using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

namespace Frostpane
{
    internal sealed class OnlineContact
    {
        public string id {get;set;}
        public string secret {get;set;}
        public string token {get;set;}
        public string ownName {get;set;}
        public string name {get;set;}
        public string status {get;set;}
        public bool owner {get;set;}
        public override string ToString() { return status=="active" ? name : "Invitation · " + (owner ? "waiting" : "joining"); }
    }
    internal sealed class OnlineLetter { public string id {get;set;} public string body {get;set;} }
    internal sealed class OnlineState
    {
        public string id {get;set;}
        public string name {get;set;}
        public string status {get;set;}
        public OnlineLetter[] messages {get;set;}
    }
    internal sealed class OnlineReply
    {
        public string error {get;set;}
        public string name {get;set;}
        public OnlineState[] contacts {get;set;}
    }
    internal sealed class OnlineError : IOException
    {
        internal int Status;
        internal OnlineError(int status,string message) : base(message) { Status=status; }
    }

    internal sealed class OnlinePost
    {
        internal const string Address="https://jake-frost-mail.netlify.app/api/post";
        private readonly object gate=new object();
        private readonly string file;
        private readonly Uri endpoint;
        private readonly JavaScriptSerializer json=new JavaScriptSerializer { MaxJsonLength=256000, RecursionLimit=12 };
        private List<OnlineContact> contacts;
        internal OnlinePost(string directory) : this(directory,new Uri(Address)) {}
        internal OnlinePost(string directory,Uri relay)
        {
            if(relay.Scheme!=Uri.UriSchemeHttps && !(relay.Scheme==Uri.UriSchemeHttp && relay.IsLoopback))
                throw new ArgumentException("The friend relay requires HTTPS.");
            endpoint=relay; file=Path.Combine(directory,"GiftPost","online-v1.dat");
        }
        private List<OnlineContact> Load()
        {
            if(contacts!=null)return contacts;
            if(!File.Exists(file))return contacts=new List<OnlineContact>();
            byte[] sealedFile=Convert.FromBase64String(GiftPayload.ReadSmall(file,64000));
            string raw=Encoding.UTF8.GetString(ProtectedData.Unprotect(sealedFile,null,DataProtectionScope.CurrentUser));
            var rows=json.Deserialize<List<OnlineContact>>(raw);
            if(rows==null || rows.Count>16)throw new InvalidDataException("Cannot read the online friend list.");
            foreach(var c in rows) {
                if(c==null || c.id!=FriendEnvelope.Id(c.secret) || FriendEnvelope.Key(c.token).Length!=32)
                    throw new InvalidDataException("Cannot read the online friend list.");
            }
            return contacts=rows;
        }
        private void Save()
        {
            Directory.CreateDirectory(Path.GetDirectoryName(file));
            var bytes=Encoding.UTF8.GetBytes(json.Serialize(contacts));
            byte[] protectedBytes=ProtectedData.Protect(bytes,null,DataProtectionScope.CurrentUser);
            GiftPayload.AtomicWrite(file,Convert.ToBase64String(protectedBytes),true);
        }
        private static string Display(string value)
        {
            string name=GiftPayload.Name(value);
            if(name.Length==0)throw new InvalidOperationException("Enter your name to add a friend.");
            return name;
        }
        internal List<OnlineContact> List()
        {
            lock(gate) {
                return Load().Select(c=>new OnlineContact {id=c.id,name=c.name,ownName=c.ownName,status=c.status,owner=c.owner}).ToList();
            }
        }
        private OnlineContact Add(string key,string name,bool owner)
        {
            if(Load().Count>=16)throw new InvalidOperationException("Remove an invitation or friend to add someone new.");
            var c=new OnlineContact {id=FriendEnvelope.Id(key),secret=key,token=FriendEnvelope.Token(),ownName=name,
                owner=owner,status=owner?"creating":"joining",name=""};
            contacts.Add(c);
            try { Save(); } catch {contacts.Remove(c);throw;}
            return c;
        }
        private OnlineReply Request(object values)
        {
            var req=(HttpWebRequest)WebRequest.Create(endpoint);
            req.Method="POST";req.ContentType="application/json";req.AllowAutoRedirect=false;
            req.Timeout=10000;req.ReadWriteTimeout=10000;req.UserAgent="JakeFrost-Windows";
            byte[] bytes=Encoding.UTF8.GetBytes(json.Serialize(values));req.ContentLength=bytes.Length;
            try {
                using(var stream=req.GetRequestStream())stream.Write(bytes,0,bytes.Length);
                using(var response=req.GetResponse())return ReadResponse(response);
            } catch(WebException e) {
                using(var response=e.Response as HttpWebResponse) {
                    if(response!=null) {
                        string message=null;
                        try { message=ReadResponse(response).error; } catch(Exception) { }
                        throw new OnlineError((int)response.StatusCode,message ?? "The friend service is busy. Try again shortly.");
                    }
                }
                throw new OnlineError(0,"Cannot reach the friend service. Check your connection and try again.");
            }
        }
        private OnlineReply ReadResponse(WebResponse response)
        {
            using(var reader=new StreamReader(response.GetResponseStream(),Encoding.UTF8)) {
                var text=new StringBuilder();char[] chunk=new char[4096];int read;
                while((read=reader.Read(chunk,0,chunk.Length))>0) {
                    if(text.Length+read>256000)throw new InvalidDataException("The friend service response was too large.");
                    text.Append(chunk,0,read);
                }
                var result=json.Deserialize<OnlineReply>(text.ToString());
                if(result==null)throw new InvalidDataException("Invalid friend service response.");
                return result;
            }
        }
        private void CompleteInvitation(OnlineContact c)
        {
            bool owner=c.owner;
            var response=Request(new {action=owner?"invite":"accept",c.id,c.token,proof=FriendEnvelope.Proof(c.secret),
                name=FriendEnvelope.Seal(c.secret,owner?"name/a":"name/b",c.ownName)});
            if(!owner)c.name=Display(FriendEnvelope.Open(c.secret,"name/a",response.name));
            c.status=owner?"pending":"active"; Save();
        }
        internal string Invite(string display)
        {
            lock(gate) {
                string name=Display(display);
                var c=Load().FirstOrDefault(x=>x.owner && (x.status=="creating" || x.status=="pending"));
                if(c==null)c=Add(FriendEnvelope.Token(),name,true);
                if(c.status=="creating")CompleteInvitation(c);
                return "JF1-"+c.secret;
            }
        }
        internal string Accept(string code,string display)
        {
            lock(gate) {
                code=(code??"").Trim();
                if(!code.StartsWith("JF1-",StringComparison.Ordinal))throw new InvalidDataException("Paste the full JF1 invitation code.");
                string secret=code.Substring(4),id=FriendEnvelope.Id(secret),name=Display(display);
                var c=Load().FirstOrDefault(x=>x.id==id);
                if(c!=null && c.owner)throw new InvalidOperationException("Share your invitation with another person.");
                if(c!=null && c.status=="active")return c.name;
                if(c==null)c=Add(secret,name,false);
                try {CompleteInvitation(c);}
                catch(OnlineError e) {
                    if(e.Status==400 || e.Status==403 || e.Status==404 || e.Status==409 || e.Status==410) {
                        contacts.Remove(c);Save();
                    }
                    throw;
                }
                return c.name;
            }
        }
        private OnlineContact Find(string id)
        {
            var c=Load().FirstOrDefault(x=>x.id==id);
            if(c==null)throw new InvalidOperationException("Choose a friend.");
            return c;
        }
        internal void Remove(string id)
        {
            lock(gate) {
                var c=Find(id);Request(new {action="remove",c.id,c.token});contacts.Remove(c);Save();
            }
        }
        internal void Send(string id,GiftPayload gift)
        {
            lock(gate) {
                var c=Find(id);
                if(c.status!="active")throw new InvalidOperationException("Your friend must accept the invitation first.");
                gift.Sender=c.ownName;gift.SenderId="";gift.RecipientId="";
                string content=gift.Encode();GiftPayload.DecodeGift(content);
                string side=c.owner?"b":"a";
                Request(new { action="send",c.id,c.token,giftId=gift.Id,
                    body=FriendEnvelope.Seal(c.secret,"gift/"+side+"/"+gift.Id,content) });
            }
        }
        internal void Poll(Action<GiftPayload> accept)
        {
            lock(gate) {
                if(Load().Count==0)return;
                // Deliberate invitation retries use the same persisted device token.
                var ready=contacts.Where(c=>c.status=="pending" || c.status=="active").ToArray();
                if(ready.Length==0)return;
                var response=Request(new {action="poll",contacts=ready.Select(c=>new {c.id,c.token}).ToArray()});
                if(response.contacts==null || response.contacts.Length!=ready.Length)throw new InvalidDataException("Incomplete friend service response.");
                foreach(var row in response.contacts) {
                    var c=Find(row.id);
                    if(row.status=="gone"){contacts.Remove(c);Save();continue;}
                    if(row.status!="active")continue;
                    string side=c.owner?"a":"b",other=c.owner?"b":"a";
                    string otherName=Display(FriendEnvelope.Open(c.secret,"name/"+other,row.name));
                    if(c.status!="active" || c.name!=otherName) {c.name=otherName;c.status="active";Save();}
                    foreach(var letter in row.messages ?? new OnlineLetter[0]) {
                        if(!GiftPayload.IsId(letter.id))throw new InvalidDataException("Invalid delivery identifier.");
                        GiftPayload gift=null;
                        // A corrupt letter must not keep valid mail queued behind it.
                        try {
                            string raw=FriendEnvelope.Open(c.secret,"gift/"+side+"/"+letter.id,letter.body);
                            var decoded=GiftPayload.DecodeGift(raw);
                            if(decoded.Id==letter.id && decoded.RecipientId=="" && decoded.SenderId=="")gift=decoded;
                        } catch(InvalidDataException) {} catch(FormatException) {} catch(CryptographicException) {} catch(ArgumentException) {}
                        if(gift!=null){gift.Sender=c.name;accept(gift);}
                        Request(new { action="ack",c.id,c.token,giftId=letter.id });
                    }
                }
            }
        }
    }
}
