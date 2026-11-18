using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;

namespace Frostpane
{
    internal sealed class WinterPlough
    {
        internal int Facing;
        internal double X, Y, Scale, Incline, Time, WheelTurn, Powder, LastSpray, Carry;
    }

    internal sealed partial class SnowScene
    {
        internal WinterPlough Plough;
        private int nextPloughSide = 1;
        private double PloughScale {get{return Limit(height/420,.76,1.22)*visitorScales[(int)VisitorSizeTarget.Snowplow];}}
        private void SizePlough()
        {
            Plough.Scale=PloughScale;
            GroundPlough(Plough,0);
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

        private double TireBed(double x,double scale)
        {
            double span=4*scale;
            double loose=(floor.PaintedHeightAt(x-span)+2*floor.PaintedHeightAt(x)+floor.PaintedHeightAt(x+span))*.25;
            // The tires compact loose snow rather than climbing every raw snow sample.
            return floor.Y-Math.Min(5*scale,loose*.30);
        }

        private void GroundPlough(WinterPlough p,double dt)
        {
            double rear=-20*p.Facing*p.Scale,front=14*p.Facing*p.Scale,r=6.4*p.Scale;
            double grade=(TireBed(p.X+front,p.Scale)-TireBed(p.X+rear,p.Scale))/(front-rear);
            double target=Limit(Math.Atan(grade)*180/Math.PI,-8,8);
            p.Incline+=Limit(target-p.Incline,-22*dt,22*dt);
            double angle=p.Incline*Math.PI/180,c=Math.Cos(angle),s=Math.Sin(angle);
            p.Y=Math.Min(TireBed(p.X+c*rear+s*r,p.Scale)-s*rear,
                         TireBed(p.X+c*front+s*r,p.Scale)-s*front)-r*(1-c);
        }

        private static Point TruckPoint(WinterPlough p,double x,double y)
        {
            var offset=TurnOffset(x*p.Facing*p.Scale,y*p.Scale,p.Incline);
            return new Point(p.X+offset.X,p.Y+offset.Y);
        }

        partial void StepSnowplough(double dt)
        {
            WinterPlough p=Plough;
            if(p==null || floor==null || dt<=0) return;
            Point oldLip=TruckPoint(p,37,0), oldTop=TruckPoint(p,30,-18);
            Point oldHeel=TruckPoint(p,-25,0);
            double travel=52*VisitorPace*dt;
            p.Time+=dt;p.X+=p.Facing*travel;p.WheelTurn+=travel/(6.4*p.Scale);
            GroundPlough(p,dt);
            Point lip=TruckPoint(p,37,0),top=TruckPoint(p,30,-18),heel=TruckPoint(p,-25,0);
            double cell=floor.Width/(floor.Heights.Length-1);
            double farGround=VisitorGround(lip.X+p.Facing*cell);
            // Grade every cell between the cutting edge and the rear tire. A resized
            // truck can span many samples without its blade crossing a new one.
            int first=Math.Max(0,(int)Math.Ceiling((Math.Min(Math.Min(oldHeel.X,heel.X),Math.Min(oldLip.X,lip.X))-floor.X)/cell));
            int last=Math.Min(floor.Heights.Length-1,(int)Math.Floor((Math.Max(Math.Max(oldHeel.X,heel.X),Math.Max(oldLip.X,lip.X))-floor.X)/cell));
            double removed=0;
            for(int i=first;i<=last;i++) {
                double x=floor.X+i*cell;
                double t=Limit((x-heel.X)/(lip.X-heel.X),0,1);
                double track=heel.Y+(lip.Y-heel.Y)*t;
                double left=Math.Max(0,floor.Y-track);
                double cut=Math.Max(0,floor.Heights[i]-left);
                floor.Heights[i]-=cut;removed+=cut;
            }
            p.Carry+=removed*.94; p.Powder+=removed*.20;
            bool deposited=SpreadPloughedSnow(p,lip,cell);
            if(deposited || removed>.00001)floor.Revision++;
            PushBladeLoad(p,oldTop,oldLip,top,lip,farGround,travel/dt);
            if(p.Powder>=1 && p.Time-p.LastSpray>=.10 && lip.X>=0 && lip.X<=width) {
                int amount=(int)Math.Min(9,p.Powder);
                PowderBurst(lip.X,VisitorGround(lip.X+p.Facing*3)-1,amount,p.Facing*65,.65);
                p.Powder=0;p.LastSpray=p.Time;
            }
            double margin=41*p.Scale;
            if((p.X<=-margin && p.Facing<0) || (p.X>=width+margin && p.Facing>0)) Plough=null;
        }

        private struct PloughContact
        {
            internal object Item;
            internal double Near,Far,High,Low,Advance;
            internal bool InQueue;
        }
        private readonly List<PloughContact> bladeContacts=new List<PloughContact>();
        private static readonly Comparison<PloughContact> bladeOrder=delegate(PloughContact a,PloughContact b) {
            int order=a.Near.CompareTo(b.Near);
            return order!=0?order:a.Far.CompareTo(b.Far);
        };

        private void AddContact(object item,double left,double right,double high,double low,int facing)
        {
            bladeContacts.Add(new PloughContact {Item=item,Near=facing>0?left:-right,Far=facing>0?right:-left,High=high,Low=low});
        }
        private void ContactCircle(object item,double x,double y,double radius,double top,double bottom,int facing)
        {
            double dy=Limit(y,top,bottom)-y;
            if(Math.Abs(dy)>radius)return;
            double half=Math.Sqrt(Math.Max(0,radius*radius-dy*dy));
            AddContact(item,x-half,x+half,Math.Max(top,y-radius),Math.Min(bottom,y+radius),facing);
        }
        private void ContactArt(object item,DecorationKind kind,double x,double y,double angle,double scale,double top,double bottom,int facing)
        {
            if(y+110*scale<top || y-110*scale>bottom)return;
            double left,right,high,low;
            if(DecorationFootprint.For(item,kind,angle).Slice((top-y)/scale,(bottom-y)/scale,out left,out right,out high,out low))
                AddContact(item,x+left*scale,x+right*scale,y+high*scale,y+low*scale,facing);
        }
        private static double BladeReach(Point a,Point b,double y0,double y1,int facing)
        {
            double dy=b.Y-a.Y;
            if(Math.Max(a.Y,b.Y)<y0 || Math.Min(a.Y,b.Y)>y1)return double.NegativeInfinity;
            if(Math.Abs(dy)<.0001)return Math.Max(a.X*facing,b.X*facing);
            double t0=Limit((y0-a.Y)/dy,0,1),t1=Limit((y1-a.Y)/dy,0,1);
            return Math.Max(facing*(a.X+t0*(b.X-a.X)),facing*(a.X+t1*(b.X-a.X)));
        }
        private bool OnWindow(double x,double foot)
        {
            double surface;
            SnowBank bank=FindSupport(x,foot,foot+1.5,2,out surface);
            return bank!=null && !bank.IsFloor;
        }
        private void PushBladeLoad(WinterPlough p,Point oldTop,Point oldLip,Point top,Point lip,double snowTop,double speed)
        {
            if(Balls.Count+Snowmen.Count+Sleds.Count+Trees.Count+Decorations.Count+Lights.Count==0 && DailyPresent==null)return;
            int f=p.Facing;
            // One strip spans the blade's previous and current poses. For objects
            // resting on snow, include the snow being pushed immediately in front.
            double high=Math.Min(oldTop.Y,top.Y)-p.Scale,low=Math.Max(oldLip.Y,lip.Y)+p.Scale;
            double loadTop=Math.Min(high,snowTop);
            double back=Math.Min(Math.Min(oldTop.X*f,top.X*f),Math.Min(oldLip.X*f,lip.X*f))-4*p.Scale;
            Point bend=TruckPoint(p,32.75,-11.25),nose=TruckPoint(p,39,-3);
            bladeContacts.Clear();
            foreach(SnowBall b in Balls) {
                if(b.Held || b.InFlight || b.Below!=null || OnWindow(b.X,b.Y+b.Radius))continue;
                double reach=Math.Abs(VisitorGround(b.X)-b.Y-b.Radius)<6?loadTop:high;
                ContactCircle(b,b.X,b.Y,b.Radius,reach,low,f);
            }
            foreach(Snowman m in Snowmen) {
                if(m.Held || OnWindow(m.X,m.Y))continue;
                double reach=Math.Abs(VisitorGround(m.X)-m.Y)<6?loadTop:high;
                ContactCircle(m,m.X,m.Y-m.BaseRadius,m.BaseRadius,reach,low,f);
            }
            foreach(WinterTree t in Trees) {
                if(t.Hidden || t==draggedTree || (t.Support!=null && !t.Support.IsFloor))continue;
                ContactArt(t,DecorationKind.Tree,t.X,t.Y,t.Angle,t.DisplaySize/96,t.Support==floor?loadTop:high,low,f);
            }
            foreach(PlacedDecoration d in Decorations) {
                if(d.Hidden || d.Tree!=null || d==draggedDecoration || (d.Mount.Support!=null && !d.Mount.Support.IsFloor))continue;
                ContactArt(d,d.Kind,d.X,d.Y,d.Angle,d.Scale,d.Mount.Support==floor?loadTop:high,low,f);
            }
            foreach(WinterSled s in Sleds) {
                if(s==draggedSled || (s.Support!=null && !s.Support.IsFloor))continue;
                double left,right;
                double upper=s.Support==floor?loadTop:high;
                if(s.BladeSlice(upper,low,out left,out right))AddContact(s,left,right,upper,Math.Min(low,s.DisplayY+2),f);
            }
            if(DailyPresent!=null && DailyPresent.Y>=(Math.Abs(VisitorGround(DailyPresent.X)-DailyPresent.Y)<6?loadTop:high) && DailyPresent.Y-25<=low)
                AddContact(DailyPresent,DailyPresent.X-12,DailyPresent.X+12,DailyPresent.Y-25,DailyPresent.Y,f);
            foreach(LightString l in Lights) {
                if(l.Hidden || l==draggedLights || (l.Left.Support!=null && !l.Left.Support.IsFloor) ||
                    (l.Right.Support!=null && !l.Right.Support.IsFloor))continue;
                double left=double.PositiveInfinity,right=double.NegativeInfinity,minY=double.PositiveInfinity,maxY=double.NegativeInfinity;
                int samples=Math.Max(8,Math.Min(200,(int)Math.Ceiling((l.Length+2*l.Sag)/6)));
                for(int i=0;i<=samples;i++) {
                    double t=(double)i/samples,y=l.CurveY(t);
                    if(y+8*l.BulbScale<high || y-1>low)continue;
                    double x=l.X1+(l.X2-l.X1)*t;
                    left=Math.Min(left,x-2*l.BulbScale);right=Math.Max(right,x+2*l.BulbScale);
                    minY=Math.Min(minY,y-1);maxY=Math.Max(maxY,y+8*l.BulbScale);
                }
                if(left<=right)AddContact(l,left,right,minY,maxY,f);
            }
            bladeContacts.Sort(bladeOrder);
            double leader=double.NegativeInfinity;
            for(int i=0;i<bladeContacts.Count;i++) {
                PloughContact c=bladeContacts[i];
                if(c.Far<back)continue;
                double lo=c.High-p.Scale*.5,hi=c.Low+p.Scale*.5;
                double edge=Math.Max(BladeReach(top,bend,lo,hi,f),Math.Max(BladeReach(bend,nose,lo,hi,f),BladeReach(nose,lip,lo,hi,f)));
                if(c.Low<high && c.Low>=loadTop)edge=lip.X*f;
                double contact=Math.Max(leader,edge);
                if(c.Near>contact)continue;
                c.InQueue=true;c.Advance=Math.Max(0,contact-c.Near);
                leader=c.Far+c.Advance+.6;bladeContacts[i]=c;
            }
            // Once the front object reaches the display edge, park its followers in
            // order. A plow pass never deletes a decoration or packs every pivot onto one pixel.
            double boundary=f>0?width:0;
            for(int i=bladeContacts.Count-1;i>=0;i--) {
                PloughContact c=bladeContacts[i];if(!c.InQueue)continue;
                double shift=Math.Max(0,Math.Min(c.Advance,boundary-c.Far));
                boundary=Math.Min(boundary,c.Near+shift);
                if(shift>0)MoveWithBlade(c.Item,shift*f,speed*f);
            }
            foreach(SnowBall b in Balls)if(b.Below!=null) {
                b.X=b.Below.X;b.Y=b.Below.Y-.78*(b.Radius+b.Below.Radius);
            }
            foreach(PlacedDecoration d in Decorations)if(d.Tree!=null && d!=draggedDecoration) SetTreePosition(d);
        }

        private void MoveWithBlade(object item,double dx,double velocity)
        {
            var b=item as SnowBall;
            if(b!=null) {
                b.X=Limit(b.X+dx,b.Radius,Math.Max(b.Radius,width-b.Radius));
                b.Rotation+=dx/Math.Max(1,b.Radius);b.Y=Math.Min(b.Y,VisitorGround(b.X)-b.Radius);
                return;
            }
            var m=item as Snowman;
            if(m!=null) {m.X=Limit(m.X+dx,m.BaseRadius,Math.Max(m.BaseRadius,width-m.BaseRadius));m.Y=Math.Min(m.Y,VisitorGround(m.X));return;}
            var sled=item as WinterSled;
            if(sled!=null) {
                sled.X=Limit(sled.X+dx,Math.Min(20,width*.5),Math.Max(width*.5,width-20));
                if(sled.Support==floor)sled.Y=VisitorGround(sled.X);
                sled.Vx=velocity;return;
            }
            var tree=item as WinterTree;
            if(tree!=null) {
                tree.X=Limit(tree.X+dx,0,width);
                if(tree.Support==floor){tree.Anchor=tree.X/width;RestTree(tree,floor);}
                return;
            }
            var d=item as PlacedDecoration;
            if(d!=null) {
                d.X=Limit(d.X+dx,0,width);
                if(d.Mount.Support==floor){d.Mount.Anchor=d.X/width;RestDecoration(d,floor);}
                return;
            }
            var l=item as LightString;
            if(l!=null) {
                dx=Limit(dx,-Math.Min(l.X1,l.X2),width-Math.Max(l.X1,l.X2));
                l.X1+=dx;l.X2+=dx;
                if(l.Left.Support==floor)l.Left.Anchor=l.X1/width;
                if(l.Right.Support==floor)l.Right.Anchor=l.X2/width;
                return;
            }
            var gift=(WinterPresent)item;
            gift.X=Limit(gift.X+dx,12,Math.Max(12,width-12));gift.Y=Math.Min(gift.Y,VisitorGround(gift.X));
        }

        private bool SpreadPloughedSnow(WinterPlough p,Point lip,double cell)
        {
            // Start shallow at the lip and taper back to the unworked blanket.
            // A full bank carries its excess forward until there is room or the plow exits.
            int first=p.Facing>0 ? (int)Math.Floor((lip.X-floor.X)/cell)+1 : (int)Math.Ceiling((lip.X-floor.X)/cell)-1;
            bool changed=false;
            for(int j=first;j>=0 && j<floor.Heights.Length;j+=p.Facing) {
                double distance=(j*cell+floor.X-lip.X)*p.Facing;
                double cap=Math.Max(0,floor.Y-lip.Y+.43*distance);
                if(floor.Heights[j]<=cap)break;
                // The face of an existing solid bank sloughs into the blade. Limit
                // only the connected rise, leaving separate hills ahead untouched.
                p.Carry+=floor.Heights[j]-cap;floor.Heights[j]=cap;changed=true;
            }
            if(p.Carry<.001)return changed;
            double reach=Math.Max(cell*9,76*p.Scale), load=p.Carry;
            int count=(int)Math.Ceiling(reach/cell);
            for(int n=0;n<count;n++) {
                int index=first+n*p.Facing;
                if(index<0 || index>=floor.Heights.Length)continue;
                double distance=(index*cell+floor.X-lip.X)*p.Facing;
                double wedge=Math.Max(0,Math.Min(distance,reach-distance))*.43;
                int a=Math.Max(0,index-1),b=Math.Min(floor.Heights.Length-1,index+1);
                double cap=Math.Min(floor.Maximum(index),Math.Min(floor.Y-lip.Y+wedge,Math.Min(floor.Heights[a],floor.Heights[b])+.43*cell));
                double lift=Math.Min(Math.Max(0,cap-floor.Heights[index]),load*2*Math.Sin(Math.PI*Limit(distance/reach,0,1))/(count+1));
                lift=Math.Min(lift,p.Carry);
                if(lift<=.00001)continue;
                floor.Heights[index]+=lift;p.Carry-=lift;changed=true;
            }
            return changed;
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
                    "M30,-18 Q31,-12 39,-3 L37,0 Q30,-3 26,-12 L27,-18 Z");
                dc.DrawLine(Stroke("#D3DADC",1.4),new Point(30,-3.5),new Point(37.5,-.6));
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
