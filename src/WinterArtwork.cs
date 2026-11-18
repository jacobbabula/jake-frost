using System;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;

namespace Frostpane
{
    internal static partial class SnowArtwork
    {
        internal static Drawing TreeBodyDrawing()
        {
            var group=new DrawingGroup();
            using(var g=group.Open()) WinterArt.PaintTree(g,0);
            group.Freeze();return group;
        }
        internal static ImageSource TreePreview(TreeTrim trim,int palette)
        {
            var group=new DrawingGroup();
            using(var dc=group.Open()) WinterArt.DrawTree(dc,0,0,1,palette,0,trim,0);
            var image=new DrawingImage(group);image.Freeze();return image;
        }
        private static class WinterArt
        {
            private sealed class IceArt
            {
                internal int Level;
                internal double Width;
                internal Sprite Drawing;
            }

            private sealed class StringArt
            {
                internal double Width, Rise, Sag, BulbScale, Phase;
                internal int Palette;
                internal Sprite Cable;
                internal readonly Sprite[] Lamps=new Sprite[4];
            }
            private struct Lamp
            {
                internal Point Wire,Socket;
                internal int Color;
            }

            private static readonly ConditionalWeakTable<SnowBank, IceArt> IceCache =
                new ConditionalWeakTable<SnowBank, IceArt>();
            private static readonly ConditionalWeakTable<LightString, StringArt> StringCache =
                new ConditionalWeakTable<LightString, StringArt>();
            private static readonly Brush IceRim = Vertical("#B9EAF9FF", "#927AB4D8", "#4689C5E5");
            private static readonly Brush IceBody = Vertical("#B4ECF8FF", "#90B6DDEA", "#549AC7DE");
            private static readonly Brush IceShade = Ink("#727CA6BD");
            private static readonly Pen IceEdge = Stroke("#CAF8FFFF", .86);
            private static readonly Pen FernStem = Stroke("#A5DEEFFF", .84);
            private static readonly Pen FernVein = Stroke("#89E6F7FF", .64);
            private static readonly Pen CableShadow = Stroke("#E3213435", 2.25);
            private static readonly Pen Cable = Stroke("#D38AA599", .84);
            private static readonly Pen PendantWire = Stroke("#E84C6359", 1.02);
            private static readonly Brush Clamp = Ink("#977151");
            private static readonly Brush ClampGlint = Ink("#EDD5A4");
            private static readonly Brush BulbTop = Ink("#616459");
            private static readonly Pen BulbRib = Stroke("#A79178", .58);
            private static readonly Pen GlassLine = Stroke("#EDFFFFFF", .75);
            private static readonly Brush[] Powder = CreatePowder();
            private static readonly Pen Trail = Stroke("#77E6F6FF", 1.6);
            private static readonly Pen FineTrail = Stroke("#50E4F6FF", .9);

            // Each palette references a small common collection of mouth-blown bulb silhouettes.
            private static readonly int[][] Palettes = {
                new int[] { 0, 1, 0, 2, 0, 1 },
                new int[] { 3, 0, 4, 6, 5, 2, 8, 7 },
                new int[] { 7, 4, 5, 6, 8, 6, 5, 7 }
            };
            private static readonly string[,] Glass = {
                {"#FFF9C9","#FFCE36","#D47B14","#B8FFBD28"},
                {"#FFFFEF","#FFE3A2","#C59A54","#A8FFDB87"},
                {"#FFF2AE","#FF9638","#CD571D","#B9FF852C"},
                {"#FFD4C8","#FF434C","#A6113C","#C8FF334E"},
                {"#CDFFC6","#36ED8E","#0C865F","#B840FF8B"},
                {"#CCECFF","#499FFF","#3549BC","#BE479DFF"},
                {"#F9D7FF","#C36AFF","#7032AE","#C79F49FF"},
                {"#C5FFFB","#29E3EA","#0C8EAC","#B741FFF2"},
                {"#FFDEF3","#FF5BAE","#B32175","#C9FF48AE"}
            };
            private static readonly Lazy<Sprite[]> Bulbs = new Lazy<Sprite[]>(BuildBulbs);
            private static readonly Sprite[] Trees = new Sprite[3];
            private static readonly Sprite[] Garlands=new Sprite[3];
            private static readonly Sprite[,] Baubles=new Sprite[3,3];
            private static readonly Sprite[,,] TreeLamps=new Sprite[3,3,3];
            private static readonly Lazy<Sprite> SledRight=new Lazy<Sprite>(delegate {return new Sprite(PaintSled);});
            private static readonly Lazy<Sprite> SledLeft=new Lazy<Sprite>(delegate {return new Sprite(PaintSled,true);});

