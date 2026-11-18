using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

[assembly: AssemblyTitle("Jake Frost")]
[assembly: AssemblyDescription("Interactive desktop snowfall")]
[assembly: AssemblyProduct("Jake Frost")]
[assembly: AssemblyVersion("4.0.2.0")]
[assembly: System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.8")]

namespace Frostpane
{
    internal sealed class Preferences
    {
        internal int Intensity=2,Wind=0,Volume=100,Depth=72,Ice=1,Palette=1,VisitorSpeed=0;
        internal int BulbSize=100;
        internal bool TwinkleLights=true;
        internal TreeTrim TreeTrimOptions=TreeTrim.All;
        internal int TreePalette=1;
        internal string LastTreeMonitor="";
        // In saved-file order: snowplow, Yeti, Santa, elf train, visiting snowmen.
        internal readonly int[] VisitorSizes={100,100,100,100,100};
        internal bool PauseFullscreen=true,ClickPuffs=true,RememberDecorations=true,DirectGrab=true,Lightning=false,SaveBattery=true;
        internal WeatherMode Weather=WeatherMode.Snow;
        internal WeatherSchedule Schedule=WeatherSchedule.Manual;
        internal string City="";
        internal DecorationKind Decoration=DecorationKind.Tree;
        internal bool AutoVisitors=true,BehindWindows=false,WindowBanks=true,Southern=false;
        internal readonly HashSet<string> HiddenScreens=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        internal PlayTool Tool=PlayTool.Puff;
        internal static string DirectoryName {
            get { return Environment.GetEnvironmentVariable("JAKEFROST_SETTINGS_DIR") ?? Environment.GetEnvironmentVariable("FROSTPANE_SETTINGS_DIR") ??
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Frostpane"); }
        }
        internal void Load()
        {
            try {
                string path=Path.Combine(DirectoryName,"settings.dat");
                string v2=Path.Combine(DirectoryName,"settings-v2.dat");
                if (File.Exists(v2)) path=v2;
                string current=Path.Combine(DirectoryName,"settings-v3.dat");
                if (File.Exists(current)) path=current;
                if (!File.Exists(path)) return;
                string[] values=File.ReadAllLines(path);
                Intensity=Number(values,0,Intensity,1,3); Wind=Number(values,1,Wind,-80,80);
                bool flag;
                if (values.Length>2 && bool.TryParse(values[2],out flag)) PauseFullscreen=flag;
                Volume=Number(values,3,Volume,0,400); Depth=Number(values,4,Depth,24,SnowScene.MaximumDriftDepth);
                Ice=Number(values,5,Ice,0,3); Palette=Number(values,6,Palette,0,2);
                if (values.Length>7 && bool.TryParse(values[7],out flag)) ClickPuffs=flag;
                PlayTool tool;
                if (values.Length>8 && Enum.TryParse(values[8],out tool) && Enum.IsDefined(typeof(PlayTool),tool)) Tool=tool;
                if (values.Length>9 && bool.TryParse(values[9],out flag)) RememberDecorations=flag;
                if (values.Length>10 && bool.TryParse(values[10],out flag)) DirectGrab=flag;
                Weather=Choice(values,11,Weather); Schedule=Choice(values,12,Schedule);
                if(values.Length>13) City=values[13].Substring(0,Math.Min(100,values[13].Length));
                if(values.Length>14 && bool.TryParse(values[14],out flag)) Lightning=flag;
                if(values.Length>15 && bool.TryParse(values[15],out flag)) SaveBattery=flag;
                Decoration=Choice(values,16,Decoration);
                if(values.Length>17 && bool.TryParse(values[17],out flag)) AutoVisitors=flag;
                if(values.Length>18 && bool.TryParse(values[18],out flag)) BehindWindows=flag;
                if(values.Length>19 && bool.TryParse(values[19],out flag)) WindowBanks=flag;
                if(values.Length>20) foreach(string id in values[20].Split('|')) if(id.Length>0 && id.Length<128) HiddenScreens.Add(id);
                if(values.Length>21 && bool.TryParse(values[21],out flag)) Southern=flag;
                VisitorSpeed=Number(values,22,VisitorSpeed,0,2);
                for (int i=0;i<VisitorSizes.Length;i++) VisitorSizes[i]=Number(values,23+i,100,50,250);
                BulbSize=Number(values,28,100,50,500);
                if(values.Length>29 && bool.TryParse(values[29],out flag)) TwinkleLights=flag;
                TreeTrimOptions=(TreeTrim)Number(values,30,(int)TreeTrim.All,0,7);
                TreePalette=Number(values,31,Palette,0,2);
                if(values.Length>32 && values[32].Length<128)LastTreeMonitor=values[32];
            } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
        private static T Choice<T>(string[] values,int index,T fallback) where T:struct
        {
            T parsed;
            return index<values.Length && Enum.TryParse(values[index],out parsed) && Enum.IsDefined(typeof(T),parsed) ? parsed : fallback;
        }
        private static int Number(string[] values,int index,int fallback,int min,int max)
        {
            int n;
            return index<values.Length && int.TryParse(values[index],NumberStyles.Integer,CultureInfo.InvariantCulture,out n)
                ? Math.Max(min,Math.Min(max,n)) : fallback;
        }
        internal void Save()
        {
            try {
                string dir=DirectoryName; Directory.CreateDirectory(dir);
                string path=Path.Combine(dir,"settings-v3.dat"), temp=path+".new";
                File.WriteAllLines(temp,new string[] {Intensity.ToString(CultureInfo.InvariantCulture),Wind.ToString(CultureInfo.InvariantCulture),PauseFullscreen.ToString(),
                    Volume.ToString(CultureInfo.InvariantCulture),Depth.ToString(CultureInfo.InvariantCulture),Ice.ToString(CultureInfo.InvariantCulture),
                    Palette.ToString(CultureInfo.InvariantCulture),ClickPuffs.ToString(),Tool.ToString(),RememberDecorations.ToString(),
                    DirectGrab.ToString(),Weather.ToString(),Schedule.ToString(),City,Lightning.ToString(),SaveBattery.ToString(),Decoration.ToString(),
                    AutoVisitors.ToString(),BehindWindows.ToString(),WindowBanks.ToString(),String.Join("|",HiddenScreens),Southern.ToString(),
                    VisitorSpeed.ToString(CultureInfo.InvariantCulture)}.Concat(
                    VisitorSizes.Select(size=>size.ToString(CultureInfo.InvariantCulture))).Concat(
                    new[]{BulbSize.ToString(CultureInfo.InvariantCulture),TwinkleLights.ToString(),
                        ((int)TreeTrimOptions).ToString(CultureInfo.InvariantCulture),TreePalette.ToString(CultureInfo.InvariantCulture),LastTreeMonitor}));
                if (File.Exists(path)) File.Replace(temp,path,null); else File.Move(temp,path);
            } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    internal sealed partial class FrostApp : Application
    {
        private const string InstanceName=@"Local\JakeFrost.Desktop.v3", WakeName=@"Local\JakeFrost.Open.v3";
        private const string GiftWakeName=@"Local\JakeFrost.OpenGift.v3";
        [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hwnd,int id,uint modifiers,uint key);
        [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hwnd,int id);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr handle,IntPtr after,int x,int y,int width,int height,uint flags);
        private const int ExitBuildKey=0x4650;
        private readonly Preferences prefs=new Preferences();
        private readonly List<Overlay> overlays=new List<Overlay>();
        private readonly Stopwatch watch=new Stopwatch();
        private readonly DispatcherTimer animation=new DispatcherTimer(DispatcherPriority.Render);
        private readonly DispatcherTimer poll=new DispatcherTimer(DispatcherPriority.Background);
        private readonly DispatcherTimer save=new DispatcherTimer();
        private Window panel;
        private PlayPalette panelTools;
        private bool leftWasDown;
        private Forms.NotifyIcon tray;
        private Forms.ContextMenuStrip menu;
        private System.Drawing.Icon appIcon;
        private Forms.ToolStripMenuItem trayPause, trayBuild;
        private RegisteredWaitHandle wakeHandler,giftWakeHandler;
        private bool building, paused, quitting, loading=true, escapeRegistered, measurePending;
        private IntPtr panelHandle;
        private double lastFrame;
        private int scans;

        [STAThread]
        internal static int Main(string[] args)
        {
            bool openedGift=args.Length>0;
            if(openedGift) {
                try {
                    var inbox=new GiftPost(Preferences.DirectoryName);
                    foreach(string path in args) {
                        if(!String.Equals(Path.GetExtension(path),".fpgift",StringComparison.OrdinalIgnoreCase))
                            throw new InvalidDataException("Choose a Jake Frost gift file (.fpgift).");
                        inbox.Import(Path.GetFullPath(path));
                    }
                } catch(Exception ex) {
                    MessageBox.Show(ex.Message,"Open Jake Frost gift",MessageBoxButton.OK,MessageBoxImage.Information);
                    return 1;
                }
            }
            bool first;
            using (var mutex=new Mutex(true,InstanceName,out first))
            using (var wake=new EventWaitHandle(false,EventResetMode.AutoReset,WakeName))
            using (var giftWake=new EventWaitHandle(false,EventResetMode.AutoReset,GiftWakeName)) {
                if (!first) { if(openedGift) giftWake.Set(); else wake.Set(); return 0; }
                try {
                    var app=new FrostApp();
                    app.ShutdownMode=ShutdownMode.OnExplicitShutdown;
                    app.Startup += delegate { app.Start(wake,giftWake,openedGift); };
                    return app.Run();
                } finally { mutex.ReleaseMutex(); }
            }
        }
        private T Control<T>(string name) where T : FrameworkElement { return (T)panel.FindName(name); }

        private void Start(EventWaitHandle wake,EventWaitHandle giftWake,bool openedGift)
        {
            prefs.Load();
            panel=(Window)LoadComponent(new Uri("/JakeFrost;component/Panel.xaml",UriKind.Relative));
            using (var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("JakeFrost.Icon"))
            using (var icon=new System.Drawing.Icon(stream)) appIcon=(System.Drawing.Icon)icon.Clone();
            panel.Icon=Imaging.CreateBitmapSourceFromHIcon(appIcon.Handle,Int32Rect.Empty,BitmapSizeOptions.FromEmptyOptions());
            MainWindow=panel;
            panel.MaxHeight=Math.Max(200,SystemParameters.WorkArea.Height-12);
            panel.MaxWidth=Math.Max(240,SystemParameters.WorkArea.Width-12);
            panel.SourceInitialized += delegate {
                panelHandle=new WindowInteropHelper(panel).Handle;
                HwndSource.FromHwnd(panelHandle).AddHook(PanelMessage);
                powerNotice=RegisterPowerSettingNotification(panelHandle,ref DisplayState,0);
                QueuePanelMeasure();
            };
            panel.LocationChanged += delegate { QueuePanelMeasure(); };
            panel.StateChanged += delegate { ScheduleFrames(); };
            SetupStudio();
            ConnectControls();
            ConnectScenes();
            ApplyPreferences();
            // Give the settings window its first layout before creating the full-screen windows.
            if (!openedGift) OpenPanel();
            MakeTray();
            SyncMonitors();
            wakeHandler=ThreadPool.RegisterWaitForSingleObject(wake,delegate { Dispatcher.BeginInvoke(new Action(OpenPanel)); },null,-1,false);
            giftWakeHandler=ThreadPool.RegisterWaitForSingleObject(giftWake,delegate {
                Dispatcher.BeginInvoke(new Action(delegate {if(!quitting){OpenPage("Friends");friends.Poll();}}));
            },null,-1,false);
            save.Interval=TimeSpan.FromMilliseconds(300);
            save.Tick += delegate { save.Stop(); prefs.Save(); };
            poll.Interval=TimeSpan.FromMilliseconds(250);
            poll.Tick += delegate {
                if (++scans%8==0) { SyncMonitors(); weather.Tick(); friends.Poll(); CheckPower(); UpdateWallpaper(); }
                foreach (Overlay overlay in overlays) {
                    PollOverlay(overlay);
                    if (scans%40==0) SaveDecorations(overlay);
                }
                ScheduleFrames();
            };
            animation.Interval=TimeSpan.FromMilliseconds(33);
            animation.Tick += delegate { Frame(); };
            watch.Start(); poll.Start(); loading=false;
            weather.Configure(prefs.Schedule,prefs.City);
            if(openedGift) OpenPage("Friends");
            foreach (Overlay overlay in overlays) PollOverlay(overlay);
            // Showing transparent topmost windows can put them above an already active panel.
            SetWindowPos(panelHandle,new IntPtr(-1),0,0,0,0,0x0013); // TOPMOST, no move, size or activation
            SessionEnding+=delegate {
                foreach (Overlay overlay in overlays) SaveDecorations(overlay);
                if (save.IsEnabled) prefs.Save();
            };
            ScheduleFrames();
        }
        private void ConnectControls()
        {
            Control<Grid>("TitleBar").MouseLeftButtonDown += delegate(object o,MouseButtonEventArgs e) {
                if (!e.Handled && e.LeftButton==MouseButtonState.Pressed) panel.DragMove();
            };
            ConnectCompactPanel();
            Control<Button>("HideButton").Click += delegate { panel.Hide(); };
            Control<Button>("PauseButton").Click += delegate { TogglePause(); };
            Control<Button>("ClearButton").Click += delegate { ClearSnow(); };
            Control<Button>("QuitButton").Click += delegate { Quit(); };
            string[] tabNames={"Workshop","Weather","Decor","Friends"};
            foreach(string name in tabNames) {
                string selected=name; Control<RadioButton>(name+"Tab").Checked+=delegate { ShowPage(selected); };
            }
            panelTools=new PlayPalette(3,ActivateTool);
            Control<Border>("ToolsHost").Child=panelTools;
            panel.Closing += delegate(object o,System.ComponentModel.CancelEventArgs e) {
                if (!quitting) { e.Cancel=true; if(building) SetBuild(false); panel.Hide(); }
            };
            panel.PreviewKeyDown += delegate(object o,KeyEventArgs e) {
                if (e.Key==Key.Escape) { if(building) SetBuild(false); else panel.Hide(); e.Handled=true; }
            };
            SetUpChoices(new[]{"Light","Steady","Flurry"},prefs.Intensity-1,delegate(int n){ prefs.Intensity=n+1; });
            SetUpChoices(new[]{"IceOff","IceFrost","IceIcicles","IceDeep"},prefs.Ice,delegate(int n){ prefs.Ice=n; });
            SetUpChoices(new[]{"Warm","Festive","Aurora"},prefs.Palette,delegate(int n){ prefs.Palette=n; });
            SetUpSlider("BulbSize",prefs.BulbSize,delegate(int n){prefs.BulbSize=n;},"%");
            SetupOption("TwinkleLightsOption",prefs.TwinkleLights,delegate(bool v){prefs.TwinkleLights=v;ApplyPreferences();UpdateTreePreview();});
            ConnectTreeDesigner();
            SetUpChoices(new[]{"VisitorSpeed0","VisitorSpeed1","VisitorSpeed2"},prefs.VisitorSpeed,delegate(int n){ prefs.VisitorSpeed=n; });
            foreach (VisitorSizeTarget target in Enum.GetValues(typeof(VisitorSizeTarget))) {
                int index=(int)target;
                SetUpSlider("Size"+target,prefs.VisitorSizes[index],delegate(int n){prefs.VisitorSizes[index]=n;},"%");
            }
            SetUpSlider("Volume",prefs.Volume,delegate(int n) { prefs.Volume=n; },"%");
            SetUpSlider("Depth",prefs.Depth,delegate(int n) { prefs.Depth=n; }," DIP");
            var wind=Control<Slider>("Wind");
            wind.Value=prefs.Wind; ShowWind();
            wind.ValueChanged += delegate { prefs.Wind=(int)wind.Value; ShowWind(); SaveSoon(); };
            var fullscreen=Control<CheckBox>("FullscreenOption");
            fullscreen.IsChecked=prefs.PauseFullscreen;
            BindToggle(fullscreen,delegate(bool enabled) { prefs.PauseFullscreen=enabled; });
            var puff=Control<CheckBox>("PuffOption"); puff.IsChecked=prefs.ClickPuffs;
            BindToggle(puff,delegate(bool enabled) { prefs.ClickPuffs=enabled; leftWasDown=(GetAsyncKeyState(1)&0x8000)!=0; });
            var remember=Control<CheckBox>("RememberOption"); remember.IsChecked=prefs.RememberDecorations;
            BindToggle(remember,delegate(bool enabled) {
                prefs.RememberDecorations=enabled;
                foreach (Overlay overlay in overlays) {
                    if (enabled) SaveDecorations(overlay);
                    else if (DecorationStore.Write(overlay.MonitorInfo.Id,"")) overlay.SavedLayout="";
                }
            });
            var grab=Control<CheckBox>("GrabOption"); grab.IsChecked=prefs.DirectGrab;
            BindToggle(grab,delegate(bool enabled) {prefs.DirectGrab=enabled;foreach(Overlay o in overlays) UpdateGrab(o);});
        }
        private void BindToggle(CheckBox box,Action<bool> set)
        {
            RoutedEventHandler changed=delegate { set(box.IsChecked==true); SaveSoon(); };
            box.Checked+=changed; box.Unchecked+=changed;
        }
        private void ShowPage(string choice)
        {
            if (choice=="Decor") EnsureDecorationGallery();
            string[] names={"WorkshopPane","WeatherPane","DecorPane","FriendsHost"};
            foreach (string name in names) Control<FrameworkElement>(name).Visibility=
                name.StartsWith(choice,StringComparison.Ordinal)?Visibility.Visible:Visibility.Collapsed;
        }
        private void SetUpChoices(string[] names,int selected,Action<int> set)
        {
            for (int i=0;i<names.Length;i++) {
                int index=i; var radio=Control<RadioButton>(names[i]);
                radio.IsChecked=index==selected;
                radio.Checked+=delegate { set(index); ApplyPreferences(); SaveSoon(); };
            }
        }
        private void SetUpSlider(string name,int initial,Action<int> set,string unit)
        {
            var slider=Control<Slider>(name); var label=Control<TextBlock>(name+"Label");
            slider.Value=initial; label.Text=initial.ToString()+unit;
            slider.ValueChanged+=delegate {
                int value=(int)Math.Round(slider.Value); set(value);
                label.Text=value.ToString()+unit; ApplyPreferences(); SaveSoon();
            };
        }
        private void ActivateTool(PlayTool value)
        {
            EnsureSnow();
            prefs.Tool=value;
            ApplyPreferences(); SaveSoon();
            SetBuild(true);
        }
        private void Configure(SnowScene scene)
        {
            scene.Tool=prefs.Tool; scene.SnowVolume=prefs.Volume; scene.DriftDepth=prefs.Depth;
            scene.IceLevel=prefs.Ice; scene.LightPalette=prefs.Palette; scene.Weather=prefs.Weather;
            scene.NewBulbScale=prefs.BulbSize/100.0; scene.TwinkleLights=prefs.TwinkleLights;
            scene.NewTreeTrim=prefs.TreeTrimOptions;scene.NewTreePalette=prefs.TreePalette;
            scene.LightningEnabled=prefs.Lightning; scene.SelectedDecoration=prefs.Decoration;
            scene.WindowSnowEnabled=prefs.WindowBanks;
            scene.VisitorSpeed=prefs.VisitorSpeed;
            for(int i=0;i<prefs.VisitorSizes.Length;i++) scene.SetVisitorSize((VisitorSizeTarget)i,prefs.VisitorSizes[i]);
        }
        private void ApplyPreferences()
        {
            panelTools.SelectTool(prefs.Tool);
            foreach (Overlay o in overlays) {
                Configure(o.Surface.Scene); o.Surface.InvalidateVisual();
                UpdateGrab(o);
            }
        }
        private void SaveSoon() { if (!loading) { save.Stop(); save.Start(); } }
        private IntPtr PanelMessage(IntPtr hwnd,int msg,IntPtr wParam,IntPtr lParam,ref bool handled)
        {
            if (msg==0x112 && (wParam.ToInt64() & 0xFFF0)==0xF020) {
                SetCompact(true); handled=true; return IntPtr.Zero;
            }
            if (msg==0x312 && wParam.ToInt32()==ExitBuildKey && building) {
                SetBuild(false); handled=true;
            }
            if (msg==0x2E0 || msg==0x1A) QueuePanelMeasure();
            PowerMessage(msg,wParam,lParam);
            return IntPtr.Zero;
        }
        private void QueuePanelMeasure()
        {
            if (panelHandle==IntPtr.Zero || measurePending || quitting) return;
            measurePending=true;
            Dispatcher.BeginInvoke(DispatcherPriority.Background,new Action(delegate {
                measurePending=false;
                var screen=Forms.Screen.FromHandle(panelHandle);
                var source=HwndSource.FromHwnd(panelHandle);
                if (source==null || source.CompositionTarget==null) return;
                var pixels=source.CompositionTarget.TransformToDevice;
                panel.MaxHeight=Math.Max(100,screen.WorkingArea.Height/pixels.M22-12);
                panel.MaxWidth=Math.Max(180,screen.WorkingArea.Width/pixels.M11-12);
            }));
        }
        private void ShowWind() {
            Control<TextBlock>("WindLabel").Text=prefs.Wind==0?"Calm":
                (prefs.Wind<0?"←  ":"")+Math.Abs(prefs.Wind).ToString(CultureInfo.InvariantCulture)+(prefs.Wind>0?"  →":"");
        }
        private void MakeTray()
        {
            menu=new Forms.ContextMenuStrip();
            menu.Items.Add("Open Jake Frost",null,delegate { OpenPanel(); });
            AddStudioMenu(menu);
            trayBuild=(Forms.ToolStripMenuItem)menu.Items.Add("Play on desktop",null,delegate { SetBuild(!building); });
            trayPause=(Forms.ToolStripMenuItem)menu.Items.Add("Pause effects",null,delegate { TogglePause(); });
            menu.Items.Add("Clear scene",null,delegate { ClearSnow(); });
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("Quit Jake Frost",null,delegate { Quit(); });
            tray=new Forms.NotifyIcon { Icon=appIcon, Text="Jake Frost", ContextMenuStrip=menu,Visible=true };
            tray.MouseClick += delegate(object o,Forms.MouseEventArgs e) { if (e.Button==Forms.MouseButtons.Left) OpenPanel(); };
        }
        private void OpenPanel()
        {
            if (quitting) return;
            if (building) SetBuild(false);
            ShowPanel(false); panel.Focus();
        }
        private void ShowPanel(bool folded)
        {
            SetCompact(folded); panel.Show(); panel.WindowState=WindowState.Normal;
            panel.Topmost=true; panel.Activate();
            ScheduleFrames();
        }
        private void ClearSnow() {
            foreach (Overlay o in overlays) {
                o.Surface.Scene.Clear(); o.Surface.InvalidateVisual();
                if (prefs.RememberDecorations && DecorationStore.Write(o.MonitorInfo.Id,"")) o.SavedLayout="";
            }
        }
        private void PollOverlay(Overlay overlay)
        {
            overlay.Poll(prefs.PauseFullscreen,building,(prefs.Weather==WeatherMode.Off && !overlay.Surface.Scene.BlizzardActive) || displayAsleep || prefs.HiddenScreens.Contains(overlay.MonitorInfo.Id),
                prefs.BehindWindows,prefs.WindowBanks);
            UpdateGrab(overlay);
            if (overlay.LayoutInitialized || overlay.Suspended || overlay.Surface.ActualWidth<2 || overlay.Surface.Scene.Banks.Count==0) return;
            overlay.LayoutInitialized=true;
            if (prefs.RememberDecorations) {
                overlay.SavedLayout=DecorationStore.Read(overlay.MonitorInfo.Id);
                if (overlay.SavedLayout.Length>0) overlay.Surface.Scene.ImportDecorations(overlay.SavedLayout);
            }
        }
        private void SaveDecorations(Overlay overlay)
        {
            if (!prefs.RememberDecorations || !overlay.LayoutInitialized) return;
            string layout=overlay.Surface.Scene.ExportDecorations();
            if (layout!=overlay.SavedLayout && DecorationStore.Write(overlay.MonitorInfo.Id,layout)) overlay.SavedLayout=layout;
        }
        private void TogglePause()
        {
            paused=!paused;
            if (paused && building) SetBuild(false);
            string text=paused?"Resume":"Pause";
            Control<Button>("PauseButton").Content=text; trayPause.Text=text+" effects";
            foreach(Overlay o in overlays) UpdateGrab(o);
            ScheduleFrames();
        }
        private void SetBuild(bool value)
        {
            if (building==value) { if(value) SetCompact(true); return; }
            if (value && overlays.All(o=>prefs.HiddenScreens.Contains(o.MonitorInfo.Id))) {
                OpenPage("Weather");
                Control<TextBlock>("ScheduleStatus").Text="Enable a display below to play on your desktop.";
                Control<Expander>("DisplayOptions").IsExpanded=true;
                return;
            }
            if (value) EnsureSnow();
            if (value && paused) TogglePause();
            building=value;
            leftWasDown=(GetAsyncKeyState(1)&0x8000)!=0;
            if (value) {
                escapeRegistered=RegisterHotKey(panelHandle,ExitBuildKey,0x4000,0x1B);
            } else if (escapeRegistered) {
                UnregisterHotKey(panelHandle,ExitBuildKey); escapeRegistered=false;
            }
            foreach (Overlay overlay in overlays) {
                PollOverlay(overlay);
                overlay.SetBuilding(value);
                UpdateGrab(overlay);
                if (!value) SaveDecorations(overlay);
            }
            trayBuild.Text=value?"Finish playing":"Play on desktop";
            ShowPanel(value);
        }
        private void SyncMonitors()
        {
            var monitors=DesktopMap.Monitors();
            foreach (Overlay old in overlays.ToArray()) {
                if (!monitors.Any(m=>m.Id==old.MonitorInfo.Id)) { SaveDecorations(old); old.Close(); overlays.Remove(old); }
            }
            foreach (DesktopMonitor monitor in monitors) {
                Overlay o=overlays.FirstOrDefault(v=>v.MonitorInfo.Id==monitor.Id);
                if (o==null) {
                    o=new Overlay(monitor,unchecked(Environment.TickCount+monitor.Id.GetHashCode()));
                    o.GiftSelected=OpenGift;
                    var treeDisplay=o;
                    o.Surface.Scene.TreePicked=tree=>Dispatcher.BeginInvoke(new Action(delegate {OpenTreeStudio(treeDisplay,tree);}));
                    o.Surface.Scene.RedeemDailyGift=RedeemPresent;
                    o.Surface.Scene.GiftArrived=friends.GiftArrived;
                    o.Surface.Scene.IsMountWindowAlive=DesktopMap.WindowAlive;
                    Configure(o.Surface.Scene);
                    overlays.Add(o); o.Show(); o.SetBuilding(building);
                    if (building && panel.IsVisible) panel.Activate();
                } else if(monitor.Work!=o.MonitorInfo.Work || monitor.Bounds!=o.MonitorInfo.Bounds || monitor.Scale!=o.MonitorInfo.Scale) {
                    o.MonitorInfo=monitor; o.Place();
                }
            }
            RefreshScreenList(monitors);
            if (building && !overlays.Any(o=>!prefs.HiddenScreens.Contains(o.MonitorInfo.Id))) {
                SetBuild(false); OpenPage("Weather");
            }
        }
        private void ScheduleFrames()
        {
            bool needed=!paused && !displayAsleep && overlays.Any(o=>!o.Suspended && (prefs.Weather!=WeatherMode.Off || o.Surface.Scene.BlizzardActive));
            if (needed && !animation.IsEnabled) { lastFrame=watch.Elapsed.TotalSeconds; animation.Start(); }
            if (!needed && animation.IsEnabled) animation.Stop();
        }
        private void Frame()
        {
            double now=watch.Elapsed.TotalSeconds, dt=Math.Min(0.08,Math.Max(0,now-lastFrame)); lastFrame=now;
            if (!building && prefs.ClickPuffs && Snowing && overlays.Any(o=>!o.Suspended)) {
                bool down=(GetAsyncKeyState(1)&0x8000)!=0;
                if (down && !leftWasDown && !(panel.IsVisible && panel.IsMouseOver)) {
                    var pointer=Forms.Cursor.Position;
                    foreach (Overlay o in overlays) {
                        if (o.Suspended || !o.MonitorInfo.Work.Contains(pointer)) continue;
                        Point local=o.Surface.PointFromScreen(new Point(pointer.X,pointer.Y));
                        if (o.Grab==null || !o.Grab.Held && !(prefs.DirectGrab && o.Surface.Scene.DirectHit(local.X,local.Y)))
                            o.Surface.Scene.PuffAtSnow(local.X,local.Y);
                        break;
                    }
                }
                leftWasDown=down;
            }
            if (!Snowing) UpdateWeatherPointer();
            foreach(Overlay o in overlays) o.Advance(dt,prefs.Intensity,prefs.Wind);
        }
        private void Quit()
        {
            if (quitting) return;
            quitting=true; poll.Stop(); animation.Stop();
            if (wallpaper!=null) wallpaper.Dispose();
            CloseStudio();
            foreach (Overlay overlay in overlays) SaveDecorations(overlay);
            if (escapeRegistered) UnregisterHotKey(panelHandle,ExitBuildKey);
            if (save.IsEnabled) { save.Stop(); prefs.Save(); }
            if (wakeHandler!=null) wakeHandler.Unregister(null);
            if (giftWakeHandler!=null) giftWakeHandler.Unregister(null);
            if (tray!=null) { tray.Visible=false; tray.Dispose(); }
            if (menu!=null) menu.Dispose();
            if (appIcon!=null) appIcon.Dispose();
            Shutdown();
        }
    }
}
