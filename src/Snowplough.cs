using System;
using System.Windows;
using System.Windows.Media;

namespace Frostpane
{
    internal sealed class WinterPlough
    {
        internal int Facing;
        internal double X, Y, Scale, Incline, Time, WheelTurn, Powder, LastSpray;
    }

    internal sealed partial class SnowScene
    {
        internal WinterPlough Plough;
        private int nextPloughSide = 1;
        private static readonly double[] truckWheels={-20,14};
        private double PloughScale {get{return Limit(height/420,.76,1.22)*visitorScales[(int)VisitorSizeTarget.Snowplow];}}
        private void SizePlough()
        {
            Plough.Scale=PloughScale;
            GroundWheels(Plough.X,Plough.Scale*Plough.Facing,truckWheels,6.4,out Plough.Y,out Plough.Incline);
        }

        internal void SendSnowplough()
        {
            if (Plough != null || floor == null || width < 1 || height < 1) return;
            double scale = PloughScale;
            Plough = new WinterPlough {
                Facing = nextPloughSide, Scale = scale, Y = height,
                X = nextPloughSide > 0 ? -41 * scale : width + 41 * scale,
                LastSpray = -.2
            };
            SizePlough();
            nextPloughSide = -nextPloughSide;
        }

        partial void ClearSnowplough() { Plough = null; }

        partial void StepSnowplough(double dt)
        {
            WinterPlough p = Plough;
            if (p == null || floor == null || dt <= 0) return;
            double margin = 41 * p.Scale;
            double previousX = p.X;
            p.Time += dt;
            double travel = 52 * VisitorPace * dt;
            p.X += p.Facing * travel;
            p.WheelTurn += travel / (6.2 * p.Scale);
            double pitch=p.Incline*Math.PI/180;
            double bladeOffset = (p.Facing*36*Math.Cos(pitch)+5*Math.Sin(pitch))*p.Scale;
            double tip = p.X + bladeOffset, previousTip = previousX + bladeOffset;
            double cell = floor.Width / (floor.Heights.Length-1);
            // Each blade crossing clears one height sample and passes its snow forward.
            int from = p.Facing > 0 ? (int)Math.Floor(previousTip/cell)+1 : (int)Math.Ceiling(previousTip/cell)-1;
            int to = p.Facing > 0 ? (int)Math.Floor(tip/cell) : (int)Math.Ceiling(tip/cell);
            bool touched = false;
            for (int i=from; p.Facing>0 ? i<=to : i>=to; i+=p.Facing)
            {
                if (i < 0 || i >= floor.Heights.Length) continue;
                double taken = Math.Max(0, floor.Heights[i] - .22);
                if (taken <= 0) continue;
                floor.Heights[i] -= taken;
                touched = true;
                p.Powder += taken * .35;
                // A graded wedge runs ahead of the blade. Excess spills off the front of the pass.
                double remaining = taken * .93;
                int reach = Math.Max(4, (int)Math.Ceiling(46 * p.Scale / cell));
                double weightSum = reach * (reach + 1) / 2.0;
                for (int n=1; n<=reach && remaining>.001; n++)
                {
                    int j = i + n * p.Facing;
                    if (j < 0 || j >= floor.Heights.Length) break;
                    double weight = reach-n+1;
                    double lift = Math.Min(Math.Max(0,floor.Maximum(j)-floor.Heights[j]), remaining*weight/weightSum);
                    floor.Heights[j] += lift;
                    remaining -= lift; weightSum -= weight;
                }
            }
            // Snow slumps behind a slow blade. The rear wheels pack a shallow track through it.
            double rearOffset = (-20*p.Facing*Math.Cos(pitch)+6.4*Math.Sin(pitch))*p.Scale;
            int rearBefore = (int)Math.Floor((previousX + rearOffset) / cell);
            int rearNow = (int)Math.Floor((p.X + rearOffset) / cell);
            for (int i = rearBefore; i != rearNow; i += p.Facing)
            {
                int sample = i + p.Facing;
                if (sample < 0 || sample >= floor.Heights.Length || floor.Heights[sample] <= 1) continue;
                floor.Heights[sample] = 1;
                touched = true;
            }
            if (touched) floor.Revision++;
            GroundWheels(p.X,p.Scale*p.Facing,truckWheels,6.4,out p.Y,out p.Incline);
            if (p.Powder>=1 && p.Time-p.LastSpray>=.10 && tip>=0 && tip<=width)
            {
                int amount = (int)Math.Min(9,p.Powder);
                PowderBurst(tip, floor.Y-floor.HeightAt(tip+p.Facing*5)-2, amount, p.Facing*65, .65);
                p.Powder = 0; p.LastSpray = p.Time;
            }
            if ((p.X <= -margin && p.Facing < 0) || (p.X >= width + margin && p.Facing > 0)) Plough = null;
        }
    }

    internal static partial class SnowArtwork
    {
        private static class PloughArtwork
        {
            internal static readonly Sprite Right = new Sprite(Paint);
            internal static readonly Sprite Left = new Sprite(Paint,true);
            internal static readonly Sprite[] Hubs = MakeHubs();
            internal static readonly Brush Beacon = Soft("#BEFFC461","#44FF9B27");