            private static Brush[] CreatePowder()
            {
                Brush[] brushes = new Brush[10];
                for (int i = 0; i < brushes.Length; i++)
                {
                    Color c = Color.FromArgb((byte)(20 + 220*i/(brushes.Length-1)), 239, 249, 255);
                    Color edge = Color.FromArgb((byte)(c.A/2), 198, 229, 248);
                    RadialGradientBrush brush = new RadialGradientBrush();
                    brush.GradientStops.Add(new GradientStop(c,0));
                    brush.GradientStops.Add(new GradientStop(edge,.52));
                    brush.GradientStops.Add(new GradientStop(Color.FromArgb(0,190,221,238),1));
                    brush.Freeze();
                    brushes[i] = brush;
                }
                return brushes;
            }

            internal static void DrawPowder(DrawingContext dc, Flake f)
            {
                double life = Math.Max(0, Math.Min(1, f.Lifetime > 0 ? f.Life / f.Lifetime : 1));
                int index = (int)(life * (Powder.Length-1));
                if (f.Wisp) {
                    double size=f.Radius*(.68+2.1*(1-life));
                    Brush mist=Powder[Math.Min(Powder.Length-1,(int)(2+life*5))];
                    double side=f.Phase>Math.PI ? -1 : 1;
                    dc.DrawEllipse(Powder[index],null,new Point(f.X,f.Y),size,size*.79);
                    dc.DrawEllipse(mist,null,new Point(f.X+side*size*.53,f.Y-size*.18),size*.73,size*.64);
                    return;
                }
                double expansion = f.Radius * (1.28 + .62*(1-life));
                dc.DrawEllipse(Powder[index], null, new Point(f.X,f.Y), expansion, expansion*.85);
            }

            internal static void DrawThrow(DrawingContext dc, SnowBall ball)
            {
                double speed = Math.Sqrt(ball.Vx*ball.Vx + ball.Vy*ball.Vy);
                if (speed < 200) return;
                double dx = ball.Vx/speed, dy = ball.Vy/speed;
                double tail = Math.Min(29, 5+speed*.025);
                double r = ball.Radius;
                for (int i = -1; i <= 1; i++) {
                    double bx = ball.X-dx*r*.78 - dy*i*r*.46;
                    double by = ball.Y-dy*r*.78 + dx*i*r*.46;
                    double length = i==0 ? tail : tail*.58;
                    dc.DrawLine(i==0?Trail:FineTrail, new Point(bx,by),
                        new Point(bx-dx*length,by-dy*length));
                }
            }

            internal static void DrawObjects(DrawingContext dc, SnowScene scene)
            {
                int palette = Math.Max(0,Math.Min(2,scene.LightPalette));
                foreach (WinterTree tree in scene.Trees) {
                    if(tree.Hidden) continue;
                    if(tree.Angle!=0) dc.PushTransform(new RotateTransform(tree.Angle,tree.X,tree.Y));
                    DrawTree(dc,tree.X,tree.Y,tree.DisplaySize/96,tree.Palette<0?palette:tree.Palette,
                        Math.Abs(tree.Style%3),scene.TwinkleLights ? tree.Trim : tree.Trim & ~TreeTrim.Twinkle,scene.Time);
                    if(tree.Angle!=0) dc.Pop();
                }
                foreach (LightString strand in scene.Lights)
                    if(!strand.Hidden) DrawString(dc,strand,palette,scene.Time,scene.TwinkleLights);
                foreach (WinterSled sled in scene.Sleds)
                {
                    double y=sled.DisplayY;
                    var sprite=(sled.Facing<0?SledLeft:SledRight).Value;
                    if (sled.DisplayAngle==0) sprite.Draw(dc,sled.X,y,1);
                    else {
                        dc.PushTransform(new RotateTransform(sled.DisplayAngle,sled.X,y));
                        sprite.Draw(dc,sled.X,y,1);
                        dc.Pop();
                    }
                }
            }

