using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace Frostpane
{
    internal sealed class SnowSurface : FrameworkElement
    {
        internal readonly SnowScene Scene;
        internal bool Building;
        private static readonly Brush CatchClicks = new SolidColorBrush(Color.FromArgb(1,0,0,0));

        internal SnowSurface(int seed)
        {
            Scene = new SnowScene(seed);
            ClipToBounds = true;
            SizeChanged += delegate {
                if (ActualWidth > 1 && ActualHeight > 1) Scene.Resize(ActualWidth, ActualHeight);
            };
        }
        protected override void OnRender(DrawingContext dc)
        {
            if (Building) dc.DrawRectangle(CatchClicks, null, new Rect(RenderSize));
            SnowArtwork.Draw(dc, Scene);
        }
        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            if (!Building) return;
            Point p = e.GetPosition(this); string fortune;
            if(!Scene.OpenDailyPresent(p.X,p.Y,out fortune)) {Scene.PlayDown(p.X,p.Y); CaptureMouse();}
            InvalidateVisual(); e.Handled = true;
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            if (!Building || !IsMouseCaptured) return;
            Point p=e.GetPosition(this); Scene.PlayMove(p.X,p.Y); InvalidateVisual();
        }
        protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
        {
            if (!IsMouseCaptured) return;
            Point p=e.GetPosition(this); Scene.PlayUp(p.X,p.Y); ReleaseMouseCapture(); InvalidateVisual(); e.Handled = true;
        }
        protected override void OnMouseWheel(MouseWheelEventArgs e)
        {
            if (!Building || e.Delta==0) return;
            Point p=e.GetPosition(this);
            if((Keyboard.Modifiers & ModifierKeys.Shift)!=0) Scene.AdjustPropAngleAt(p.X,p.Y,Math.Sign(e.Delta));
            else Scene.AdjustPropSizeAt(p.X,p.Y,Math.Sign(e.Delta));
            InvalidateVisual(); e.Handled=true;
        }
        protected override void OnLostMouseCapture(MouseEventArgs e)
        {
            base.OnLostMouseCapture(e);
            Scene.CancelPlay();
        }
    }

    internal sealed class Overlay : Window
    {
        [DllImport("user32.dll",EntryPoint="GetWindowLongW")] private static extern int GetStyle(IntPtr h,int n);
        [DllImport("user32.dll",EntryPoint="SetWindowLongW")] private static extern int SetStyle(IntPtr h,int n,int v);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
        private const int Extended = -20, ClickThrough=0x20, NoActivate=0x08000000, ToolWindow=0x80;
        private IntPtr hwnd;
        internal DesktopMonitor MonitorInfo;
        internal readonly SnowSurface Surface;
        internal bool Suspended;
        internal bool LayoutInitialized;
        internal string SavedLayout;
        internal DesktopGrab Grab;
        internal Action<Overlay> GiftSelected;
        private DesktopMap.WindowSnapshot appliedWindows;
        private System.Drawing.Rectangle previousWork, previousBounds;
        private Size previousSize;
        private double previousScale;
        private bool behindWindows, previousBehind, closed;
        private readonly Action<DesktopMap.WindowSnapshot> applyWindows;

        internal Overlay(DesktopMonitor monitor,int seed)
        {
            MonitorInfo=monitor;
            applyWindows=ApplyWindows;
            Title="Jake Frost snowfall"; WindowStyle=WindowStyle.None; ResizeMode=ResizeMode.NoResize;
            AllowsTransparency=true; Background=Brushes.Transparent; ShowActivated=false;
            Focusable=false; ShowInTaskbar=false; Topmost=true; WindowStartupLocation=WindowStartupLocation.Manual;
            // Native bounds below are authoritative when monitors have different DPI settings.
            Left=monitor.Work.Left/monitor.Scale; Top=monitor.Work.Top/monitor.Scale;
            Width=Math.Max(1,monitor.Work.Width/monitor.Scale); Height=Math.Max(1,monitor.Work.Height/monitor.Scale);
            Surface = new SnowSurface(seed); Content = Surface;
            SourceInitialized += delegate {
                hwnd=new WindowInteropHelper(this).Handle;
                SetBuilding(false);
                Place();
            };
            Loaded += delegate { Place(); };
            Closed+=delegate { closed=true; if (Grab!=null) Grab.Close(); };
            Surface.MouseRightButtonUp+=delegate(object obj,MouseButtonEventArgs e) {
                var p=e.GetPosition(Surface); if (Surface.Scene.SelectGiftAt(p.X,p.Y) && GiftSelected!=null) { GiftSelected(this); e.Handled=true; }
            };
        }
        internal void SetGrab(bool enabled)
        {
            if (Grab==null) {
                if (!enabled) return;
                Grab=new DesktopGrab(this);
                Grab.GiftSelected=delegate { if (GiftSelected!=null) GiftSelected(this); };
            }
            Grab.Enable(enabled && !Suspended && !Surface.Building);
        }
        internal void Place()
        {
            if (hwnd==IntPtr.Zero) return;
            var b=MonitorInfo.Work;
            SetWindowPos(hwnd,IntPtr.Zero,b.Left,b.Top,b.Width,b.Height,0x14);
            if (Grab!=null) Grab.Place();
        }
        internal void SetBuilding(bool on)
        {
            if (!on && Surface.IsMouseCaptured) Surface.ReleaseMouseCapture();
            Surface.Building=on;
            Surface.Scene.ShowDecorationHandles=on;
            if (on && Grab!=null) Grab.Enable(false);
            Cursor=on ? Cursors.Hand : Cursors.Arrow;
            if (hwnd!=IntPtr.Zero) {
                int flags=GetStyle(hwnd,Extended) | NoActivate | ToolWindow | ClickThrough;
                if (on) flags &= ~ClickThrough;
                SetStyle(hwnd,Extended,flags);
                SetWindowPos(hwnd,IntPtr.Zero,0,0,0,0,0x37);
            }
            Surface.InvalidateVisual();
        }
        internal void Poll(bool pauseFullscreen,bool building,bool off=false,bool behind=false,bool windowSnow=true)
        {
            bool hide=off || (pauseFullscreen && !building && DesktopMap.Fullscreen(MonitorInfo));
            if (hide!=Suspended) {
                Suspended=hide; if (hide) Hide(); else Show();
                if (hide && Grab!=null) Grab.Enable(false);
            }
            if (Suspended) return;
            behindWindows=behind;
            Surface.Scene.WindowSnowEnabled=windowSnow;
            DesktopMap.RequestWindows(applyWindows);
            if(Grab!=null && Grab.IsVisible) Grab.ClipSnow(Surface.Clip);
        }
        private void ApplyWindows(DesktopMap.WindowSnapshot windows)
        {
            if (closed || Suspended) return;
            var source=PresentationSource.FromVisual(this);
            double scale=source==null || source.CompositionTarget==null ? MonitorInfo.Scale : source.CompositionTarget.TransformToDevice.M11;
            bool sameGeometry=windows==appliedWindows && scale==previousScale && MonitorInfo.Work==previousWork &&
                MonitorInfo.Bounds==previousBounds && previousSize==Surface.RenderSize;
            if (sameGeometry && behindWindows==previousBehind) return;
            Geometry clip=null;
            if (behindWindows) {
                var bounds=windows.AppBounds(MonitorInfo);
                if(bounds.Count>0) {
                    var cuts=new GeometryGroup{FillRule=FillRule.Nonzero};
                    foreach(var r in bounds) cuts.Children.Add(new RectangleGeometry(new Rect((r.Left-MonitorInfo.Work.Left)/scale,
                        (r.Top-MonitorInfo.Work.Top)/scale,r.Width/scale,r.Height/scale)));
                    clip=new CombinedGeometry(GeometryCombineMode.Exclude,new RectangleGeometry(new Rect(0,0,MonitorInfo.Work.Width/scale,MonitorInfo.Work.Height/scale)),cuts);
                    clip.Freeze();
                }
            }
            Surface.Clip=clip;
            if(Grab!=null && Grab.IsVisible) Grab.ClipSnow(Surface.Clip);
            previousBehind=behindWindows;
            if (sameGeometry) return;
            List<Ledge> edges=windows.Ledges(MonitorInfo,scale);
            double offsetX=(MonitorInfo.Work.Left-MonitorInfo.Bounds.Left)/scale;
            double offsetY=(MonitorInfo.Work.Top-MonitorInfo.Bounds.Top)/scale;
            foreach (Ledge edge in edges) { edge.X-=offsetX; edge.Y-=offsetY; }
            Surface.Scene.SetLedges(edges);
            if (Surface.Scene.Banks.Count>0) {
                appliedWindows=windows; previousScale=scale; previousWork=MonitorInfo.Work;
                previousBounds=MonitorInfo.Bounds; previousSize=Surface.RenderSize;
            }
        }
        internal void Advance(double dt,int intensity,double wind)
        {
            if (Suspended || Surface.ActualWidth<2 || Surface.ActualHeight<2) return;
            Surface.Scene.Step(dt,intensity,wind);
            Surface.InvalidateVisual();
            if (Grab!=null) Grab.RefreshMask();
        }
    }
}
