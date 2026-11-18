using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using Forms=System.Windows.Forms;

namespace Frostpane
{
    internal sealed partial class FrostApp
    {
        private WeatherController weather;
        private FriendsPane friends;
        private Overlay giftMonitor;
        private string screenKey="",dailyGiftOpened="";
        private bool updatingWeather,displayAsleep,onBattery;
        private IntPtr powerNotice;
        private DateTime nextPlough=DateTime.Now.AddMinutes(15),nextSanta=DateTime.Now.AddHours(2);
        private readonly Dictionary<WeatherMode,Forms.ToolStripMenuItem> modeItems=new Dictionary<WeatherMode,Forms.ToolStripMenuItem>();
        private static readonly string[] EffectLabels={"Snow","Heavy snow","Rain","Sakura","Leaves","Fireflies","Starfall","Off"};
        private static readonly string[] Schedules={"Manual","Random","Season","Local"};
        private bool Snowing {get {return prefs.Weather==WeatherMode.Snow || prefs.Weather==WeatherMode.HeavySnow;}}
        [DllImport("user32.dll")] private static extern IntPtr RegisterPowerSettingNotification(IntPtr recipient,ref Guid setting,uint flags);
        [DllImport("user32.dll")] private static extern bool UnregisterPowerSettingNotification(IntPtr handle);
        private static Guid DisplayState=new Guid("6fe69556-704a-47a0-8f24-c28d936fda47");

        private void SetupStudio()
        {
            friends=new FriendsPane(GiftSource,Summon,ReceiveGift,
                delegate(string id) { return overlays.Exists(o=>o.Surface.Scene.IsGiftInTransit(id)); },Preferences.DirectoryName);
            Control<Border>("FriendsHost").Child=friends;
            weather=new WeatherController(delegate(WeatherMode mode,string status) {
                Control<TextBlock>("ScheduleStatus").Text=status;
                if (Enum.IsDefined(typeof(WeatherMode),mode)) SetWeather(mode,false);
            });
            weather.Southern=prefs.Southern;
            foreach(WeatherMode item in Enum.GetValues(typeof(WeatherMode))) {
                WeatherMode value=item; var radio=Control<RadioButton>("Mode"+item); radio.IsChecked=prefs.Weather==value;
                radio.Checked+=delegate { if (!updatingWeather) SetWeather(value,true); };
            }
            foreach(string item in Schedules) {
                var schedule=(WeatherSchedule)Enum.Parse(typeof(WeatherSchedule),item);
                var radio=Control<RadioButton>("Schedule"+item); radio.IsChecked=prefs.Schedule==schedule;
                radio.Checked+=delegate { if (!updatingWeather) SetSchedule(schedule); };
            }
            Control<TextBox>("WeatherCity").Text=prefs.City;
            Control<Button>("WeatherLookup").Click+=delegate { MatchCity(); };
            Control<TextBox>("WeatherCity").KeyDown+=delegate(object o,KeyEventArgs e) { if(e.Key==Key.Enter) {MatchCity();e.Handled=true;} };
            Control<StackPanel>("LocalWeatherBox").Visibility=prefs.Schedule==WeatherSchedule.Local?Visibility.Visible:Visibility.Collapsed;
            var lightning=Control<CheckBox>("LightningOption"); lightning.IsChecked=prefs.Lightning;
            BindToggle(lightning,delegate(bool value) {prefs.Lightning=value;ApplyPreferences();});
            var battery=Control<CheckBox>("BatteryOption"); battery.IsChecked=prefs.SaveBattery;
            BindToggle(battery,delegate(bool value) {prefs.SaveBattery=value;CheckPower();});
            SetupOption("VisitsOption",prefs.AutoVisitors,delegate(bool v){prefs.AutoVisitors=v;});
            SetupOption("BehindOption",prefs.BehindWindows,delegate(bool v){prefs.BehindWindows=v;foreach(Overlay o in overlays)PollOverlay(o);});
            SetupOption("BanksOption",prefs.WindowBanks,delegate(bool v){prefs.WindowBanks=v;foreach(Overlay o in overlays)PollOverlay(o);});
            SetupOption("HemisphereOption",prefs.Southern,delegate(bool v){prefs.Southern=v;weather.Southern=v;if(prefs.Schedule==WeatherSchedule.Season) SetSchedule(prefs.Schedule);});
            Control<Button>("PloughButton").Click+=delegate { SendPlough(); };
            Control<Button>("SnowmenButton").Click+=delegate { Summon(VisitorKind.Snowmen); };
            Control<Button>("YetiButton").Click+=delegate { Summon(VisitorKind.Yeti); };
            Control<Button>("SantaButton").Click+=delegate { Summon(VisitorKind.Santa); };
        }
        private void EnsureDecorationGallery()
        {
            var host=Control<Border>("DecorGalleryHost");
            if (host.Child!=null) return;
            var picker=new DecorationPicker(delegate(DecorationKind kind) {
                prefs.Decoration=kind; ActivateTool(PlayTool.Decorate);
            });
            picker.SelectKind(prefs.Decoration);
            host.Child=picker;
            UpdateTreePreview();
        }