            private static Sprite[] BuildBulbs()
            {
                Sprite[] result = new Sprite[Glass.GetLength(0)];
                for (int i=0;i<result.Length;i++)
                {
                    int color=i;
                    result[i] = new Sprite(delegate(DrawingContext dc) {
                        RadialGradientBrush glow = new RadialGradientBrush();
                        glow.GradientStops.Add(Stop(Glass[color,3],0));
                        Color rim=(Color)ColorConverter.ConvertFromString(Glass[color,1]);
                        glow.GradientStops.Add(new GradientStop(Color.FromArgb(46,rim.R,rim.G,rim.B),.49));
                        glow.GradientStops.Add(new GradientStop(Color.FromArgb(0,rim.R,rim.G,rim.B),1));
                        glow.Freeze();
                        Dot(dc,glow,0,5.5,12,13);
                        var glass=new RadialGradientBrush {
                            Center=new Point(.42,.4),GradientOrigin=new Point(.3,.29),RadiusX=.74,RadiusY=.73 };
                        glass.GradientStops.Add(Stop(Glass[color,0],0));glass.GradientStops.Add(Stop(Glass[color,1],.51));
                        glass.GradientStops.Add(Stop(Glass[color,2],1));glass.Freeze();
                        Path(dc,glass,null,
                            "M -1.55,1.6 C -2.9,3.1 -3.8,5.1 -3.05,7.2 Q -2.2,9.15 0,10 Q 2.2,9.15 3.05,7.2 C 3.8,5.1 2.9,3.1 1.55,1.6 Z");
                        dc.DrawRoundedRectangle(BulbTop,null,new Rect(-1.7,-.2,3.4,2.5),.55,.55);
                        dc.DrawLine(BulbRib,new Point(-1.3,.95),new Point(1.2,.95));
                        Path(dc,null,GlassLine,"M -1.1,3.5 Q -2.2,4.5 -1.95,5.7");
                        Dot(dc,Ink("#C4FFFFFF"),1.05,7.6,.55,.55);
                    });
                }
                return result;
            }

            private static void DrawString(DrawingContext dc, LightString strand, int palette,double time,bool twinkle)
            {
                double dx=strand.X2-strand.X1, dy=strand.Y2-strand.Y1;
                if (Math.Abs(dx)+Math.Abs(dy)<4) return;
                double sag=strand.Sag,scale=strand.BulbScale;
                if(strand.Palette>=0) palette=strand.Palette;
                StringArt art=StringCache.GetOrCreateValue(strand);
                if (art.Cable==null) art.Phase=(strand.X1*.013+strand.Y1*.022)%(2*Math.PI);
                if (art.Cable==null || Math.Abs(dx-art.Width)>.24 || Math.Abs(dy-art.Rise)>.24 ||
                    Math.Abs(sag-art.Sag)>.24 || scale!=art.BulbScale || art.Palette!=palette)
                {
                    art.Width=dx; art.Rise=dy; art.Palette=palette;art.Sag=sag;art.BulbScale=scale;
                    Lamp[] lamps=SpaceBulbs(dx,dy,sag,scale,palette);
                    art.Cable=new Sprite(delegate(DrawingContext draw) { PaintWire(draw,dx,dy,sag,lamps); });
                    for(int i=0;i<art.Lamps.Length;i++) {
                        int offset=i;
                        art.Lamps[i]=new Sprite(delegate(DrawingContext draw) {
                            for(int j=offset;j<lamps.Length;j+=art.Lamps.Length) {
                                Lamp lamp=lamps[j];
                                Bulbs.Value[lamp.Color].Draw(draw,lamp.Socket.X,lamp.Socket.Y,1.1*scale);
                            }
                        });
                    }
                }
                art.Cable.Draw(dc,strand.X1,strand.Y1,1);
                // Animate four interleaved circuits. Bulbs and wire remain frozen between edits.
                for(int i=0;i<art.Lamps.Length;i++) {
                    if(twinkle) {
                        double wave=.5+.5*Math.Sin(time*(1.52+i*.21)+i*2.40+art.Phase);
                        dc.PushOpacity(.41+.59*wave*wave);
                    }
                    art.Lamps[i].Draw(dc,strand.X1,strand.Y1,1);
                    if(twinkle) dc.Pop();
                }
            }

