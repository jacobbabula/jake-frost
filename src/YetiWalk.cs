using System;

namespace Frostpane
{
    internal sealed class YetiFoot
    {
        internal double X,Y,Start,Landing,Progress=1,Clearance,Ground,Tilt;
        internal bool Planted {get{return Progress>=1;}}
    }

    internal sealed class YetiWalk
    {
        internal readonly YetiFoot Far=new YetiFoot(),Near=new YetiFoot();
        internal int Entry,Approach;
        internal double Velocity,Weight,Bob,Arm,SpeedRatio,Look;
        internal object Target;
        internal YetiFoot Swing;
    }

    internal sealed partial class SnowScene
    {
        private int nextYetiEntry=1;
        private const double YetiPace=42;

        internal void SendBlizzardYeti(int direction)
        {
            if(floor==null || Visitors.Count>=12)return;
            var runner=new WinterVisitor {Kind=VisitorKind.Yeti,Wild=true,Scale=visitorScales[(int)VisitorSizeTarget.Yeti]};
            EnterYeti(runner,direction<0?-1:1);
            Visitors.Add(runner);
        }

        private void EnterYeti(WinterVisitor v,int direction)
        {
            var walk=new YetiWalk { Entry=direction,Approach=direction };
            v.Walk=walk;v.Facing=walk.Look=walk.Entry;v.X=walk.Entry>0?-35*v.Scale:width+35*v.Scale;
            v.Y=VisitorGround(v.X);v.Dwell=5;
            walk.Far.X=v.X-4*v.Scale*v.Facing;walk.Near.X=v.X+4*v.Scale*v.Facing;
            walk.Far.Ground=walk.Far.Y=VisitorGround(walk.Far.X);
            walk.Near.Ground=walk.Near.Y=VisitorGround(walk.Near.X);
        }

        private static void ResizeYetiFoot(YetiFoot foot,double center,double factor)
        {
            foot.X=center+(foot.X-center)*factor;
            foot.Start=center+(foot.Start-center)*factor;
            foot.Landing=center+(foot.Landing-center)*factor;
            foot.Clearance*=factor;
        }

        private static double Towards(double value,double goal,double step)
        {
            return value+Limit(goal-value,-step,step);
        }

        private double YetiApproach(WinterVisitor v,object target,double x,double reach)
        {
            var w=v.Walk;
            if(w.Target!=target) {
                w.Target=target;
                w.Approach=x<reach ? -1 : x>width-reach ? 1 : x<v.X ? -1 : 1;
            }
            return x-w.Approach*reach;
        }

        private bool WalkYeti(WinterVisitor v,double destination,double pacedDt,double dt)
        {
            var w=v.Walk;
            double dx=destination-v.X;
            // Brake in time to meet the trunk or friend's outline without reversing around it.
            double topSpeed=v.Wild ? 92*Math.Sqrt(v.Scale) : YetiPace;
            double goal=Limit(3.15*dx,-topSpeed,topSpeed);
            w.Velocity=Towards(w.Velocity,goal,(v.Wild?260:124)*pacedDt);
            double travel=w.Velocity*pacedDt;
            bool arrived=Math.Abs(dx)<.1 || (dx*travel>0 && Math.Abs(travel)>=Math.Abs(dx));
            if(arrived){travel=dx;w.Velocity=0;}
            if(Math.Abs(travel)>.015)v.Facing=Math.Sign(travel);
            v.X+=travel;v.Travel+=Math.Abs(travel);
            PoseYeti(v,travel,destination,dt);
            return arrived;
        }

        private double YetiSlope(double x,double scale)
        {
            double span=4*scale;
            return Limit(Math.Atan2(VisitorGround(x+span)-VisitorGround(x-span),2*span)*180/Math.PI,-36,36);
        }

        private void PoseYeti(WinterVisitor v,double travel,double destination,double dt)
        {
            var w=v.Walk;
            double scale=v.Scale,facing=v.Facing;
            w.Look=Towards(w.Look,facing,dt*8);
            double strideScale=scale*(v.Wild?1.36:1);
            bool moving=Math.Abs(travel)>.0001;
            if(w.Swing==null) {
                // Take off with the trailing foot. The other sole remains fixed in world space.
                YetiFoot foot=(w.Far.X-w.Near.X)*facing<0 ? w.Far : w.Near;
                double landing=foot.X;
                if(moving && (v.X-foot.X)*facing>=7.1*strideScale) {
                    landing=v.X+facing*18.6*strideScale;
                    if((landing-destination)*facing>4*scale)landing=destination+facing*4*scale;
                } else if(!moving) {
                    double farRest=v.X-4.2*scale*facing,nearRest=v.X+4.2*scale*facing;
                    foot=Math.Abs(w.Far.X-farRest)>Math.Abs(w.Near.X-nearRest) ? w.Far : w.Near;
                    landing=foot==w.Far ? farRest : nearRest;
                }
                if(Math.Abs(landing-foot.X)>.8*scale) {
                    w.Swing=foot;foot.Start=foot.X;foot.Landing=landing;foot.Progress=0;
                }
            }
            YetiFoot swing=w.Swing;
            double lift=0;
            if(swing!=null) {
                // Distance sets the cadence at all visitor sizes. Finish the last swing
                // on approach even after the torso has already come to rest.
                double advance=Math.Abs(travel)/(11.4*strideScale);
                if(Math.Abs(w.Velocity)<12)advance=Math.Max(advance,dt*3.9);
                swing.Progress=Math.Min(1,swing.Progress+advance);
                double u=swing.Progress,ease=u*u*(3-2*u);
                swing.X=swing.Start+(swing.Landing-swing.Start)*ease;
                double arch=4*u*(1-u);
                lift=arch*arch*Math.Min((v.Wild?8.2:5.9)*scale,Math.Abs(swing.Landing-swing.Start)*.32);
                swing.Clearance=lift;
                if(u>=1) {
                    swing.X=swing.Landing;swing.Clearance=0;w.Swing=null;
                    if(v.Wild && Math.Abs(w.Velocity)>44 && swing.X>=0 && swing.X<=width)
                        PowderBurst(swing.X,VisitorGround(swing.X)-1,3,-w.Velocity*.55,.44);
                }
            }
            w.Far.Ground=VisitorGround(w.Far.X);w.Near.Ground=VisitorGround(w.Near.X);
            w.Far.Y=w.Far.Ground-w.Far.Clearance;w.Near.Y=w.Near.Ground-w.Near.Clearance;
            w.Far.Tilt=YetiSlope(w.Far.X,scale);w.Near.Tilt=YetiSlope(w.Near.X,scale);
            double shift=swing==null ? 0 : (swing==w.Far ? 1 : -1)*Math.Min(1,lift/(4*scale));
            w.Weight=Towards(w.Weight,shift,dt*9);
            double weight=.5+.32*w.Weight;
            v.Y=w.Far.Ground*(1-weight)+w.Near.Ground*weight;
            w.Bob=Towards(w.Bob,Math.Min(1,lift/(4*scale))*(v.Wild?2.9:1.5),dt*(v.Wild?28:14));
            w.SpeedRatio=Towards(w.SpeedRatio,Math.Min(1,Math.Abs(w.Velocity)/YetiPace),dt*5);
            // Pendulum follows the opposite leg. It slows naturally as both feet settle.
            double stagger=(w.Far.X-w.Near.X)*facing/scale;
            w.Arm=Towards(w.Arm,Limit(-stagger*1.55,v.Wild?-36:-24,v.Wild?36:24)*w.SpeedRatio,dt*(v.Wild?310:165));
        }
    }
}