            private static void Paint(DrawingContext dc)
            {
                Brush frame = Ink("#24363C"), rubber = Ink("#202B30"), steel = Ink("#788F96");
                Brush amber = Vertical("#FFC268","#E78F36","#B95724");
                Brush box = Vertical("#C5784D","#A65735","#753F31");
                Brush glass = Vertical("#CEE2DD","#8FB4BC","#607F8F");
                Pen outline = Stroke("#384647",1.1), seam = Stroke("#9D572C",.80);
                // A short municipal truck with a salt hopper, snow cap and curved steel blade.
                Path(dc,frame,null,"M-32,-14 L22,-14 26,-9 25,-5 -29,-5 Z");
                Path(dc,box,outline,"M-32,-27 L-9,-27 -10,-15 -27,-14 -31,-18 Z");
                Path(dc,Ink("#EDF4F0"),null,"M-33,-26 Q-32,-29 -29,-29 Q-23,-32 -18,-29 Q-13,-31 -9,-28 L-8,-26 Z");
                for(int i=0;i<3;i++)
                    dc.DrawLine(Stroke("#DA9A6F",1.15),new Point(-28+i*7,-24),new Point(-26+i*7,-17));
                Path(dc,amber,outline,"M-11,-14 L-10,-29 Q-10,-32 -7,-32 L6,-32 Q9,-32 11,-29 L15,-21 23,-19 25,-16 25,-8 -12,-8 Z");
                Path(dc,glass,outline,"M-7,-28 L-1,-28 -1,-21 -7,-21 Z M1,-28 L7,-28 11,-21 1,-21 Z");
                Path(dc,Ink("#EAF1E4"),null,"M1,-28 L6,-28 2,-22 1,-22 Z");
                Path(dc,Ink("#FAF5DE"),null,"M-11,-31 Q-9,-34 -5,-33 Q0,-35 5,-33 L9,-32 9,-30 -10,-30 Z");
                dc.DrawLine(seam,new Point(-7,-20),new Point(-7,-12));
                dc.DrawLine(Stroke("#563F31",1.3),new Point(-5,-19),new Point(-2,-19));
                Path(dc,Ink("#674C3A"),null,"M15,-15 L24,-15 24,-12 16,-12 Z");
                dc.DrawRoundedRectangle(Ink("#FFF1AE"),null,new Rect(20,-18,5,2.8),.8,.8);
                dc.DrawRoundedRectangle(Ink("#D65C3D"),null,new Rect(-32,-17,2.8,3.5),.7,.7);
                Path(dc,Ink("#666E67"),null,"M-4,-34 L3,-34 3,-32 -4,-32 Z");
                dc.DrawRoundedRectangle(Ink("#FFC056"),Stroke("#975B2F",.60),new Rect(-2.6,-37.7,4.6,4.4),1.5,1.5);
                dc.DrawLine(Stroke("#55666A",2.3),new Point(19,-6),new Point(34,-7));
                dc.DrawLine(Stroke("#AC7749",1.7),new Point(21,-13),new Point(32,-6));
                Path(dc,Vertical("#DBEEEF","#8EAFBA","#47727F"),outline,
                    "M30,-18 Q31,-12 39,-5 L37,-2 Q30,-4 26,-12 L27,-18 Z");
                dc.DrawLine(Stroke("#D3DADC",1.4),new Point(30,-4.5),new Point(38,-2.5));
                dc.DrawLine(Stroke("#EDAC5D",1.5),new Point(27.3,-18),new Point(30.3,-18));
                foreach(double wx in new double[]{-20,14}) {
                    dc.DrawEllipse(rubber,Stroke("#1F292D",1),new Point(wx,-6.4),6.4,6.4);
                    dc.DrawEllipse(steel,Stroke("#41565E",.9),new Point(wx,-6.4),3.9,3.9);
                    dc.DrawEllipse(Ink("#D5DEE0"),null,new Point(wx,-6.4),1.25,1.25);
                }
            }

            private static Sprite[] MakeHubs()
            {
                var hubs = new Sprite[12];
                Pen glint = Stroke("#E2EAEB",.85);
                for (int i=0;i<hubs.Length;i++)
                {
                    double offset = i*Math.PI*2/(3*hubs.Length);
                    hubs[i] = new Sprite(delegate(DrawingContext dc) {
                        for(int j=0;j<3;j++) {
                            double a=offset+j*Math.PI*2/3;
                            dc.DrawLine(glint,new Point(1.6*Math.Cos(a),1.6*Math.Sin(a)),
                                new Point(3.1*Math.Cos(a),3.1*Math.Sin(a)));
                        }
                    });
                }
                return hubs;
            }
        }

        internal static void DrawSnowplough(DrawingContext dc,SnowScene scene)
        {
            WinterPlough p = scene.Plough;
            if (p == null) return;
            double scale=p.Scale;
            dc.PushTransform(new RotateTransform(p.Incline,p.X,p.Y));
            (p.Facing>0?PloughArtwork.Right:PloughArtwork.Left).Draw(dc,p.X,p.Y,scale);
            double phase=p.Facing*p.WheelTurn*3/(2*Math.PI);
            int frame=(int)((phase-Math.Floor(phase))*PloughArtwork.Hubs.Length)%PloughArtwork.Hubs.Length;
            Sprite hub=PloughArtwork.Hubs[frame];
            hub.Draw(dc,p.X-p.Facing*20*scale,p.Y-6.4*scale,scale);
            hub.Draw(dc,p.X+p.Facing*14*scale,p.Y-6.4*scale,scale);
            double glow=scale*(2.3+3.6*Math.Pow(.5+.5*Math.Cos(p.Time*7),3));
            dc.DrawEllipse(PloughArtwork.Beacon,null,new Point(p.X-.3*p.Facing*scale,p.Y-36*scale),glow,glow*.85);
            dc.Pop();
        }
    }
}