            private static void PaintWire(DrawingContext dc,double dx,double dy,double sag,Lamp[] lamps)
            {
                StreamGeometry cable=new StreamGeometry();
                using (StreamGeometryContext line=cable.Open())
                {
                    line.BeginFigure(new Point(0,0),false,false);
                    line.QuadraticBezierTo(new Point(dx*.5,dy*.5+2*sag),new Point(dx,dy),true,true);
                }
                cable.Freeze();
                dc.DrawGeometry(null,CableShadow,cable);
                dc.DrawGeometry(null,Cable,cable);
                foreach(Lamp lamp in lamps) dc.DrawLine(PendantWire,lamp.Wire,lamp.Socket);
                Dot(dc,Clamp,0,0,2.15,1.75); Dot(dc,ClampGlint,-.35,-.45,.68,.49);
                Dot(dc,Clamp,dx,dy,2.15,1.75); Dot(dc,ClampGlint,dx-.35,dy-.45,.68,.49);
            }

            private static Lamp[] SpaceBulbs(double dx,double dy,double sag,double scale,int palette)
            {
                // Space bulbs by distance along the wire, even on steep, deeply bowed strands.
                const int sections=24;
                double[] distances=new double[sections+1];
                double prevY=0;
                for(int j=1;j<=sections;j++) {
                    double t=(double)j/sections,y=dy*t+4*sag*t*(1-t);
                    distances[j]=distances[j-1]+Math.Sqrt(dx*dx/(sections*sections)+(y-prevY)*(y-prevY));prevY=y;
                }
                double length=distances[sections];
                int lamps=Math.Max(1,Math.Min(240,(int)Math.Round(length/(21*Math.Sqrt(scale)))));
                var layout=new Lamp[lamps];
                int[] sequence=Palettes[palette];
                int section=1;
                for (int i=0;i<lamps;i++) {
                    double pos=length*(i+.5)/lamps;
                    while(section<sections && pos>distances[section]) section++;
                    double t=(section-1+(pos-distances[section-1])/Math.Max(.001,distances[section]-distances[section-1]))/sections;
                    double x=dx*t, y=dy*t+4*sag*t*(1-t);
                    double drop=(i%3==1 ? 5.4 : 3.1)*scale;
                    layout[i]=new Lamp {Wire=new Point(x,y),Socket=new Point(x,y+drop),Color=sequence[i%sequence.Length]};
                }
                return layout;
            }

            private static uint SeedFor(string id)
            {
                uint seed=2166136261u;
                if (id!=null) foreach (char c in id) seed=unchecked((seed^c)*16777619u);
                return seed;
            }

            private static double Next(ref uint state)
            {
                state=unchecked(state*1664525u+1013904223u);
                return (state>>8)*(1.0/16777216);
            }

            internal static void DrawIce(DrawingContext dc,SnowBank bank,int level)
            {
                if (bank.Width<5) return;
                IceArt art=IceCache.GetOrCreateValue(bank);
                if (art.Drawing==null || art.Level!=level || Math.Abs(art.Width-bank.Width)>.65)
                {
                    art.Width=bank.Width; art.Level=level;
                    uint seed=SeedFor(bank.Id);
                    art.Drawing=new Sprite(delegate(DrawingContext draw) { PaintIce(draw,bank.Width,level,seed); });
                }
                art.Drawing.Draw(dc,bank.X,bank.Y,1);
            }

