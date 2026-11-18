using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Frostpane;

// Offscreen integration fixture. Step and Draw are the same simulation and WPF artwork
// entry points used by SnowSurface in the installed app.
internal static class PloughSheet
{
    const int W=410, H=240, ViewH=140, Cut=100, CellW=W+12, RowH=ViewH+37;
    static readonly Brush Paper=Brush("#152734"), Light=Brush("#EAF0F3"), Muted=Brush("#A6C7D6");
    static readonly Brush Back=new LinearGradientBrush(Color.FromRgb(28,47,60),Color.FromRgb(54,79,92),90);

    static SolidColorBrush Brush(string hex) { return new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)); }
    static void Label(DrawingContext dc,string text,double x,double y,double size,Brush ink) {
        dc.DrawText(new FormattedText(text,CultureInfo.InvariantCulture,FlowDirection.LeftToRight,
                    new Typeface("Segoe UI"),size,ink,1.0),new Point(x,y));
    }

    static SnowScene Setup(int dir,bool ridge,int size) {
        var scene=new SnowScene(49);
        scene.SnowVolume=0; scene.DriftDepth=100; scene.Resize(W,H); scene.Clear();
        scene.SetVisitorSize(VisitorSizeTarget.Snowplow,size);
        if(dir<0) {scene.SendSnowplough();scene.Clear();}
        var bank=scene.Banks[0];
        for(int i=0;i<bank.Heights.Length;i++) {
            double x=bank.X+i*bank.Width/(bank.Heights.Length-1);
            double oriented=dir>0?x:W-x;
            // A uniform blanket and a tall, fairly steep bank with a short sparse approach.
            double h=ridge?6+66*Math.Max(0,Math.Min(1,(oriented-185)/20))*Math.Max(0,Math.Min(1,(300-oriented)/20)):30;
            bank.Heights[i]=h;
        }
        bank.Revision++;
        double ballX=dir>0?225:W-225;
        scene.Balls.Add(new SnowBall{X=ballX,Y=H-bank.PaintedHeightAt(ballX)-11,Radius=11});
        double propX=dir>0?286:W-286, baseY=H-bank.PaintedHeightAt(propX)-2;
        scene.Tool=PlayTool.Decorate;scene.SelectedDecoration=DecorationKind.Gift;
        scene.PlayDown(propX,baseY);scene.PlayUp(propX,baseY);
        scene.SendSnowplough();
        if(scene.Plough==null||scene.Plough.Facing!=dir)throw new InvalidOperationException("Directional fixture failed");
        return scene;
    }

    static void Row(DrawingContext dc,int row,int dir,bool ridge,int size) {
        var s=Setup(dir,ridge,size); var p=s.Plough;
        double[] checkpoints={94,188,289};
        double peak=0, maxGap=0;
        double y=62+row*RowH;
        Label(dc,(ridge?"High bank":"Flat blanket")+"   "+size+"%"+(dir>0?"   →  left to right":"   ←  right to left"),12,y-22,14,Light);
        for(int col=0;col<checkpoints.Length;col++) {
            double target=checkpoints[col]; int ticks=0;
            while ((dir>0?p.X:W-p.X)<target) {
                if(++ticks>3000)throw new InvalidOperationException("Plough did not reach checkpoint");
                s.Step(1.0/60,0,0);
                if(s.Plough==null)throw new InvalidOperationException("Plough left prematurely");
                peak=Math.Max(peak,Math.Abs(p.Incline));
                double rad=p.Incline*Math.PI/180, scale=p.Scale;
                foreach(double axle in new[]{-20.0,14.0}) {
                    double cx=p.X+(axle*dir*Math.Cos(rad)+6.4*Math.Sin(rad))*scale;
                    if(cx<0||cx>W)continue;
                    double bottom=p.Y+(axle*dir*Math.Sin(rad)-6.4*Math.Cos(rad)+6.4)*scale;
                    maxGap=Math.Max(maxGap,H-s.Banks[0].PaintedHeightAt(cx)-bottom);
                }
            }
            double x=12+col*CellW;
            dc.PushTransform(new TranslateTransform(x,y));
            dc.PushClip(new RectangleGeometry(new Rect(0,0,W,ViewH)));
            dc.DrawRectangle(Back,null,new Rect(0,0,W,ViewH));
            dc.PushTransform(new TranslateTransform(0,-Cut));
            SnowArtwork.Draw(dc,s);
            dc.Pop(); dc.Pop(); dc.Pop();
            Label(dc,(col==0?"Approach":col==1?"Contact":"After contact")+String.Format(CultureInfo.InvariantCulture,"   {0:0.0}°",p.Incline),
                  x+8,y+6,11,Muted);
        }
        Console.WriteLine("{0}, {1}: peak pitch {2:F2} degrees, maximum gap below a wheel {3:F2}px, final ball x {4:F1}",
            ridge?"Ridge":"Flat",dir>0?"right":"left",peak,maxGap,s.Balls.Count>0?s.Balls[0].X:-1);
    }

    [STAThread] static void Main(string[] args) {
        var dv=new DrawingVisual();
        int width=CellW*3+12, height=6*RowH+39;
        using(var dc=dv.RenderOpen()){
            dc.DrawRectangle(Paper,null,new Rect(0,0,width,height));
            Label(dc,"Jake Frost  /  "+args[1]+"  /  native Windows snowplow",12,7,19,Light);
            Row(dc,0,1,false,160);Row(dc,1,-1,false,160);
            Row(dc,2,1,true,75);Row(dc,3,-1,true,75);
            Row(dc,4,1,true,225);Row(dc,5,-1,true,225);
        }
        var bmp=new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32);bmp.Render(dv);
        var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bmp));
        using(var output=File.Create(Path.GetFullPath(args[0])))png.Save(output);
    }
}
