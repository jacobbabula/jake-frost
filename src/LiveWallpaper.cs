using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Frostpane
{
    internal enum WallpaperScene { Off, Switchback, Lantern }
    internal enum WallpaperTime { Clock, Dawn, Morning, Midday, GoldenHour, Dusk, Night }

    // Each surface is a child of Explorer's wallpaper layer. Destroying it reveals
    // the user's original wallpaper, including slideshows, on the very same frame.
    internal sealed class LiveWallpaper : IDisposable
    {
        private sealed class ScreenLayer { internal HwndSource Window; internal WallpaperArt Art; internal System.Drawing.Rectangle Bounds; }
        private readonly Dictionary<string,ScreenLayer> layers=new Dictionary<string,ScreenLayer>();
        private readonly DispatcherTimer timer=new DispatcherTimer(DispatcherPriority.Background);
        private readonly System.Diagnostics.Stopwatch elapsed=System.Diagnostics.Stopwatch.StartNew();
        private WallpaperScene scene;
        private BitmapSource bitmap,night;
        private int renderedMinute=-1;
        private IntPtr preparedShell;
        private double lastShellRequest=-10;
        internal bool Available { get { return layers.Count>0; } }
        private delegate bool EnumWindow(IntPtr hwnd,IntPtr state);
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern IntPtr FindWindow(string cls,string title);
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern IntPtr FindWindowEx(IntPtr parent,IntPtr after,string cls,string title);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindow callback,IntPtr state);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr handle);
        [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr handle);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr handle,uint command);
        [DllImport("user32.dll",EntryPoint="GetWindowLongW")] private static extern int GetWindowLong(IntPtr handle,int index);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr handle,out uint processId);
        [DllImport("user32.dll")] private static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint message,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr response);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
        [DllImport("user32.dll")] private static extern bool ScreenToClient(IntPtr hwnd,ref System.Drawing.Point point);
        private const int ExStyle=-20, Layered=0x00080000, NoRedirectionBitmap=0x00200000;
        private const uint NextSibling=2;
        private struct DesktopHost
        {
            internal IntPtr Parent,Icons,Wallpaper;
            internal bool Raised { get { return Icons!=IntPtr.Zero; } }
            internal bool IsBelowIcons(IntPtr handle)
            {
                if(!Raised) return true;
                // Multiple monitors can have siblings between the icons and Explorer's wallpaper.
                for(IntPtr next=GetWindow(Icons,NextSibling);next!=IntPtr.Zero && next!=Wallpaper;next=GetWindow(next,NextSibling))
                    if(next==handle) return true;
                return false;
            }
        }
        private static DesktopHost InspectShell(IntPtr prog)
        {
            IntPtr icons=FindWindowEx(prog,IntPtr.Zero,"SHELLDLL_DefView",null);
            IntPtr paper=icons==IntPtr.Zero ? IntPtr.Zero : FindWindowEx(prog,icons,"WorkerW",null);
            if(paper!=IntPtr.Zero) return new DesktopHost { Parent=prog,Icons=icons,Wallpaper=paper };
            if((GetWindowLong(prog,ExStyle)&NoRedirectionBitmap)!=0) return new DesktopHost();
            uint shellPid;GetWindowThreadProcessId(prog,out shellPid);
            IntPtr background=IntPtr.Zero;
            EnumWindows(delegate(IntPtr top,IntPtr unused) {
                uint owner;GetWindowThreadProcessId(top,out owner);
                if(owner!=shellPid) return true;
                if(FindWindowEx(top,IntPtr.Zero,"SHELLDLL_DefView",null)==IntPtr.Zero) return true;
                for(IntPtr next=FindWindowEx(IntPtr.Zero,top,"WorkerW",null);next!=IntPtr.Zero;next=FindWindowEx(IntPtr.Zero,next,"WorkerW",null)) {
                    GetWindowThreadProcessId(next,out owner);
                    if(owner==shellPid) {background=next;return false;}
                }
                return true;
            },IntPtr.Zero);
            return new DesktopHost { Parent=background };
        }
        private DesktopHost FindHost()
        {
            IntPtr prog=FindWindow("Progman",null);
            if(prog==IntPtr.Zero) return new DesktopHost();
            var host=InspectShell(prog);
            if(prog!=preparedShell || (host.Parent==IntPtr.Zero && elapsed.Elapsed.TotalSeconds-lastShellRequest>=2)) {
                preparedShell=prog;lastShellRequest=elapsed.Elapsed.TotalSeconds;
                IntPtr result;
                SendMessageTimeout(prog,0x052C,new IntPtr(0xD),new IntPtr(1),2,200,out result);
                host=InspectShell(prog);
            }
            return host;
        }
        private static bool MatchesHost(HwndSource window,DesktopHost host)
        {
            if(window.IsDisposed || !IsWindow(window.Handle) || GetParent(window.Handle)!=host.Parent) return false;
            return ((GetWindowLong(window.Handle,ExStyle)&Layered)!=0)==host.Raised;
        }
        private static ScreenLayer CreateLayer(DesktopHost host,System.Drawing.Rectangle bounds)
        {
            var point=bounds.Location;
            if(!ScreenToClient(host.Parent,ref point)) return null;
            var spec=new HwndSourceParameters("Jake Frost landscape") {
                WindowStyle=0x40000000,ExtendedWindowStyle=0x08000020,
                ParentWindow=host.Parent,PositionX=point.X,PositionY=point.Y, Width=bounds.Width,Height=bounds.Height,
                // WPF clears WS_EX_LAYERED on an opaque HwndSource. Let WPF present the
                // raised desktop's layered child itself, using its own per-pixel surface.
                UsesPerPixelTransparency=host.Raised
            };
            HwndSource window=new HwndSource(spec);
            try {
                var layer=new ScreenLayer { Window=window,Art=new WallpaperArt(),Bounds=bounds };
                window.RootVisual=layer.Art;
                if(MatchesHost(window,host) && SetWindowPos(window.Handle,host.Icons,point.X,point.Y,bounds.Width,bounds.Height,0x0050) &&
                   host.IsBelowIcons(window.Handle)) return layer;
            } catch {window.Dispose();throw;}
            window.Dispose();return null;
        }
        internal LiveWallpaper() {timer.Tick+=delegate { Paint(); };}
        private double seconds;
        private double lastTick;
        private void Paint()
        {
            double now=elapsed.Elapsed.TotalSeconds;
            seconds+=Math.Min(.25,Math.Max(0,now-lastTick)); lastTick=now;
            foreach(ScreenLayer layer in layers.Values) {
                if(!layer.Art.Animate || layer.Window.IsDisposed) continue;
                layer.Art.Seconds=seconds;
                layer.Art.InvalidateVisual();
            }
        }
        internal void Update(WallpaperScene selected,WallpaperTime time,bool motion,bool idle,bool battery,
                             List<DesktopMonitor> screens,HashSet<string> hidden,bool pauseFullscreen)
        {
            if(selected==WallpaperScene.Off) { CloseLayers(); scene=selected; bitmap=null; night=null; return; }
            bool changed=scene!=selected;
            if(changed || bitmap==null) {
                bitmap=WallpaperArt.Load(selected);
                night=WallpaperArt.Load(selected,true);
                scene=selected;
            }
            bool animate=motion && !idle && SystemParameters.ClientAreaAnimation;
            bool anyMotion=false;
            var retained=new HashSet<string>();
            int minute=(int)DateTime.Now.TimeOfDay.TotalMinutes;
            var host=FindHost();
            foreach(DesktopMonitor monitor in screens) {
                if(hidden.Contains(monitor.Id) || host.Parent==IntPtr.Zero) continue;
                ScreenLayer layer;
                bool fresh=false;
                if(!layers.TryGetValue(monitor.Id,out layer) || layer.Bounds!=monitor.Bounds || !MatchesHost(layer.Window,host)) {
                    if(layer!=null) { layer.Window.Dispose(); layers.Remove(monitor.Id); }
                    layer=CreateLayer(host,monitor.Bounds);
                    if(layer==null) continue;
                    layers.Add(monitor.Id,layer);fresh=true;
                } else if(!host.IsBelowIcons(layer.Window.Handle)) {
                    if(!SetWindowPos(layer.Window.Handle,host.Icons,0,0,0,0,0x0013) || !host.IsBelowIcons(layer.Window.Handle)) continue;
                }
                retained.Add(monitor.Id);
                bool moving=animate && !(pauseFullscreen && DesktopMap.Fullscreen(monitor));
                anyMotion|=moving;
                if(fresh || changed || renderedMinute!=minute || layer.Art.TimeMode!=time || layer.Art.Animate!=moving) {
                    layer.Art.Configure(bitmap,night,selected,time,moving); layer.Art.Seconds=seconds;
                    layer.Art.InvalidateVisual();
                }
            }
            foreach(string key in new List<string>(layers.Keys)) if(!retained.Contains(key)) {layers[key].Window.Dispose(); layers.Remove(key);}
            renderedMinute=minute;
            var interval=TimeSpan.FromMilliseconds(battery?160:83);
            if(timer.Interval!=interval) timer.Interval=interval;
            if(anyMotion && !timer.IsEnabled) {lastTick=elapsed.Elapsed.TotalSeconds;timer.Start();}
            if(!anyMotion) timer.Stop();
        }
        private void CloseLayers() {timer.Stop();foreach(var layer in layers.Values) layer.Window.Dispose();layers.Clear();}
        public void Dispose() {CloseLayers();bitmap=null;}
    }
}
