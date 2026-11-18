using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
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
        private readonly Border buildBar;
        private readonly Button done;
        private readonly TextBlock toolHint;
        private IntPtr hwnd;
        internal DesktopMonitor MonitorInfo;
        internal readonly SnowSurface Surface;
        internal bool Suspended;
        internal bool LayoutInitialized;
        internal string SavedLayout;
        internal DesktopGrab Grab;
        internal Action<Overlay> GiftSelected;
        private List<System.Drawing.Rectangle> clippedRects;
        private double clippedScale;

        internal Overlay(DesktopMonitor monitor,Action finish,Action openTools,int seed)
        {
            MonitorInfo=monitor;
            Title="Jake Frost snowfall"; WindowStyle=WindowStyle.None; ResizeMode=ResizeMode.NoResize;
            AllowsTransparency=true; Background=Brushes.Transparent; ShowActivated=false;
            Focusable=false; ShowInTaskbar=false; Topmost=true; WindowStartupLocation=WindowStartupLocation.Manual;
            // Native bounds below are authoritative when monitors have different DPI settings.
            Left=monitor.Work.Left/monitor.Scale; Top=monitor.Work.Top/monitor.Scale;
            Width=Math.Max(1,monitor.Work.Width/monitor.Scale); Height=Math.Max(1,monitor.Work.Height/monitor.Scale);
            var stack = new Grid();
            Surface = new SnowSurface(seed); stack.Children.Add(Surface);
            var row=new StackPanel {Orientation=Orientation.Horizontal};
            toolHint=new TextBlock {FontFamily=new FontFamily("Segoe UI"),FontWeight=FontWeights.SemiBold,
                FontSize=12,Foreground=Brushes.White,VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(5,0,9,0),
                MaxWidth=Math.Max(25,Math.Min(310,Width-170)),TextTrimming=TextTrimming.CharacterEllipsis};
            row.Children.Add(toolHint);
            var switchTool=new Button {Content="Tools…",Padding=new Thickness(8,4,8,4),Margin=new Thickness(0,0,4,0),
                Style=(Style)Application.Current.MainWindow.FindResource("Button")};
            switchTool.Click+=delegate {openTools();};
            row.Children.Add(switchTool);
            done = new Button { Content="Done",Padding=new Thickness(10,4,10,4),Cursor=Cursors.Hand,
                Style=(Style)Application.Current.MainWindow.FindResource("Button"),
                Background=new SolidColorBrush(Color.FromRgb(183,214,193)),Foreground=new SolidColorBrush(Color.FromRgb(26,48,41)) };
            done.Click += delegate { finish(); };
            AutomationProperties.SetAutomationId(done,"DoneButton");
            row.Children.Add(done);
            buildBar = new Border { Child=row, Background=new SolidColorBrush(Color.FromArgb(241,29,49,52)),
                CornerRadius=new CornerRadius(8), HorizontalAlignment=HorizontalAlignment.Left,VerticalAlignment=VerticalAlignment.Bottom,
                Padding=new Thickness(4),Margin=new Thickness(12,0,0,26),Visibility=Visibility.Collapsed };
            stack.Children.Add(buildBar); Content=stack;
            SourceInitialized += delegate {
                hwnd=new WindowInteropHelper(this).Handle;
                SetBuilding(false);
                Place();
            };
            Loaded += delegate { Place(); };
            Closed+=delegate { if (Grab!=null) Grab.Close(); };
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
        internal void SelectTool(PlayTool tool)
        {
            toolHint.Text=tool==PlayTool.Decorate?DecorationPicker.NameOf(Surface.Scene.SelectedDecoration):
                (tool==PlayTool.Erase?"Remove":tool.ToString());
            if (tool==PlayTool.Lights || tool==PlayTool.Decorate && Surface.Scene.SelectedDecoration==DecorationKind.Lights)
                toolHint.Text+="  ·  Drag ends to tilt, middle to curve";
            else if (tool==PlayTool.Arrange || tool==PlayTool.Decorate || tool==PlayTool.Tree || tool==PlayTool.Sled)
                toolHint.Text+="  ·  Drag the circular arrow to rotate";
            toolHint.ToolTip=PlayPalette.Hint(tool);
        }
        internal void Place()
        {
            if (hwnd==IntPtr.Zero) return;
            var b=MonitorInfo.Work;
            SetWindowPos(hwnd,IntPtr.Zero,b.Left,b.Top,b.Width,b.Height,0x14);
            if (Grab!=null) Grab.Place();
        }
        internal void SetBuilding(bool on,bool escapeRegistered=false)
        {
            if (!on && Surface.IsMouseCaptured) Surface.ReleaseMouseCapture();
            Surface.Building=on;
            Surface.Scene.ShowDecorationHandles=on;
            if (on && Grab!=null) Grab.Enable(false);
            buildBar.Visibility=on ? Visibility.Visible : Visibility.Collapsed;
            done.Content=escapeRegistered ? "Done  ·  Esc" : "Done";
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
            var source=PresentationSource.FromVisual(this);
            double scale=source==null || source.CompositionTarget==null ? MonitorInfo.Scale : source.CompositionTarget.TransformToDevice.M11;
            var bounds=behind?DesktopMap.AppBounds(MonitorInfo):new List<System.Drawing.Rectangle>();
            if(clippedRects==null || scale!=clippedScale || !clippedRects.SequenceEqual(bounds) || (bounds.Count>0 && Surface.Clip==null)) {
                clippedRects=bounds;clippedScale=scale;
                Geometry clip=null;
                if(bounds.Count>0) {
                    var cuts=new GeometryGroup{FillRule=FillRule.Nonzero};
                    foreach(var r in bounds) cuts.Children.Add(new RectangleGeometry(new Rect((r.Left-MonitorInfo.Work.Left)/scale,
                        (r.Top-MonitorInfo.Work.Top)/scale,r.Width/scale,r.Height/scale)));
                    clip=new CombinedGeometry(GeometryCombineMode.Exclude,new RectangleGeometry(new Rect(0,0,MonitorInfo.Work.Width/scale,MonitorInfo.Work.Height/scale)),cuts);
                    clip.Freeze();
                }
                Surface.Clip=clip;
            }
            if(Grab!=null && Grab.IsVisible) Grab.ClipSnow(Surface.Clip);
            Surface.Scene.WindowSnowEnabled=windowSnow;
            List<Ledge> edges=DesktopMap.Ledges(MonitorInfo,scale);
            double offsetX=(MonitorInfo.Work.Left-MonitorInfo.Bounds.Left)/scale;
            double offsetY=(MonitorInfo.Work.Top-MonitorInfo.Bounds.Top)/scale;
            foreach (Ledge edge in edges) { edge.X-=offsetX; edge.Y-=offsetY; }
            Surface.Scene.SetLedges(edges);
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
