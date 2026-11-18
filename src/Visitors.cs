using System;
using System.Collections.Generic;
using System.Globalization;

namespace Frostpane
{
    internal enum VisitorKind { Snowmen, Yeti, Santa, Train }
    internal enum VisitorSizeTarget { Snowplow, Yeti, Santa, Train, Snowmen }
    internal sealed class WinterVisitor
    {
        internal VisitorKind Kind;
        internal double X,Y,Age,Facing=1,Wait,TargetX,Dwell,Travel,Scale=1,Incline;
        internal bool Met;
        internal Snowman Friend;
        internal WinterTree Timber;
        internal YetiWalk Walk;
        internal int Chops;
        internal bool CarryingLog,Wild;
        internal GiftPayload Gift;
        internal string Caption;
    }
    internal sealed class WinterPresent { internal double X,Y,Vy; }
    internal sealed class FriendlyShot { internal double X,Y,Vx,Vy,Remaining,Radius=3.6;internal Snowman Target;internal FightPlayer Shooter; }

    internal sealed partial class SnowScene
    {
        internal readonly List<WinterVisitor> Visitors = new List<WinterVisitor>();
        internal int VisitorSpeed { get; set; }
        private readonly double[] visitorScales={1,1,1,1,1};
        private static readonly VisitorSizeTarget[] sizeTargets={VisitorSizeTarget.Snowmen,VisitorSizeTarget.Yeti,VisitorSizeTarget.Santa,VisitorSizeTarget.Train};
        private static readonly double[] trainWheels={-70,-47,-20,-2,15};
        internal void SetVisitorSize(VisitorSizeTarget target,int percent)
        {
            double scale=Limit(percent,50,250)/100.0;
            if(visitorScales[(int)target]==scale) return;
            visitorScales[(int)target]=scale;
            if(target==VisitorSizeTarget.Snowplow && Plough!=null) SizePlough();
            foreach(WinterVisitor v in Visitors) {
                if(sizeTargets[(int)v.Kind]!=target) continue;
                if(v.Kind==VisitorKind.Yeti) {
                    ResizeYetiFoot(v.Walk.Far,v.X,scale/v.Scale);
                    ResizeYetiFoot(v.Walk.Near,v.X,scale/v.Scale);
                }
                v.Scale=scale;
                if(v.Kind==VisitorKind.Train) GroundWheels(v.X,scale,trainWheels,4.4,out v.Y,out v.Incline);
            }
        }
        private double VisitorPace { get { return VisitorSpeed<=0 ? 1 : VisitorSpeed==1 ? 1.5 : 2.1; } }
        internal readonly List<FriendlyShot> FriendlyShots=new List<FriendlyShot>();
        internal WinterPresent DailyPresent;
        internal Func<string,bool> RedeemDailyGift;
        internal Action<string> GiftArrived;
        internal string FortuneLine="";
        internal double FortuneX,FortuneY,FortuneTime;
        private string presentDay="";
        private double nextToss=16;
        private readonly Queue<GiftPayload> arrivingGifts=new Queue<GiftPayload>();
        private WinterTree selectedGiftTree;
        private Snowman selectedGiftMan;

