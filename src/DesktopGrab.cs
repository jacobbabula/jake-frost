using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace Frostpane
{
    // The visible weather layer stays click-through. Windows routes mouse input to
    // this separate per-pixel layered window only where its alpha mask contains snow.
    internal sealed class DesktopGrab : Window
    {
        [DllImport("user32.dll",EntryPoint="GetWindowLongW")] private static extern int GetStyle(IntPtr h,int i);
        [DllImport("user32.dll",EntryPoint="SetWindowLongW")] private static extern int SetStyle(IntPtr h,int i,int value);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
        [DllImport("user32.dll")] private static extern IntPtr SetCapture(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr GetCapture();
        [DllImport("user32.dll")] private static extern bool ReleaseCapture();
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        private readonly Overlay overlay;
        private readonly SnowScene scene;
        private readonly Mask mask;
        private IntPtr hwnd;
        private bool held;
        private int lastPointerMessage;
        internal Action GiftSelected;
        internal bool Held {get {return held;}}

        internal DesktopGrab(Overlay owner)
        {
            overlay=owner; scene=owner.Surface.Scene;
            WindowStyle=WindowStyle.None; ResizeMode=ResizeMode.NoResize; WindowStartupLocation=WindowStartupLocation.Manual;
            AllowsTransparency=true; Background=Brushes.Transparent; ShowInTaskbar=false; ShowActivated=false;
            Topmost=true; Focusable=false; Title="Jake Frost interactive snow"; Left=owner.Left; Top=owner.Top;
            Width=owner.Width; Height=owner.Height;
            mask=new Mask(scene); Content=mask;
            SourceInitialized+=delegate {
                hwnd=new WindowInteropHelper(this).Handle;
                int style=GetStyle(hwnd,-20);
                SetStyle(hwnd,-20,(style|0x08000080)&~0x20);
                HwndSource.FromHwnd(hwnd).AddHook(Messages); Place();
            };
            Loaded+=delegate { Place(); };
        }
        internal void Place()
        {
            if (hwnd==IntPtr.Zero) return;
            var work=overlay.MonitorInfo.Work;
            SetWindowPos(hwnd,IntPtr.Zero,work.Left,work.Top,work.Width,work.Height,0x14);
        }
        private Point LocalPoint(IntPtr lParam)
        {
            long pos=lParam.ToInt64(); int x=(short)(pos&65535),y=(short)((pos>>16)&65535);
            var source=HwndSource.FromHwnd(hwnd);
            return source.CompositionTarget.TransformFromDevice.Transform(new Point(x,y));
        }
        private IntPtr Messages(IntPtr h,int msg,IntPtr wp,IntPtr lp,ref bool handled)
        {
            if (msg==0x21) { handled=true; return new IntPtr(3); } // MA_NOACTIVATE
            if (msg==0x201) {
                lastPointerMessage=Environment.TickCount;
                Point p=LocalPoint(lp);
                string fortune;
                if (scene.OpenDailyPresent(p.X,p.Y,out fortune)) { handled=true; return IntPtr.Zero; }
                if (scene.DirectDown(p.X,p.Y)) {
                    held=true; mask.Dragging=true; SetCapture(h); mask.InvalidateVisual(); handled=true;
                }
            } else if (msg==0x200 && held) {
                lastPointerMessage=Environment.TickCount;
                Point p=LocalPoint(lp); scene.DirectMove(p.X,p.Y); handled=true;
            } else if (msg==0x202 && held) {
                End(LocalPoint(lp)); handled=true;
            } else if (msg==0x205) {
                Point p=LocalPoint(lp);
                if (scene.SelectGiftAt(p.X,p.Y) && GiftSelected!=null) {GiftSelected();handled=true;}
            } else if ((msg==0x215 || msg==0x1F) && held) {
                Cancel();
            }
            return IntPtr.Zero;
        }
        private void End(Point p)
        {
            held=false; mask.Dragging=false; scene.DirectUp(p.X,p.Y);
            if (GetCapture()==hwnd) ReleaseCapture(); mask.InvalidateVisual();
        }
        private void Cancel()
        {
            held=false; mask.Dragging=false; scene.CancelDirect();
            if (GetCapture()==hwnd) ReleaseCapture(); mask.InvalidateVisual();
        }
        internal void Enable(bool value)
        {
            if (value==IsVisible) return;
            if (value) { Show(); Place(); mask.InvalidateVisual(); }
            else { if (held) Cancel(); Hide(); }
        }
        internal void RefreshMask()
        {
            if (!IsVisible) return;
            // A release on another monitor can arrive after Windows relinquishes capture.
            if (held && unchecked((uint)(Environment.TickCount-lastPointerMessage))>160 && (GetAsyncKeyState(1)&0x8000)==0) {
                var p=System.Windows.Forms.Cursor.Position;
                End(mask.PointFromScreen(new Point(p.X,p.Y)));
            }
            if (!mask.Dragging && mask.HitTargetsChanged()) mask.InvalidateVisual();
        }
        private Geometry lastSnowClip;
        private Rect lastPanel=Rect.Empty;
        internal void ClipSnow(Geometry area)
        {
            Window settings=Application.Current.MainWindow;
            Rect rect=Rect.Empty;
            if(settings!=null && settings.IsVisible && settings.WindowState!=WindowState.Minimized && settings.ActualWidth>0 && IsVisible) {
                Point top=mask.PointFromScreen(settings.PointToScreen(new Point(0,0)));
                Point end=mask.PointFromScreen(settings.PointToScreen(new Point(settings.ActualWidth,settings.ActualHeight)));
                rect=new Rect(top,end);
            }
            if(lastSnowClip==area && lastPanel==rect) return;
            lastSnowClip=area;lastPanel=rect;
            if(rect.IsEmpty) {mask.Clip=area;return;}
            var outside=new CombinedGeometry(GeometryCombineMode.Exclude,area??new RectangleGeometry(new Rect(0,0,Math.Max(1,mask.ActualWidth),Math.Max(1,mask.ActualHeight))),new RectangleGeometry(rect));
            outside.Freeze();mask.Clip=outside;
        }
        private sealed class Mask : FrameworkElement
        {
            internal bool Dragging;
            private readonly SnowScene snow;
            private sealed class BankShape {internal int Revision=-1; internal Geometry Shape;}
            private readonly ConditionalWeakTable<SnowBank,BankShape> shapes=new ConditionalWeakTable<SnowBank,BankShape>();
            private static readonly SolidColorBrush Hit=new SolidColorBrush(Color.FromArgb(1,0,0,0));
            private struct Target {
                internal object Source;
                internal double X,Y,A,B,C;
            }
            private readonly List<Target> previous=new List<Target>();
            private int index;
            private bool changed;
            internal Mask(SnowScene scene) {snow=scene; ClipToBounds=true;}
            // Falling flakes never intercept mouse input. Publishing an identical full-display
            // layered window every animation tick only adds work to WPF and the compositor.
            internal bool HitTargetsChanged()
            {
                index=0; changed=false;
                var present=snow.DailyPresent;
                if (present!=null) Observe(present,present.X,present.Y);
                foreach(var b in snow.Banks)
                    if (b.Heights.Length>=2 && (b.IsFloor || snow.WindowSnowEnabled)) Observe(b,b.Revision,0);
                foreach(var ball in snow.Balls) Observe(ball,ball.X,ball.Y,ball.Radius);
                foreach(var man in snow.Snowmen) Observe(man,man.X,man.Y,man.BaseRadius,man.MidRadius,man.HeadRadius);
                foreach(var sled in snow.Sleds) Observe(sled,sled.X,sled.DisplayY,sled.DisplayAngle);
                foreach(var tree in snow.Trees) if (!tree.Hidden) Observe(tree,tree.X,tree.Y,tree.Size,tree.Angle);
                if (index<previous.Count) {previous.RemoveRange(index,previous.Count-index);changed=true;}
                return changed;
            }
            private void Observe(object source,double x,double y,double a=0,double b=0,double c=0)
            {
                var target=new Target {Source=source,X=x,Y=y,A=a,B=b,C=c};
                if (index==previous.Count) {previous.Add(target);changed=true;}
                else {
                    var old=previous[index];
                    if (old.Source!=source || old.X!=x || old.Y!=y || old.A!=a || old.B!=b || old.C!=c) {
                        previous[index]=target; changed=true;
                    }
                }
                index++;
            }
            protected override void OnRender(DrawingContext dc)
            {
                if (Dragging) {dc.DrawRectangle(Hit,null,new Rect(RenderSize));return;}
                if(snow.DailyPresent!=null) dc.DrawRectangle(Hit,null,new Rect(snow.DailyPresent.X-13,snow.DailyPresent.Y-24,26,24));
                foreach (SnowBank b in snow.Banks) {
                    if (b.Heights.Length<2 || !b.IsFloor && !snow.WindowSnowEnabled) continue;
                    var saved=shapes.GetOrCreateValue(b);
                    if (saved.Shape==null || saved.Revision!=b.Revision) {
                        var geo=new StreamGeometry();
                        using (var c=geo.Open()) {
                            c.BeginFigure(new Point(b.X,b.Y),true,true);
                            double dx=b.Width/(b.Heights.Length-1);
                            for (int j=0;j<b.Heights.Length;j++) c.LineTo(new Point(b.X+j*dx,b.Y-b.Heights[j]),true,false);
                            c.LineTo(new Point(b.X+b.Width,b.Y),true,false);
                        }
                        geo.Freeze();saved.Shape=geo;saved.Revision=b.Revision;
                    }
                    dc.DrawGeometry(Hit,null,saved.Shape);
                }
                foreach(SnowBall b in snow.Balls) dc.DrawEllipse(Hit,null,new Point(b.X,b.Y),b.Radius,b.Radius);
                foreach(Snowman m in snow.Snowmen) {
                    double y=m.Y-m.BaseRadius, mid=y-.78*(m.BaseRadius+m.MidRadius),head=mid-.78*(m.MidRadius+m.HeadRadius);
                    dc.DrawEllipse(Hit,null,new Point(m.X,y),m.BaseRadius,m.BaseRadius);
                    dc.DrawEllipse(Hit,null,new Point(m.X,mid),m.MidRadius,m.MidRadius);
                    dc.DrawEllipse(Hit,null,new Point(m.X,head),m.HeadRadius,m.HeadRadius);
                    dc.DrawRoundedRectangle(Hit,null,new Rect(m.X-1.22*m.HeadRadius,head-2.0*m.HeadRadius,2.44*m.HeadRadius,1.55*m.HeadRadius),3,3);
                }
                foreach(WinterSled sled in snow.Sleds) {
                    double y=sled.DisplayY;
                    dc.PushTransform(new RotateTransform(sled.DisplayAngle,sled.X,y));
                    dc.DrawRoundedRectangle(Hit,null,new Rect(sled.X-26,y-16,52,22),6,6);dc.Pop();
                }
                foreach(WinterTree tree in snow.Trees) {
                    if (tree.Hidden) continue;
                    if(tree.Angle!=0) dc.PushTransform(new RotateTransform(tree.Angle,tree.X,tree.Y));
                    var shape=new StreamGeometry();
                    using(var c=shape.Open()) {
                        c.BeginFigure(new Point(tree.X,tree.Y-tree.Size-3),true,true);
                        c.LineTo(new Point(tree.X-tree.Size*.32,tree.Y-3),true,false);
                        c.LineTo(new Point(tree.X+tree.Size*.32,tree.Y-3),true,false);
                    }
                    dc.DrawGeometry(Hit,null,shape);
                    if(tree.Angle!=0) dc.Pop();
                }
            }
        }
    }
}