            private static void PaintIce(DrawingContext dc,double width,int level,uint seed)
            {
                double thickness=level==1?1.25:level==2?2.2:3.25;
                dc.DrawRoundedRectangle(IceRim,null,new Rect(0,-.45,width,thickness+.6),.7,.7);
                double x=5+Next(ref seed)*12;
                while (x<width-6)
                {
                    double scale=.72+Next(ref seed)*.49;
                    if (level>=2) {
                        double longTip=level==2?3.5+9*Next(ref seed):6+18*Next(ref seed);
                        Icicle(dc,x,thickness*.52,Math.Min(x,2.3+scale*level*.75),longTip);
                        if (Next(ref seed)>.25 && x+7<width-3) Icicle(dc,x+5.4,thickness*.55,1.85,longTip*.46);
                    }
                    if (x+11<width) FrostFern(dc,x+2,thickness*.5,scale*(level==3?1.25:1));
                    x+=15+Next(ref seed)*(level==1?38:level==2?27:20);
                }
            }

            private static void Icicle(DrawingContext dc,double x,double y,double rx,double length)
            {
                var origin=new Point(x-rx,y);
                var end=new Point(x-.22*rx,y+length);
                var right=new Point(x+rx,y);
                StreamGeometry shape=new StreamGeometry();
                using (var geo=shape.Open()) {
                    geo.BeginFigure(origin,true,true);
                    geo.LineTo(right,true,false);
                    geo.QuadraticBezierTo(new Point(x+rx*.53,y+length*.57),end,true,false);
                    geo.QuadraticBezierTo(new Point(x-rx*.8,y+length*.32),origin,true,false);
                }
                shape.Freeze();dc.DrawGeometry(IceBody,null,shape);
                StreamGeometry facet=new StreamGeometry();
                using(var g=facet.Open()){
                    g.BeginFigure(new Point(x+rx*.45,y),true,true);
                    g.LineTo(right,true,false);g.LineTo(end,true,false);
                }
                facet.Freeze();dc.DrawGeometry(IceShade,null,facet);
                dc.DrawLine(IceEdge,new Point(x-rx*.58,y+.2),new Point(x-rx*.32,y+length*.66));
            }

            private static void FrostFern(DrawingContext dc,double x,double y,double s)
            {
                dc.DrawLine(FernStem,new Point(x,y),new Point(x+8*s,y+4.3*s));
                for(int i=1;i<=3;i++){
                    double tx=x+(1.5+i*1.35)*s, ty=y+(1+i*.66)*s, length=(3.1-i*.36)*s;
                    dc.DrawLine(FernVein,new Point(tx,ty),new Point(tx+.27*s,ty+length));
                    dc.DrawLine(FernVein,new Point(tx,ty),new Point(tx+length,ty-.52*s));
                }
            }

            internal static void DrawTree(DrawingContext dc,double x,double y,double size,int palette,int style,TreeTrim trim,double time)
            {
                if(Trees[style]==null) Trees[style]=new Sprite(delegate(DrawingContext g){PaintTree(g,style);});
                Trees[style].Draw(dc,x,y,size);
                if((trim&TreeTrim.Lights)!=0) {
                    if(Garlands[style]==null) Garlands[style]=new Sprite(delegate(DrawingContext g){
                        Path(g,null,Stroke("#947E6B49",.9),"M -8,-63 Q -1,-60 8,-66 M -14.5,-47 Q -3,-42 14,-51 M -21,-29 Q -3,-22 20,-33");
                    });
                    Garlands[style].Draw(dc,x,y,size);
                    bool twinkle=(trim&TreeTrim.Twinkle)!=0;
                    for(int i=0;i<3;i++) {
                        int group=i;
                        if(TreeLamps[palette,style,i]==null) TreeLamps[palette,style,i]=new Sprite(delegate(DrawingContext g){
                            PaintTreeLamps(g,palette,style,group);
                        });
                        if(twinkle) dc.PushOpacity(.65+.34*Math.Sin(time*(1.6+i*.23)+i*2.39+style));
                        TreeLamps[palette,style,i].Draw(dc,x,y,size);
                        if(twinkle) dc.Pop();
                    }
                }
                if((trim&TreeTrim.Baubles)!=0) {
                    if(Baubles[palette,style]==null) Baubles[palette,style]=new Sprite(delegate(DrawingContext g){
                        double[] spots={-4,-70,6,-57,-11,-54,2,-40,15,-34,-19,-22,-6,-19,9,-19};
                        int[] colors=Palettes[palette];
                        var cap=Ink("#DCBC85");
                        for(int i=0;i<spots.Length;i+=2) {
                            int color=colors[(i/2+style)%colors.Length];
                            double px=spots[i],py=spots[i+1];
                            g.DrawLine(BulbRib,new Point(px,py-2),new Point(px,py));
                            g.DrawRoundedRectangle(cap,null,new Rect(px-.8,py-.75,1.6,1.3),.3,.3);
                            Dot(g,Vertical(Glass[color,0],Glass[color,1],Glass[color,2]),px,py+2.3,2.45,2.5);
                            Dot(g,Ink("#F5FFF8"),px-.85,py+1.4,.48,.48);
                        }
                    });
                    Baubles[palette,style].Draw(dc,x,y,size);
                }
            }