        private void ConnectTreeDesigner()
        {
            var palette=Control<ComboBox>("TreePalette");
            palette.SelectedIndex=prefs.TreePalette;
            palette.SelectionChanged+=delegate {
                if(palette.SelectedIndex<0) return;
                prefs.TreePalette=palette.SelectedIndex;
                UpdateTreePreview();ApplyPreferences();SaveSoon();
            };
            BindTreeTrim("TreeBaubles",TreeTrim.Baubles);
            BindTreeTrim("TreeLights",TreeTrim.Lights);
            BindTreeTrim("TreeTwinkle",TreeTrim.Twinkle);
            Control<Button>("PlantTreeButton").Click+=delegate{ActivateTool(PlayTool.Tree);};
            Control<Button>("RestyleTreeButton").Click+=delegate{ActivateTool(PlayTool.StyleTree);};
        }

        private void BindTreeTrim(string name,TreeTrim flag)
        {
            SetupOption(name,(prefs.TreeTrimOptions&flag)!=0,delegate(bool enabled) {
                if(enabled) prefs.TreeTrimOptions|=flag;else prefs.TreeTrimOptions&=~flag;
                UpdateTreePreview();ApplyPreferences();
            });
        }

        private void UpdateTreePreview()
        {
            Control<Image>("TreePreview").Source=SnowArtwork.TreePreview(prefs.TreeTrimOptions,prefs.TreePalette);
        }
        private void SetupOption(string id,bool initial,Action<bool> set)
        {
            var box=Control<CheckBox>(id);box.IsChecked=initial;BindToggle(box,set);
        }
        private void RefreshScreenList(List<DesktopMonitor> monitors)
        {
            string key=String.Join("|",monitors.ConvertAll(m=>m.Id+m.Bounds.ToString()));
            if(key==screenKey)return;
            screenKey=key;var list=Control<WrapPanel>("ScreenOptions");list.Children.Clear();
            for(int i=0;i<monitors.Count;i++) {
                var m=monitors[i];
                var cb=new CheckBox {Content="Display "+(i+1)+"  ("+m.Bounds.Width+" × "+m.Bounds.Height+")",
                    Margin=new Thickness(0,3,12,3),IsChecked=!prefs.HiddenScreens.Contains(m.Id)};
                list.Children.Add(cb);
                BindToggle(cb,delegate(bool enabled) {
                    if(enabled) prefs.HiddenScreens.Remove(m.Id);else prefs.HiddenScreens.Add(m.Id);
                    foreach(Overlay o in overlays) PollOverlay(o);
                });
            }
        }
        private bool RedeemPresent(string day)
        {
            if(day==dailyGiftOpened) return false;
            try {
                string path=System.IO.Path.Combine(Preferences.DirectoryName,"last-present.txt");
                if(System.IO.File.Exists(path) && System.IO.File.ReadAllText(path)==day) {dailyGiftOpened=day;return false;}
                System.IO.Directory.CreateDirectory(Preferences.DirectoryName);System.IO.File.WriteAllText(path,day);
            } catch(System.IO.IOException) { } catch(UnauthorizedAccessException) { }
            dailyGiftOpened=day;return true;
        }
        private void SetWeather(WeatherMode value,bool manual)
        {
            updatingWeather=true;
            try {
                if (manual && prefs.Schedule!=WeatherSchedule.Manual) {
                    prefs.Schedule=WeatherSchedule.Manual; weather.Configure(prefs.Schedule,prefs.City);
                    Control<RadioButton>("ScheduleManual").IsChecked=true;
                    Control<TextBlock>("ScheduleStatus").Text="";
                    Control<StackPanel>("LocalWeatherBox").Visibility=Visibility.Collapsed;
                }
                prefs.Weather=value; Control<RadioButton>("Mode"+value).IsChecked=true;
            } finally { updatingWeather=false; }
            if (building && !Snowing) SetBuild(false);
            if (panelTools!=null) ApplyPreferences();
            foreach (Overlay o in overlays) {PollOverlay(o);o.Surface.InvalidateVisual();}
            foreach(var pair in modeItems) pair.Value.Checked=pair.Key==value;
            if (!loading) { SaveSoon(); ScheduleFrames(); }
        }
        private void SetSchedule(WeatherSchedule schedule)
        {
            prefs.Schedule=schedule; updatingWeather=true;
            try { Control<RadioButton>("Schedule"+schedule).IsChecked=true; } finally {updatingWeather=false;}
            Control<StackPanel>("LocalWeatherBox").Visibility=schedule==WeatherSchedule.Local?Visibility.Visible:Visibility.Collapsed;
            Control<TextBlock>("ScheduleStatus").Text=schedule==WeatherSchedule.Local?
                (prefs.City.Length==0?"Choose a city to match its weather.":"Checking Open-Meteo…"):"";
            weather.Configure(schedule,prefs.City); SaveSoon();
        }
        private void MatchCity()
        {
            string place=Control<TextBox>("WeatherCity").Text.Trim();
            if(place.Length==0) {Control<TextBlock>("ScheduleStatus").Text="Enter a city or latitude, longitude.";return;}
            prefs.City=place;SetSchedule(WeatherSchedule.Local);
        }
        private void EnsureSnow() { if (!Snowing) SetWeather(WeatherMode.Snow,true); }
        private void OpenPage(string page)
        {
            OpenPanel(); Control<RadioButton>(page+"Tab").IsChecked=true;
            ShowPage(page); if(page=="Friends") friends.RefreshSelection();
        }
        private Overlay CurrentMonitor()
        {
            var pt=Forms.Cursor.Position;
            foreach (Overlay o in overlays) if(o.MonitorInfo.Work.Contains(pt) && !o.Suspended) return o;
            foreach (Overlay o in overlays) if(!o.Suspended) return o;
            return null;
        }
        private SnowScene GiftSource()
        {
            var o=giftMonitor!=null && overlays.Contains(giftMonitor) && !giftMonitor.Suspended?giftMonitor:CurrentMonitor();
            return o!=null?o.Surface.Scene:null;
        }
        private void OpenGift(Overlay from) {giftMonitor=from;OpenPage("Friends");}
        private Overlay DesktopForVisit()
        {
            EnsureSnow();if (paused) TogglePause();
            var target=CurrentMonitor();
            if(target!=null) {
                if (building) SetBuild(false);
                ShowPanel(true);
            }
            else {
                OpenPage("Weather");
                Control<Expander>("DisplayOptions").IsExpanded=true;
                Control<TextBlock>("ScheduleStatus").Text="Enable a display or leave fullscreen to see a visitor.";
            }
            return target;
        }
        private void Summon(VisitorKind kind)
        {
            var target=DesktopForVisit();
            if(target!=null) target.Surface.Scene.SendVisitors(kind);
        }
        private void ReceiveGift(GiftPayload gift)
        {
            var target=CurrentMonitor();
            if(target==null || paused || displayAsleep) throw new InvalidOperationException("Your gift is waiting for an active display.");
            EnsureSnow();
            target.Surface.Scene.DeliverGift(gift);
        }
        private void SendPlough()
        {
            var target=DesktopForVisit();
            if(target!=null) target.Surface.Scene.SendSnowplough();
        }
        private void UpdateGrab(Overlay o)
        {
            o.SetGrab(prefs.DirectGrab && Snowing && !paused && !building && !displayAsleep);
        }
        private void UpdateWeatherPointer()
        {
            var pos=Forms.Cursor.Position; var p=new Point(pos.X,pos.Y);
            foreach(Overlay o in overlays) {
                bool inside=!o.Suspended && o.MonitorInfo.Work.Contains(pos) && !panel.IsMouseOver;
                Point local=inside?o.Surface.PointFromScreen(p):new Point();
                o.Surface.Scene.SetWeatherPointer(local.X,local.Y,inside);
            }
        }
        private void CheckPower()
        {
            onBattery=Forms.SystemInformation.PowerStatus.PowerLineStatus==Forms.PowerLineStatus.Offline;
            TimeSpan target=TimeSpan.FromMilliseconds(onBattery && prefs.SaveBattery?66:33);
            if (animation.Interval!=target) animation.Interval=target;
            if(!paused && Snowing && !displayAsleep && !building && CurrentMonitor()!=null && !CurrentMonitor().Suspended && prefs.AutoVisitors) {
                if (DateTime.Now>=nextPlough) {nextPlough=DateTime.Now.AddMinutes(20);CurrentMonitor().Surface.Scene.SendSnowplough();}
                if (DateTime.Now>=nextSanta) {nextSanta=DateTime.Now.AddHours(3);CurrentMonitor().Surface.Scene.SendVisitors(VisitorKind.Santa);}
            }
        }
        private void PowerMessage(int msg,IntPtr wp,IntPtr lp)
        {
            if(msg!=0x218) return;
            int eventId=wp.ToInt32();
            if(eventId==0x8013 && lp!=IntPtr.Zero && (Guid)Marshal.PtrToStructure(lp,typeof(Guid))==DisplayState && Marshal.ReadInt32(lp,16)>=4)
                displayAsleep=Marshal.ReadInt32(lp,20)==0;
            else if (eventId==4) displayAsleep=true;
            else if (eventId==7 || eventId==18) displayAsleep=false;
            else return;
            if(!loading) { foreach(Overlay o in overlays) PollOverlay(o); ScheduleFrames(); }
        }
        private void AddStudioMenu(Forms.ContextMenuStrip strip)
        {
            var modes=new Forms.ToolStripMenuItem("Weather");strip.Items.Add(modes);
            foreach(WeatherMode mode in Enum.GetValues(typeof(WeatherMode))) {
                var captured=mode; var item=(Forms.ToolStripMenuItem)modes.DropDownItems.Add(EffectLabels[(int)mode],null,delegate { SetWeather(captured,true); });
                modeItems.Add(mode,item);item.Checked=mode==prefs.Weather;
            }
            modes.DropDownItems.Add(new Forms.ToolStripSeparator());
            modes.DropDownItems.Add("Match my weather…",null,delegate { OpenPage("Weather");SetSchedule(WeatherSchedule.Local); });
            modes.DropDownItems.Add("Random weather",null,delegate {SetSchedule(WeatherSchedule.Random);});
            modes.DropDownItems.Add("Match the season",null,delegate {SetSchedule(WeatherSchedule.Season);});
            var wind=new Forms.ToolStripMenuItem("Wind");strip.Items.Add(wind);
            string[] labels={"Left breeze","Calm","Right breeze"};int[] winds={-40,0,40};
            for(int i=0;i<labels.Length;i++) {int v=winds[i];wind.DropDownItems.Add(labels[i],null,delegate {Control<Slider>("Wind").Value=v;});}
            var tools=new Forms.ToolStripMenuItem("Desktop tools");
            PlayPalette.AddToolCommands(delegate(PlayTool tool,string label) {
                tools.DropDownItems.Add(label,null,delegate {ActivateTool(tool);});
            });
            strip.Items.Add(tools);
            strip.Items.Add("Send snowplough",null,delegate {SendPlough();});
            strip.Items.Add("Add Christmas tree",null,delegate {ActivateTool(PlayTool.Tree);});
            strip.Items.Add("Send snowmen",null,delegate {Summon(VisitorKind.Snowmen);});
            strip.Items.Add("Send Yeti",null,delegate {Summon(VisitorKind.Yeti);});
            strip.Items.Add("Send Santa",null,delegate {Summon(VisitorKind.Santa);});
            strip.Items.Add("Send a train to a friend…",null,delegate {OpenPage("Friends");});
            strip.Items.Add("Decorate…",null,delegate {OpenPage("Decor");});
            strip.Items.Add(new Forms.ToolStripSeparator());
        }
        private void CloseStudio()
        {
            if(powerNotice!=IntPtr.Zero) UnregisterPowerSettingNotification(powerNotice);
            if(friends!=null) friends.ClosePane();
        }
    }
}
