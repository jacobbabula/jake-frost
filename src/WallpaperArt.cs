using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Frostpane
{
    internal sealed class WallpaperArt : FrameworkElement
    {
        internal WallpaperTime TimeMode;
        internal bool Animate;
        internal double Seconds;
        private WallpaperScene scene;
        private double dark;
        private DrawingImage landscape;
        private const double W=1672,H=941;
        private static readonly Rect area=new Rect(0,0,W,H);
        private static readonly Brush mist=Glow(Color.FromRgb(226,234,242));
        private static readonly Brush beacon=Glow(Color.FromRgb(255,202,117));
        private static readonly Pen ripple=new Pen(new SolidColorBrush(Color.FromArgb(125,212,235,231)),1.3);
        private static readonly Geometry beam=Geometry.Parse("M0,0 L-575,-26 Q-590,-3 -575,27 Z");
        private static readonly LinearGradientBrush shaft=new LinearGradientBrush(
            Color.FromArgb(0,255,236,187),Color.FromArgb(116,255,218,150),0);
        static WallpaperArt() {ripple.Freeze();beam.Freeze();shaft.Freeze();}
        private static Brush Glow(Color c) {
            var brush=new RadialGradientBrush();
            brush.GradientStops.Add(new GradientStop(c,0));
            brush.GradientStops.Add(new GradientStop(Color.FromArgb(98,c.R,c.G,c.B),.46));
            brush.GradientStops.Add(new GradientStop(Color.FromArgb(0,c.R,c.G,c.B),1));
            brush.Freeze();return brush;
        }
        internal static BitmapSource Load(WallpaperScene scene,bool night=false) {
            string name="JakeFrost.Wallpaper."+scene+(night?"Night":"");
            using(var input=typeof(WallpaperArt).Assembly.GetManifestResourceStream(name)) {
                if(input==null) throw new System.IO.InvalidDataException("Missing landscape: "+name);
                var bitmap=new BitmapImage();bitmap.BeginInit();
                bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.StreamSource=input;bitmap.EndInit();bitmap.Freeze();return bitmap;
            }
        }
        private static double Smooth(double value) {value=Math.Max(0,Math.Min(1,value));return value*value*(3-2*value);}
        internal void Configure(BitmapSource day,BitmapSource night,WallpaperScene selected,WallpaperTime time,bool moving) {
            Animate=moving;TimeMode=time;scene=selected;
            double[] hours={0,6,9,12,17.5,19.4,0};
            double hour=time==WallpaperTime.Clock ? DateTime.Now.TimeOfDay.TotalHours : hours[(int)time];
            double light=Smooth((hour-4.7)/3.6)*(1-Smooth((hour-17.0)/3.8));
            dark=1-light;
            double warm=Math.Max(Math.Exp(-Math.Pow((hour-6.7)/1.4,2)),Math.Exp(-Math.Pow((hour-17.9)/1.45,2)));
            var drawing=new DrawingGroup();
            using(var dc=drawing.Open()) {
                dc.DrawImage(day,area);
                if(dark>.001) {dc.PushOpacity(dark);dc.DrawImage(night,area);dc.Pop();}
                if(warm>.005) {
                    var wash=new LinearGradientBrush();wash.StartPoint=new Point(0,0);wash.EndPoint=new Point(.15,1);
                    wash.GradientStops.Add(new GradientStop(Color.FromArgb(62,149,86,157),0));
                    wash.GradientStops.Add(new GradientStop(Color.FromArgb(122,255,162,94),.33));
                    wash.GradientStops.Add(new GradientStop(Color.FromArgb(38,244,170,129),.66));
                    wash.GradientStops.Add(new GradientStop(Color.FromArgb(28,115,77,112),1));
                    dc.PushOpacity(warm);dc.DrawRectangle(wash,null,area);dc.Pop();
                }
            }
            landscape=new DrawingImage(drawing);landscape.Freeze();
        }
        protected override void OnRender(DrawingContext dc) {
            if(landscape==null || ActualWidth<1 || ActualHeight<1) return;
            double scale=Math.Max(ActualWidth/W,ActualHeight/H);
            dc.PushClip(new RectangleGeometry(new Rect(RenderSize)));
            dc.PushTransform(new MatrixTransform(scale,0,0,scale,(ActualWidth-W*scale)/2,(ActualHeight-H*scale)/2));
            dc.DrawImage(landscape,area);
            if(scene==WallpaperScene.Switchback) {
                // Chimney cap is at (1511,151) in the painted master.
                for(int i=0;i<13;i++) {
                    double t=(Seconds*.092+i/13.0)%1;
                    dc.PushOpacity(.29*Math.Sin(Math.PI*t));
                    double x=1511-77*t+8*t*Math.Sin(Seconds*.36+i*.7),y=151-105*t;
                    dc.DrawEllipse(mist,null,new Point(x,y),5+21*t,4+14*t);dc.Pop();
                }
            } else {
                double sweep=Math.Cos(Seconds*.51);
                dc.PushTransform(new TranslateTransform(1356,282));
                dc.PushTransform(new ScaleTransform(sweep,.7+Math.Abs(sweep)*.25));
                dc.PushOpacity(.09+.40*dark);dc.DrawGeometry(shaft,null,beam);dc.Pop();dc.Pop();dc.Pop();
                dc.PushOpacity((.23+.39*dark)*(.7+.3*Math.Cos(Seconds*1.02)));
                dc.DrawEllipse(beacon,null,new Point(1356,282),36,26);dc.Pop();
                for(int i=1;i<=31;i++) {
                    double x=(i*137%950)+5*Math.Sin(Seconds*.37+i),y=450+(i*173%245);
                    double wave=.5+.5*Math.Sin(Seconds*1.3+i);
                    dc.PushOpacity(.12+.24*wave);dc.DrawLine(ripple,new Point(x,y),new Point(x+5+15*wave,y-.5));dc.Pop();
                }
            }
            if(dark>.2) for(int i=1;i<48;i++) {
                double x=(i*5861)%1530+30,y=(i*1103)%132+9;
                dc.PushOpacity(dark*(.38+.22*Math.Sin(i+Seconds*.58)));
                dc.DrawEllipse(Brushes.AliceBlue,null,new Point(x,y),.65+i%3*.27,.65+i%3*.27);dc.Pop();
            }
            dc.Pop();dc.Pop();
        }
    }
}