            internal static void PaintTree(DrawingContext dc,int style)
            {
                // The foot and star lie at 0 and -96 DIP. The boughs overlap to show a conical crown.
                Path(dc,Vertical("#A47C59","#76523C","#513F35"),null,"M -3.2,-17 L 3.7,-17 3.2,-1 Q .3,1 -3.4,-.5 Z");
                Path(dc,Ink("#6E5543"),null,"M -2.5,-2 L -6.5,-.3 -5,1 0,-.4 5.7,.8 6.2,-.1 2.6,-2 Z");
                string[] dark={"#28514D","#2A5353","#31544C"};
                string[] mid={"#3D7266","#416F6D","#4C7365"};
                string[] top={"#759C83","#779E9B","#849F88"};
                Brush branch=Vertical(top[style],mid[style],dark[style]);
                Brush shadow=Ink(dark[style]), cap=Vertical("#F2F8EF","#DFEBE6","#AECDD0");
                Path(dc,branch,null,"M 0,-64 Q -6,-53 -15,-45 L -10,-46 Q -16,-35 -24,-31 L -18,-31 Q -23,-22 -32,-18 Q -23,-14 -15,-17 L -18,-13 Q -11,-12 -6,-15 L -7,-12 Q 2,-9 9,-12 L 8,-10 Q 14,-10 21,-13 L 19,-16 Q 25,-15 31,-19 Q 23,-23 18,-31 L 23,-30 Q 15,-37 11,-45 L 15,-44 Q 6,-52 0,-64 Z");
                Path(dc,shadow,null,"M -21,-22 Q -12,-21 -6,-25 L -7,-22 Q 1,-20 8,-23 L 8,-21 Q 17,-19 22,-23 Q 13,-27 8,-32 L -5,-32 Z");
                Path(dc,cap,null,"M -29,-19 Q -22,-21 -17,-25 L -18,-23 Q -12,-23 -9,-26 Q -9,-23 -12,-22 L -10,-22 Q -15,-18 -20,-18 L -20,-16 Q -26,-16 -29,-19 Z M 6,-20 Q 13,-21 17,-25 Q 20,-21 25,-20 Q 22,-18 17,-18 Q 16,-16 12,-17 Q 9,-16 6,-20 Z");
                Path(dc,branch,null,"M 0,-76 Q -4,-66 -12,-58 L -9,-59 Q -13,-51 -21,-45 L -17,-45 Q -20,-40 -25,-38 Q -20,-35 -13,-37 L -15,-34 Q -9,-32 -3,-36 L -4,-33 Q 4,-31 10,-35 L 9,-33 Q 18,-32 25,-38 Q 17,-42 14,-47 L 17,-46 Q 10,-54 7,-59 L 11,-58 Q 4,-67 0,-76 Z");
                Path(dc,cap,null,"M -23,-39 Q -15,-42 -11,-48 L -12,-45 Q -6,-45 -2,-49 Q -3,-44 -8,-42 Q -13,-37 -19,-37 Z M 5,-41 Q 10,-42 13,-46 Q 17,-41 22,-40 Q 19,-37 15,-38 Q 10,-37 5,-41 Z");
                Path(dc,branch,null,"M .3,-86 Q -3,-78 -7,-73 L -5,-74 Q -8,-67 -14,-62 L -11,-62 Q -15,-56 -18,-55 Q -12,-52 -7,-56 L -8,-53 Q -3,-52 2,-56 L 2,-54 Q 9,-52 17,-56 Q 11,-61 8,-67 L 10,-67 Q 4,-74 .3,-86 Z");
                Path(dc,cap,null,"M -15,-58 Q -8,-62 -4,-70 Q -4,-66 -2,-67 Q -4,-61 -8,-59 L -6,-59 Q -12,-54 -15,-58 Z M 0,-80 Q 1,-76 4,-74 L 6,-71 Q 2,-71 1,-73 Q -1,-72 -3,-72 Z");
                Path(dc,Vertical("#FFF0AC","#F6C467","#C88D46"),Stroke("#9E874A",.55),
                    "M .1,-95.6 L 2.05,-91.05 6.9,-90.5 3.2,-87.35 4.3,-82.6 .1,-85 -4.1,-82.6 -3.15,-87.35 -6.9,-90.5 -2,-91.05 Z");
                Path(dc,Ink("#FFF9C9"),null,"M .1,-94.4 L .6,-89.55 -4.6,-90.2 -1.5,-90.55 Z");
            }

