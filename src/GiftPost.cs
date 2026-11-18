using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

namespace Frostpane
{
    internal enum GiftType { Note, Snowman, Tree }
    internal sealed class GiftPayload
    {
        internal string Id=Guid.NewGuid().ToString("N"), SenderId="",RecipientId="",Sender="A friend",Note="",Dress="";
        internal GiftType Kind;
        internal int Style;
        internal double Size=18,Mid=13,Head=9,Facing=1;
        private static readonly UTF8Encoding Utf8=new UTF8Encoding(false,true);
        private static string Number(double n) { return n.ToString("R",CultureInfo.InvariantCulture); }
        internal static bool IsId(string id) { Guid temp;return id!=null && Guid.TryParseExact(id,"N",out temp); }
        internal static string Name(string s) { return Plain(s,32).Trim(); }
        private static string Plain(string s,int max)
        {
            s=s??""; if (s.Length>max) throw new InvalidDataException("Text is too long.");
            var result=new StringBuilder();
            foreach(char c in s) {
                if(c=='\r' || c=='\n' || c=='\t') result.Append(' ');
                else if (!char.IsControl(c)) result.Append(c);
            }
            return result.ToString();
        }
        private static string B64(string s) { return Convert.ToBase64String(Utf8.GetBytes(s)); }
        private static string Decode(string s,int max) {
            if (s.Length>max*6+8) throw new InvalidDataException("Gift is too large.");
            string value=Utf8.GetString(Convert.FromBase64String(s));if(value.Length>max)throw new InvalidDataException("Gift is too large.");return value;
        }
        internal string Encode() {
            string result=string.Join("\n",new[]{ "FROSTPANE-GIFT-1",Id,SenderId,RecipientId,B64(Name(Sender)),Kind.ToString(),
                B64(Plain(Note,280)),Style.ToString(CultureInfo.InvariantCulture),Number(Size),Number(Mid),Number(Head),Number(Facing),B64(Dress??""),"END" });
            if(result.Length>20000) throw new InvalidDataException("Gift is too large."); return result;
        }
        private static double ReadNumber(string s,double low,double high) {
            double n;if(s.Length>32 || !double.TryParse(s,NumberStyles.Float,CultureInfo.InvariantCulture,out n) || !(n>=low&&n<=high))
                throw new InvalidDataException("Invalid item dimensions."); return n;
        }
        internal static GiftPayload DecodeGift(string data) {
            if(data.Length>20000)throw new InvalidDataException("Gift is too large.");
            string[] l=data.Replace("\r","").Split('\n');
            GiftType kind;int style;
            if(l.Length!=14 || l[0]!="FROSTPANE-GIFT-1" || l[13]!="END" || !IsId(l[1]) || (l[2]!=""&&!IsId(l[2])) ||
                (l[3]!=""&&!IsId(l[3])) || !Enum.TryParse(l[5],out kind) || !Enum.IsDefined(typeof(GiftType),kind) ||
                !int.TryParse(l[7],NumberStyles.Integer,CultureInfo.InvariantCulture,out style) || style<0 || style>63)
                throw new InvalidDataException("This file is not a Jake Frost gift.");
            var g=new GiftPayload { Id=l[1],SenderId=l[2],RecipientId=l[3],Sender=Name(Decode(l[4],32)),
                Kind=kind,Note=Plain(Decode(l[6],280),280),Style=style,Size=ReadNumber(l[8],3,160),
                Mid=ReadNumber(l[9],1,64),Head=ReadNumber(l[10],1,64),Facing=ReadNumber(l[11],-1,1),Dress=Decode(l[12],8192) };
            if(g.Kind==GiftType.Snowman && (g.Size>50||g.Mid>50||g.Head>50))throw new InvalidDataException("Invalid snowman proportions.");
            return g;
        }
        internal static string ReadSmall(string path,int maximum) {
            using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                if(stream.Length>maximum)throw new InvalidDataException("File is too large.");
                var buffer=new byte[maximum+1];int pos=0,n;
                while(pos<buffer.Length && (n=stream.Read(buffer,pos,buffer.Length-pos))>0) pos+=n;
                if(pos>maximum)throw new InvalidDataException("File is too large.");
                return Utf8.GetString(buffer,0,pos);
            }
        }
        internal static void AtomicWrite(string path,string text,bool replace) {
            string part=path+"."+Guid.NewGuid().ToString("N")+".part";
            try {
                File.WriteAllText(part,text,new UTF8Encoding(false));
                if(replace && File.Exists(path))File.Replace(part,path,null);
                else { try { File.Move(part,path); } catch(IOException) { if(replace||!File.Exists(path))throw; } }
            } finally { if(File.Exists(part)) File.Delete(part); }
        }
    }
    internal sealed class PostFriend
    {
        internal string Id,Name;
        public override string ToString(){return Name+" · "+Id.Substring(0,4);}
    }
    internal sealed class GiftPost
    {
        private readonly object gate=new object();
        private readonly string local;
        internal string Id {get;private set;}
        internal string DisplayName {get;private set;}
        internal string Folder {get;private set;}
        internal GiftPost(string settings) {
            local=Path.Combine(settings,"GiftPost");Id=Guid.NewGuid().ToString("N");DisplayName="";Folder="";
            string path=Path.Combine(local,"connection.txt");
            try {
                if(File.Exists(path)) {
                    string[] l=GiftPayload.ReadSmall(path,12000).Split('\n');
                    if(l.Length==4 && l[0]=="FROSTPANE-POST-1" && GiftPayload.IsId(l[1])) {
                        Id=l[1];DisplayName=GiftPayload.Name(l[2]); Folder=l[3];
                    }
                }
            } catch(IOException) {} catch(UnauthorizedAccessException) {} catch(ArgumentException) {}
        }
        private string Hub { get { return Path.Combine(Folder,"Frostpane Post"); } }
        private void SaveConnection() {
            Directory.CreateDirectory(local);
            GiftPayload.AtomicWrite(Path.Combine(local,"connection.txt"),string.Join("\n",new[]{"FROSTPANE-POST-1",Id,DisplayName,Folder}),true);
        }
        internal void Connect(string root,string name) {
            lock(gate) {
                name=GiftPayload.Name(name);
                if(name.Length==0)throw new InvalidDataException("Enter your display name first.");
                if(!Directory.Exists(root))throw new DirectoryNotFoundException("Choose an existing shared folder.");
                root=Path.GetFullPath(root);
                if(Folder!=""&&!string.Equals(root,Folder,StringComparison.OrdinalIgnoreCase)) Disconnect();
                string hub=Path.Combine(root,"Frostpane Post"),peers=Path.Combine(hub,"Friends");
                Directory.CreateDirectory(peers);Directory.CreateDirectory(Path.Combine(hub,"Mail",Id));
                GiftPayload.AtomicWrite(Path.Combine(peers,Id+".friend"),name,true);
                Folder=root;DisplayName=name;SaveConnection();
            }
        }
        internal void Disconnect() {
            lock(gate) {
                if(Folder!="") {
                    string mine=Path.Combine(Hub,"Friends",Id+".friend");
                    if(File.Exists(mine))File.Delete(mine);
                }
                Folder="";SaveConnection();
            }
        }
        internal List<PostFriend> Friends() {
            lock(gate) {
                var peers=new List<PostFriend>();if(Folder=="")return peers;
                foreach(string file in Directory.EnumerateFiles(Path.Combine(Hub,"Friends"),"*.friend").Take(128)) {
                    string id=Path.GetFileNameWithoutExtension(file);
                    if(!GiftPayload.IsId(id)||id==Id)continue;
                    try {
                        string name=GiftPayload.Name(GiftPayload.ReadSmall(file,150));
                        if(name.Length>0)peers.Add(new PostFriend{Id=id,Name=name});
                    } catch(InvalidDataException) {} catch(IOException) {} catch(UnauthorizedAccessException) {} catch(ArgumentException) {}
                }
                return peers.OrderBy(p=>p.Name,StringComparer.CurrentCultureIgnoreCase).ToList();
            }
        }
        internal void Send(GiftPayload g,PostFriend friend) {
            lock(gate) {
                if(Folder==""||friend==null||!GiftPayload.IsId(friend.Id)||!File.Exists(Path.Combine(Hub,"Friends",friend.Id+".friend")))
                    throw new InvalidOperationException("Choose a friend connected to this folder.");
                g.Sender=DisplayName;g.SenderId=Id;g.RecipientId=friend.Id;
                string box=Path.Combine(Hub,"Mail",friend.Id);Directory.CreateDirectory(box);
                string encoded=g.Encode(); GiftPayload.DecodeGift(encoded);
                GiftPayload.AtomicWrite(Path.Combine(box,g.Id+".fpgift"),encoded,false);
            }
        }
        internal void Export(string path,GiftPayload g,string sender) {
            g.Sender=string.IsNullOrWhiteSpace(sender)?"A friend":GiftPayload.Name(sender);
            g.SenderId=Id;g.RecipientId="";GiftPayload.AtomicWrite(path,g.Encode(),true);
        }
        private string Archive {get {return Path.Combine(local,"Received");}}
        private string Pending {get {return Path.Combine(local,"Pending");}}
        private void Accept(GiftPayload gift) {
            if(gift.RecipientId!="" && gift.RecipientId!=Id)throw new InvalidDataException("This gift is addressed to another friend.");
            Directory.CreateDirectory(Archive);Directory.CreateDirectory(Pending);
            if(File.Exists(Path.Combine(Archive,gift.Id+".fpgift")))return;
            GiftPayload.AtomicWrite(Path.Combine(Pending,gift.Id+".fpgift"),gift.Encode(),false);
        }
        internal void Import(string path) {
            lock(gate) {Accept(GiftPayload.DecodeGift(GiftPayload.ReadSmall(path,20000)));}
        }
        internal void ReceiveOnline(GiftPayload gift) {
            lock(gate) {Accept(gift);}
        }
        internal List<GiftPayload> Receive() {
            lock(gate) {
                try { if(Folder!="") {
                    string box=Path.Combine(Hub,"Mail",Id);
                    if(Directory.Exists(box)) foreach(string path in Directory.EnumerateFiles(box,"*.fpgift").Take(96)) {
                        try {
                            var g=GiftPayload.DecodeGift(GiftPayload.ReadSmall(path,20000));
                            if(g.RecipientId!=Id||g.Id!=Path.GetFileNameWithoutExtension(path))continue;
                            Accept(g);File.Delete(path);
                        } catch(InvalidDataException) {} catch(IOException) {} catch(UnauthorizedAccessException) {} catch(FormatException) {} catch(ArgumentException) {}
                    }
                } } catch(IOException) { /* Local and portable deliveries still work while the share is offline. */ }
                catch(UnauthorizedAccessException) { }
                var result=new List<GiftPayload>();
                if(Directory.Exists(Pending)) foreach(string path in Directory.EnumerateFiles(Pending,"*.fpgift").Take(5)) {
                    // A shell-open on another process may race the moment the first copy gets archived.
                    if(File.Exists(Path.Combine(Archive,Path.GetFileName(path)))) {File.Delete(path);continue;}
                    result.Add(GiftPayload.DecodeGift(GiftPayload.ReadSmall(path,20000)));
                }
                return result;
            }
        }
        internal void Acknowledge(GiftPayload g) {
            lock(gate) {
                string pending=Path.Combine(Pending,g.Id+".fpgift"),dest=Path.Combine(Archive,g.Id+".fpgift");
                if(!File.Exists(pending))return;
                if(File.Exists(dest))File.Delete(pending);else File.Move(pending,dest);
            }
        }
        internal GiftPayload Latest() {
            lock(gate) {
                var archive = new DirectoryInfo(Archive);
                if (!archive.Exists) return null;
                // EnumerateFiles supplies the timestamps with the directory entries.
                // Keep the latest in one pass, including the original tie order.
                FileInfo latest = null;
                foreach (var file in archive.EnumerateFiles("*.fpgift"))
                    if (latest == null || file.LastWriteTimeUtc > latest.LastWriteTimeUtc) latest = file;
                return latest == null ? null : GiftPayload.DecodeGift(GiftPayload.ReadSmall(latest.FullName,20000));
            }
        }
    }
}
