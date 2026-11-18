using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace Frostpane
{
    internal sealed class FriendsPane : StackPanel
    {
        private readonly Func<SnowScene> source;
        private readonly Action<GiftPayload> deliver;
        private readonly Func<string,bool> inTransit;
        private readonly GiftPost post;
        private readonly ComboBox types=new ComboBox(), friends=new ComboBox();
        private readonly TextBox displayName=new TextBox(), note=new TextBox();
        private readonly TextBlock status=new TextBlock(), connection=new TextBlock(), lastGift=new TextBlock();
        private readonly Button detach,send,replay;
        private bool busy,closed;
        private string peersKey="";
        private GiftPayload recent;
        private readonly Dictionary<string,GiftPayload> scheduled=new Dictionary<string,GiftPayload>();
        private readonly HashSet<string> arrived=new HashSet<string>();

        internal FriendsPane(Func<SnowScene> sourceScene,Action<VisitorKind> summon,Action<GiftPayload> deliverGift,
            Func<string,bool> giftInTransit,string localSettingsDirectory)
        {
            source=sourceScene;deliver=deliverGift;inTransit=giftInTransit;post=new GiftPost(localSettingsDirectory);
            AddHeading("Send a gift");
            Row(this,"Your name",displayName);displayName.MaxLength=32;displayName.Text=post.DisplayName;
            foreach(GiftType t in Enum.GetValues(typeof(GiftType)))types.Items.Add(t);
            types.SelectedIndex=0;Row(this,"Gift",types);
            Row(this,"Note",note);note.MaxLength=280;note.AcceptsReturn=false;
            var gifts=new WrapPanel();Children.Add(gifts);
            gifts.Children.Add(ActionButton("Copy gift to send",CopyGift));
            gifts.Children.Add(ActionButton("Save gift file…",Export));gifts.Children.Add(ActionButton("Open gift file…",Import));
            Children.Add(new TextBlock{Text="Paste the copied file into a chat or email. Your friend opens the attachment in Jake Frost.",
                TextWrapping=TextWrapping.Wrap,FontSize=12,Margin=new Thickness(0,3,0,6)});
            lastGift.TextWrapping=TextWrapping.Wrap;lastGift.FontSize=12;lastGift.Margin=new Thickness(0,6,0,0);Children.Add(lastGift);
            replay=ActionButton("Replay last delivery",delegate { if(recent!=null)deliver(recent); });
            replay.HorizontalAlignment=HorizontalAlignment.Left;replay.Visibility=Visibility.Collapsed;Children.Add(replay);
            status.TextWrapping=TextWrapping.Wrap;status.FontSize=12;status.Foreground=new SolidColorBrush(Color.FromRgb(193,214,201));
            status.Margin=new Thickness(0,6,0,0);Children.Add(status);
            var shared=new StackPanel();
            Children.Add(new Expander {Header="Shared-folder delivery",Content=shared,IsExpanded=!string.IsNullOrEmpty(post.Folder),Margin=new Thickness(0,8,0,0),Foreground=Brushes.White});
            connection.TextWrapping=TextWrapping.Wrap;connection.FontSize=12;connection.Margin=new Thickness(0,2,0,6);shared.Children.Add(connection);
            var links=new WrapPanel();shared.Children.Add(links);
            links.Children.Add(ActionButton("Connect shared folder…",Connect));
            detach=ActionButton("Disconnect",delegate { Work(delegate {post.Disconnect();},delegate {Message("Disconnected."); UpdateConnection();Poll();}); });links.Children.Add(detach);
            Row(shared,"Send to",friends);friends.MinWidth=160;
            send=ActionButton("Send to friend",Send);send.HorizontalAlignment=HorizontalAlignment.Left;shared.Children.Add(send);
            AddHeading("Visitors");
            var visitors=new WrapPanel();Children.Add(visitors);
            foreach(VisitorKind v in Enum.GetValues(typeof(VisitorKind))) {
                VisitorKind kind=v;
                string label=v==VisitorKind.Snowmen?"Send snowmen":v==VisitorKind.Train?"Elf train":v.ToString();
                visitors.Children.Add(ActionButton(label,delegate { summon(kind); }));
            }
            UpdateConnection();Poll();
        }
        private void AddHeading(string text) {
            Children.Add(new TextBlock {Text=text,FontSize=14,FontWeight=FontWeights.SemiBold,Margin=new Thickness(0,9,0,3)});
        }
        private void Row(Panel parent,string label,Control input) {
            var row=new DockPanel { Margin=new Thickness(0,2,0,3) };
            var name=new TextBlock {Text=label,Width=75,VerticalAlignment=VerticalAlignment.Center};
            DockPanel.SetDock(name,Dock.Left);row.Children.Add(name);
            input.Padding=new Thickness(5,2,5,2);AutomationProperties.SetName(input,label);row.Children.Add(input);parent.Children.Add(row);
        }
        private Button ActionButton(string text,Action action) {
            var b=new Button {Content=text,Padding=new Thickness(9,4,9,4),Margin=new Thickness(0,3,5,0)};
            b.Click+=delegate { try { action(); }catch(Exception e){Message(e.Message);} };return b;
        }
        private void Message(string s) { status.Text=s; }
        private void UpdateConnection() {
            bool linked=!string.IsNullOrEmpty(post.Folder);
            connection.Text=linked?"Connected to "+Path.GetFileName(post.Folder)+". Folder members can read gifts.":
                "Choose the same shared or synced folder as your friend, or exchange a gift file.";
            detach.IsEnabled=linked;send.IsEnabled=linked;friends.IsEnabled=linked;
            if(!linked){peersKey="";friends.Items.Clear();}
        }
        internal void RefreshSelection() {
            SnowScene scene=source();
            if(scene!=null && scene.SelectedGiftType!=GiftType.Note) {
                types.SelectedItem=scene.SelectedGiftType;Message("Your selected "+scene.SelectedGiftType.ToString().ToLowerInvariant()+" is ready to send.");
            }
        }
        private GiftPayload Compose() {
            GiftType type=types.SelectedItem==null?GiftType.Note:(GiftType)types.SelectedItem;
            if(type==GiftType.Note && string.IsNullOrWhiteSpace(note.Text))throw new InvalidOperationException("Write a note for your friend.");
            if(type==GiftType.Note)return new GiftPayload{Kind=GiftType.Note,Note=note.Text};
            SnowScene scene=source();
            if(scene==null)throw new InvalidOperationException("Open a desktop snow scene first.");
            return scene.CaptureGift(type,note.Text);
        }
        private void Connect() {
            string name=GiftPayload.Name(displayName.Text);
            if(name.Length==0){Message("Enter your display name first.");displayName.Focus();return;}
            using(var picker=new Forms.FolderBrowserDialog {Description="Choose the shared folder you and your friend can both access."}) {
                if(picker.ShowDialog()!=Forms.DialogResult.OK)return;
                string folder=picker.SelectedPath;
                Work(delegate{post.Connect(folder,name);},delegate{UpdateConnection();Message("Connected as "+name+".");Poll();});
            }
        }
        private void Send() {
            var friend=friends.SelectedItem as PostFriend;
            if(friend==null) {Message("Choose a friend. They can join through the same shared folder.");return;}
            var payload=Compose();
            Work(delegate{post.Send(payload,friend);},delegate{Message("Gift sent to "+friend.Name+".");note.Clear();});
        }
        private void Export() {
            GiftPayload gift=Compose();
            var picker=new SaveFileDialog {Filter="Jake Frost gifts (*.fpgift)|*.fpgift",DefaultExt=".fpgift",AddExtension=true,FileName="Winter gift.fpgift"};
            if(picker.ShowDialog()!=true)return;
            string path=picker.FileName,name=displayName.Text;
            Work(delegate{post.Export(path,gift,name);},delegate{Message("Gift file saved. Share it with your friend.");});
        }
        private void CopyGift() {
            GiftPayload gift=Compose();
            string folder=Path.Combine(Path.GetTempPath(),"Jake Frost gifts");
            string path=Path.Combine(folder,gift.Kind+"-"+gift.Id+".fpgift");
            string name=displayName.Text;
            Work(delegate{Directory.CreateDirectory(folder);post.Export(path,gift,name);},delegate {
                try {
                    var files=new StringCollection();files.Add(path);Clipboard.SetFileDropList(files);
                    Message("Gift copied. Paste it into a chat or email that accepts file attachments.");
                } catch(System.Runtime.InteropServices.ExternalException) {
                    Message("The clipboard is busy. Try again or choose Save gift file.");
                }
            });
        }
        private void Import() {
            var picker=new OpenFileDialog {Filter="Jake Frost gifts (*.fpgift)|*.fpgift",CheckFileExists=true};
            if(picker.ShowDialog()!=true)return;
            string path=picker.FileName;
            Work(delegate{post.Import(path);},delegate{Message("Gift file checked.");Poll();});
        }
        private void Work(Action action,Action finish) {
            // File operations may wait for a user's chosen sync provider.
            ThreadPool.QueueUserWorkItem(delegate {
                string error=null;try{action();}catch(Exception e){error=e.Message;}
                if(Dispatcher.HasShutdownStarted)return;
                Dispatcher.BeginInvoke(new Action(delegate{if(closed)return;if(error!=null)Message(error);else finish();}));
            });
        }
        internal void Poll() {
            if(closed||busy)return;busy=true;
            ThreadPool.QueueUserWorkItem(delegate {
                List<PostFriend> peers=null;List<GiftPayload> inbox=null;GiftPayload latest=null;string warning=null;
                try {inbox=post.Receive();latest=post.Latest();}catch(Exception e){warning=e.Message;}
                try {peers=post.Friends();}catch(Exception e){warning=e.Message;}
                if(Dispatcher.HasShutdownStarted)return;
                Dispatcher.BeginInvoke(new Action(delegate{
                    if(closed){busy=false;return;}
                    if(warning!=null)Message(warning);
                    string key="";if(peers!=null)foreach(PostFriend f in peers)key+=f.Id+f.Name;
                    if(peers!=null && key!=peersKey){
                        string selected=friends.SelectedItem is PostFriend?((PostFriend)friends.SelectedItem).Id:"";
                        friends.Items.Clear();foreach(PostFriend f in peers){friends.Items.Add(f);if(f.Id==selected)friends.SelectedItem=f;}
                        if(friends.SelectedIndex<0 && peers.Count>0)friends.SelectedIndex=0;peersKey=key;
                    }
                    recent=latest;
                    try {
                        if(inbox!=null)foreach(GiftPayload g in inbox) {
                            if(arrived.Contains(g.Id)) {
                                post.Acknowledge(g);
                                arrived.Remove(g.Id);scheduled.Remove(g.Id);recent=g;
                            } else if(!inTransit(g.Id)) {
                                deliver(g);scheduled[g.Id]=g;
                            }
                        }
                        if(recent!=null) {
                            lastGift.Text="From "+recent.Sender+" · "+recent.Kind+(recent.Note.Length==0?"":" — "+recent.Note);
                            replay.Visibility=Visibility.Visible;
                        }
                    }catch(Exception e){Message(e.Message);}finally{busy=false;}
                }));
            });
        }
        internal void GiftArrived(string id)
        {
            if(scheduled.ContainsKey(id)) arrived.Add(id);
        }
        internal void ClosePane()
        {
            closed=true;
            foreach(string id in arrived) {
                try { post.Acknowledge(scheduled[id]); }
                catch(IOException) { } catch(UnauthorizedAccessException) { }
            }
        }
    }
}