            private static void PaintTreeLamps(DrawingContext dc,int palette,int style,int group)
            {
                double[] spots={-6,-63,3,-63.4,-9,-46.2,.8,-45.8,10,-48.4,-17,-28.3,-9,-26.5,1,-26.8,13,-29,-2,-74};
                int[] seq=Palettes[palette];
                for(int i=group*2;i<spots.Length;i+=6) {
                    int color=seq[(i/2+style)%seq.Length];
                    double x=spots[i],y=spots[i+1];
                    Dot(dc,Ink(Glass[color,3]),x,y+1.45,3.4,3.4);
                    Dot(dc,Ink(Glass[color,2]),x,y+1.35,1.65,1.85);
                    Dot(dc,Ink(Glass[color,1]),x-.13,y+1.15,1.35,1.5);
                    Dot(dc,Ink(Glass[color,0]),x-.45,y+.63,.53,.55);
                }
            }

            private static void PaintSled(DrawingContext dc)
            {
                Pen bronze=Stroke("#8B624E",1.8), iron=Stroke("#48636E",2.25);
                Pen steel=Stroke("#DCE8E6",.78), cord=Stroke("#9B6643",.95);
                Path(dc,null,bronze,"M -16,-3 L 11,-3 Q 16,-3 19,-9 Q 20,-12 17,-12 M -10,-4 L -8.5,-10 M 6,-4 L 8,-10");
                Path(dc,Vertical("#D39A63","#B6794E","#905940"),Stroke("#795547",.65),
                    "M -16,-12.1 L 10.1,-12.1 13.8,-9.7 13.4,-8.2 -13.5,-8.1 -17.4,-10.1 Z");
                Path(dc,Ink("#DDA76C"),null,"M -16,-12.4 L 10.4,-12.4 13.5,-10.15 -13.4,-10.2 Z");
                Path(dc,null,Stroke("#8B644B",.6),"M -11.9,-12.1 L -9,-10.2 M -4.2,-12.1 L -1.3,-10.2 M 3.2,-12.1 L 6,-10.2");
                Path(dc,null,Stroke("#B45345",2.15),"M -11,-8.2 L -13,-1.3 M 6.3,-8.1 L 8.8,-1.3 M -12,-2.2 L 7.6,-7.6");
                Dot(dc,Ink("#F1C587"),-10.9,-8.4,.7,.7);Dot(dc,Ink("#F1C587"),6.3,-8.3,.7,.7);
                Path(dc,null,iron,"M -20,-.4 Q -18,.45 -14,.45 L 13.5,.4 Q 20,.2 21.4,-7 Q 22,-10.9 18.7,-11.3 Q 17.1,-11.2 17.1,-9.8");
                Path(dc,null,steel,"M -16,0 L 13.3,0 Q 18.8,0 20.4,-5.7");
                Path(dc,null,cord,"M 13.1,-9.9 Q 15.5,-4.1 21.2,-9.1 Q 24.5,-13.2 25.4,-11.4 Q 26,-9.9 24.6,-9.4");
            }
        }
    }
}