        internal bool SelectGiftAt(double x,double y)
        {
            selectedGiftMan=DirectSnowman(x,y);
            selectedGiftTree=selectedGiftMan==null?TreeAt(x,y):null;
            return selectedGiftMan!=null || selectedGiftTree!=null;
        }
        internal GiftType SelectedGiftType {
            get {
                if (selectedGiftTree!=null && Trees.Contains(selectedGiftTree)) return GiftType.Tree;
                if (selectedGiftMan!=null && Snowmen.Contains(selectedGiftMan)) return GiftType.Snowman;
                return GiftType.Note;
            }
        }
        internal GiftPayload CaptureTreeGift(WinterTree tree,string note)
        {
            if (tree==null || !Trees.Contains(tree)) throw new InvalidOperationException("Place a tree, then select it to send a copy.");
            return new GiftPayload {Kind=GiftType.Tree,Note=note,Style=tree.Style, Size=tree.Size,Dress=ExportTreeDress(tree)};
        }
        internal GiftPayload CaptureSnowmanGift(Snowman man,string note)
        {
            if (man==null || !Snowmen.Contains(man)) throw new InvalidOperationException("Stack three balls, then select your snowman to send a copy.");
            return new GiftPayload {Kind=GiftType.Snowman,Note=note,Style=man.Style,Size=man.BaseRadius,
                Mid=man.MidRadius,Head=man.HeadRadius,Facing=man.Facing};
        }
        internal GiftPayload CaptureGift(GiftType kind,string note)
        {
            if (kind==GiftType.Note) return new GiftPayload {Kind=kind,Note=note};
            if (kind==GiftType.Tree) return CaptureTreeGift(SelectedGiftType==GiftType.Tree?selectedGiftTree:
                Trees.Count>0?Trees[Trees.Count-1]:null,note);
            return CaptureSnowmanGift(SelectedGiftType==GiftType.Snowman?selectedGiftMan:
                Snowmen.Count>0?Snowmen[Snowmen.Count-1]:null,note);
        }
        internal void SendVisitors(VisitorKind kind)
        {
            if (floor==null || Visitors.Count>=12) return;
            if (kind==VisitorKind.Train) { DeliverGift(new GiftPayload {Kind=GiftType.Note,Note="Hello from the North Pole!",Sender="The elves"});return; }
            if (kind==VisitorKind.Snowmen && Snowmen.Count>=70) return;
            double scale=visitorScales[(int)sizeTargets[(int)kind]];
            var v=new WinterVisitor { Kind=kind,Scale=scale,X=-23*scale,TargetX=Between(.22,.78)*Math.Min(width,1100) };
            if(kind==VisitorKind.Yeti) {EnterYeti(v,nextYetiEntry);nextYetiEntry=-nextYetiEntry;}
            if (kind==VisitorKind.Snowmen) { v.TargetX=Between(width*.22,width*.78);v.X=v.TargetX;v.Y=-2; }
            if (kind==VisitorKind.Santa) { v.X=-109*scale;v.Y=height*.2; }
            Visitors.Add(v);
        }
        internal void DeliverGift(GiftPayload gift)
        {
            if (gift==null) return;
            if (arrivingGifts.Count>=64) throw new InvalidOperationException("The gift train is busy. Please try again shortly.");
            arrivingGifts.Enqueue(gift);
        }
        internal bool IsGiftInTransit(string id)
        {
            if(string.IsNullOrEmpty(id)) return false;
            foreach(var gift in arrivingGifts) if(gift.Id==id) return true;
            foreach(var visitor in Visitors)
                if(visitor.Kind==VisitorKind.Train && !visitor.Met && visitor.Gift.Id==id) return true;
            return false;
        }
        private double VisitorGround(double x) { return floor.Y-floor.PaintedHeightAt(Limit(x,0,width)); }
        // Tilt the chassis with the terrain. On a hump the highest supporting wheel
        // carries the vehicle. Offsets mirror with travel direction and scale with its art.
        private void GroundWheels(double x,double signedScale,double[] wheels,double wheelRadius,out double y,out double incline)
        {
            double left=wheels[0]*signedScale,right=wheels[wheels.Length-1]*signedScale;
            double slope=(VisitorGround(x+right)-VisitorGround(x+left))/(right-left);
            double angle=Math.Atan(Limit(slope,-.36,.36)),sin=Math.Sin(angle),cos=Math.Cos(angle);
            double radius=wheelRadius*Math.Abs(signedScale);
            y=double.MaxValue;
            foreach(double wheel in wheels) {
                double dx=wheel*signedScale;
                y=Math.Min(y,VisitorGround(x+cos*dx+sin*radius)-sin*dx-radius*(1-cos));
            }
            incline=angle*180/Math.PI;
        }
        internal bool OpenDailyPresent(double x,double y,out string text)
        {
            text="";
            if(DailyPresent==null || Math.Abs(x-DailyPresent.X)>13 || y<DailyPresent.Y-26 || y>DailyPresent.Y+1)return false;
            string day=DateTime.Now.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture);
            string[] lines={
                "A window ledge is a small mountain if you are a snowflake.",
                "Leave a little room on the hill for a friend.",
                "Even the longest sleigh ride starts with one soft crunch.",
                "A crooked snowman still catches the morning light.",
                "The quietest snow can carry the brightest footsteps.",
                "Every snowbank remembers a different wind.",
                "Cold fingers make wonderfully warm gifts."
            };
            bool first=RedeemDailyGift==null||RedeemDailyGift(day);
            text=first?lines[DateTime.Now.DayOfYear%lines.Length]:"Santa already left you a note today.";
            FortuneX=Limit(DailyPresent.X,Math.Min(width/2,160),Math.Max(width/2,width-160));
            FortuneY=Math.Max(40,DailyPresent.Y-32);FortuneLine=text;FortuneTime=9;
            PowderBurst(DailyPresent.X,DailyPresent.Y-12,17,0,.7);DailyPresent=null;return true;
        }
        private void WinterGames(double dt)
        {
            StepFight(dt);
            if(FortuneTime>0)FortuneTime-=dt;
            if(DailyPresent!=null) {
                DailyPresent.Vy=Math.Min(150,DailyPresent.Vy+125*dt);
                DailyPresent.Y=Math.Min(VisitorGround(DailyPresent.X),DailyPresent.Y+DailyPresent.Vy*dt);
            }
            if(Snowmen.Count<2)nextToss=Math.Min(nextToss,13);
            else if (Fight==null && (nextToss-=dt)<=0) {
                nextToss=Between(19,36);
                var from=Snowmen[random.Next(Snowmen.Count)];Snowman to=null;double nearest=double.MaxValue;
                foreach(Snowman man in Snowmen) {
                    if(man==from||man.Held)continue;
                    double dx=man.X-from.X,dy=man.Y-from.Y,dist=dx*dx+dy*dy;
                    if(dist<nearest){nearest=dist;to=man;}
                }
                if(!from.Held && to!=null) {
                    double tx=to.X,ty=to.Y-to.Height*.58,x=from.X,y=from.Y-from.Height*.58;
                    double duration=Limit(.62+Math.Abs(tx-x)/600,.65,2.0);
                    from.Facing=tx>x?1:-1;
                    FriendlyShots.Add(new FriendlyShot{X=x,Y=y,Vx=(tx-x)/duration,Vy=(ty-y)/duration-130*duration,Remaining=duration,Target=to});
                }
            }
            for(int i=FriendlyShots.Count-1;i>=0;i--) {
                var b=FriendlyShots[i];
                if(b.Shooter!=null){if(AdvanceBattleShot(b,dt))FriendlyShots.RemoveAt(i);continue;}
                b.Remaining-=dt;b.X+=b.Vx*dt;b.Y+=b.Vy*dt+130*dt*dt;b.Vy+=260*dt;
                if(b.Remaining<=0) {
                    if(b.Target!=null && !b.Target.Held && Math.Abs(b.Target.X-b.X)<b.Target.BaseRadius+10) b.Target.Facing=b.Vx>0?-1:1;
                    PowderBurst(b.X,b.Y,13,b.Vx*.2,.65);FriendlyShots.RemoveAt(i);
                }
            }
        }
        private void Unload(WinterVisitor v)
        {
            var g=v.Gift;double x=Limit(v.X-59*v.Scale*Math.Cos(v.Incline*Math.PI/180),20,Math.Max(20,width-20));
            if (g.Kind==GiftType.Tree && Trees.Count<40) {
                var tree=new WinterTree { X=x,Y=VisitorGround(x),Size=g.Size,Style=g.Style,Support=floor,Anchor=x/width };
                Trees.Add(tree);ImportTreeDress(tree,g.Dress);
            } else if(g.Kind==GiftType.Snowman && Snowmen.Count<70) {
                Snowmen.Add(new Snowman { X=x,Y=VisitorGround(x),BaseRadius=g.Size,MidRadius=g.Mid,HeadRadius=g.Head,Facing=g.Facing,Style=g.Style });
            }
            PowderBurst(x,VisitorGround(x)-4,14,0,.8);
        }
        private void UpdateVisitors(double dt)
        {
            WinterGames(dt);
            double pacedDt=dt*VisitorPace;
            bool stationBusy=false;
            for(int i=Visitors.Count-1;i>=0;i--) {
                WinterVisitor v=Visitors[i]; v.Age+=dt;
                if(v.Kind==VisitorKind.Santa) {
                    v.X+=82*pacedDt;
                    v.Y=Math.Max(Math.Min(height*.55,46*v.Scale),height*.2+Math.Sin(v.Age*1.15)*Math.Min(20,height*.07));
                    if(!v.Met && v.X>=v.TargetX) {
                        v.Met=true;string day=DateTime.Now.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture);
                        if(day!=presentDay && DailyPresent==null){DailyPresent=new WinterPresent{X=v.X,Y=v.Y};presentDay=day;}
                    }
                    if (v.X>width+95*v.Scale) Visitors.RemoveAt(i);
                } else if(v.Kind==VisitorKind.Snowmen) {
                    v.Y+=48*pacedDt;v.X=v.TargetX+Math.Sin(v.Age*1.05)*9;
                    if (v.Y>=VisitorGround(v.X)) {
                        if (Snowmen.Count<70) Snowmen.Add(new Snowman { X=v.X,Y=VisitorGround(v.X),BaseRadius=19*v.Scale,MidRadius=14*v.Scale,HeadRadius=10*v.Scale,
                            Facing=1,Style=1 });
                        PowderBurst(v.X,v.Y,20,0,.9); Visitors.RemoveAt(i);
                    }
                } else if(v.Kind==VisitorKind.Yeti) {
                    if (StepYeti(v,dt,pacedDt)) Visitors.RemoveAt(i);
                } else {
                    double previousX=v.X;
                    if (!v.Met) {
                        v.X=Math.Min(v.TargetX,v.X+58*pacedDt);
                        if (v.X>=v.TargetX) {
                            v.Met=true;
                            Unload(v);
                            if(GiftArrived!=null) GiftArrived(v.Gift.Id);
                        }
                    } else if((v.Wait+=dt)>v.Dwell) v.X+=64*pacedDt;
                    v.Travel+=v.X-previousX;
                    GroundWheels(v.X,v.Scale,trainWheels,4.4,out v.Y,out v.Incline);
                    if(v.X>width+90*v.Scale) Visitors.RemoveAt(i);
                    else if(v.X<v.TargetX+160*v.Scale) stationBusy=true;
                }
            }
            if(!stationBusy && arrivingGifts.Count>0 && Visitors.Count<12) {
                var gift=arrivingGifts.Dequeue();
                string caption=string.IsNullOrEmpty(gift.Note) ? "For you, from "+gift.Sender : gift.Note;
                double dwell=Math.Max(11,7+caption.Length/16.0);
                double scale=visitorScales[(int)VisitorSizeTarget.Train];
                Visitors.Add(new WinterVisitor {Kind=VisitorKind.Train,Scale=scale,X=-27*scale,Y=VisitorGround(0),
                    TargetX=Math.Min(width*.54,640),Gift=gift,Dwell=dwell,Caption=caption});
            }
        }
        private void ClearVisitors()
        {
            Fight=null;
            if(DailyPresent!=null)presentDay="";
            Visitors.Clear();arrivingGifts.Clear();FriendlyShots.Clear();DailyPresent=null;FortuneTime=0;selectedGiftTree=null;selectedGiftMan=null;
        }
    }
}
