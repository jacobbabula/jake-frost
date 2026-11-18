using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
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
        internal bool Available { get { return layers.Count>0; } }
        private delegate bool EnumWindow(IntPtr hwnd,IntPtr state);
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern IntPtr FindWindow(string cls,string title);
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern IntPtr FindWindowEx(IntPtr parent,IntPtr after,string cls,string title);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindow callback,IntPtr state);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr handle);
        [DllImport("user32.dll")] private static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint message,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr response);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
        [DllImport("user32.dll")] private static extern bool ScreenToClient(IntPtr hwnd,ref System.Drawing.Point point);
        [DllImport("user32.dll")] private static extern bool SetLayeredWindowAttributes(IntPtr hwnd,uint key,byte alpha,uint flags);
        private static IntPtr FindHost(out IntPtr belowIcons)
        {
            IntPtr prog=FindWindow("Progman",null);
            belowIcons=IntPtr.Zero;
            if(prog==IntPtr.Zero) return IntPtr.Zero;
            IntPtr result;
            SendMessageTimeout(prog,0x052C,new IntPtr(0xD),new IntPtr(1),2,200,out result);
            IntPtr icons=FindWindowEx(prog,IntPtr.Zero,"SHELLDLL_DefView",null);
            if(icons!=IntPtr.Zero && FindWindowEx(prog,IntPtr.Zero,"WorkerW",null)!=IntPtr.Zero) {
                belowIcons=icons; return prog;
            }
            IntPtr background=IntPtr.Zero;
            EnumWindows(delegate(IntPtr top,IntPtr unused) {
                if(FindWindowEx(top,IntPtr.Zero,"SHELLDLL_DefView",null)==IntPtr.Zero) return true;
                background=FindWindowEx(IntPtr.Zero,top,"WorkerW",null);
                return background==IntPtr.Zero;
            },IntPtr.Zero);
            return background;
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
            IntPtr parent=IntPtr.Zero,after=IntPtr.Zero;
            bool searched=false;
            foreach(DesktopMonitor monitor in screens) {
                if(hidden.Contains(monitor.Id)) continue;
                ScreenLayer layer;
                bool fresh=false;
                if(!layers.TryGetValue(monitor.Id,out layer) || layer.Window.IsDisposed || !IsWindow(layer.Window.Handle) || layer.Bounds!=monitor.Bounds) {
                    if(layer!=null) { layer.Window.Dispose(); layers.Remove(monitor.Id); }
                    if(!searched) {parent=FindHost(out after); searched=true;}
                    if(parent==IntPtr.Zero) continue;
                    var point=monitor.Bounds.Location; ScreenToClient(parent,ref point);
                    var spec=new HwndSourceParameters("Jake Frost landscape") {
                        WindowStyle=0x40000000, ExtendedWindowStyle=0x08000020 | (after==IntPtr.Zero ? 0 : 0x80000),
                        ParentWindow=parent, PositionX=point.X,PositionY=point.Y, Width=monitor.Bounds.Width,Height=monitor.Bounds.Height
                    };
                    HwndSource window=new HwndSource(spec);
                    if(after!=IntPtr.Zero) SetLayeredWindowAttributes(window.Handle,0,255,2);
                    layer=new ScreenLayer { Window=window,Art=new WallpaperArt(),Bounds=monitor.Bounds };
                    window.RootVisual=layer.Art;
                    if(!SetWindowPos(window.Handle,after,point.X,point.Y,monitor.Bounds.Width,monitor.Bounds.Height,0x0050)) {window.Dispose();continue;}
                    layers.Add(monitor.Id,layer);fresh=true;
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
