using System;
using System.Collections.Generic;

namespace Frostpane
{
    internal sealed class FightPlayer
    {
        internal Snowman Man;
        internal double X,Y,Home,Entry,Face=1,Scale=1,Stride,Windup,Follow,Duck,Wave;
        internal bool Red;
    }
    internal sealed class SnowballFight
    {
        internal readonly FightPlayer[] Players={new FightPlayer {Red=true},new FightPlayer()};
        internal double Age,End;
        internal int Throws;
        internal bool Snowmen;
    }
    internal sealed partial class SnowScene
    {
        internal SnowballFight Fight;
        private static readonly double[] throwsAt={3.3,5.65,7.45,9.8,11.55,13.5};
        private static double Ease(double x) { x=Limit(x,0,1);return x*x*(3-2*x); }
        internal bool StartFight(bool useSnowmen) {
            if(floor==null) return false;
            Snowman first=null,second=null;
            if(useSnowmen) {
                foreach(var man in Snowmen) if(!man.Held && (first==null || man==selectedGiftMan)) first=man;
                if(first==null) return false;
                double best=double.MaxValue;
                foreach(var man in Snowmen) if(!man.Held && man!=first) {
                    double d=Math.Abs(man.X-first.X)+Math.Abs(man.Y-first.Y);
                    if(d<best) {best=d;second=man;}
                }
            }
            double center=width*.50;
            var fight=new SnowballFight {Snowmen=useSnowmen,End=18};
            double span=Math.Min(width*.22,145);
            if(first!=null) center=Limit(first.X+(first.X>width/2?-span:span),span+5,Math.Max(span+5,width-span-5));
            for(int i=0;i<2;i++) {
                var a=fight.Players[i];
                a.Man=i==0?first:second;
                a.Home=center+(i==0?-span:span);
                if(first!=null && second==null && i==1) a.Home=Limit(first.X+(first.X>width/2?-2:2)*span,15,Math.Max(15,width-15));
                a.Entry=a.Home+(a.Home<width/2?-1:1)*Math.Min(width*.22,180);
                a.Scale=Limit(visitorScales[(int)VisitorSizeTarget.Train],.5,2.5)*1.16;
                a.X=a.Man!=null?a.Man.X:a.Entry;a.Y=a.Man!=null?a.Man.Y:VisitorGround(a.X);
            }
            Fight=fight;return true;
        }
        private void StepFight(double dt) {
            var f=Fight;if(f==null) return;
            f.Age+=dt*VisitorPace;
            if(f.Age>=f.End) {Fight=null;return;}
            for(int i=0;i<2;i++) {
                var a=f.Players[i];var other=f.Players[1-i];
                if(a.Man!=null && (a.Man.Held || !Snowmen.Contains(a.Man))) {Fight=null;return;}
                double enter=Ease(f.Age/1.85),leave=Ease((f.Age-16.0)/2);
                a.X=a.Man==null ? a.Entry+(a.Home-a.Entry)*enter*(1-leave) : a.Man.X;
                a.Y=a.Man==null?VisitorGround(a.X):a.Man.Y;
                a.Face=other.X>=a.X?1:-1;
                a.Stride=(f.Age<1.85 || f.Age>16)?Math.Sin(f.Age*12)*Math.Sin(Math.PI*(f.Age<1.85?enter:leave)):0;
                a.Wave=(1-Ease(Math.Abs(f.Age-2.13)/.65))+ (1-Ease(Math.Abs(f.Age-15.42)/.82));
                a.Windup=a.Follow=a.Duck=0;
                for(int k=0;k<throwsAt.Length;k++) {
                    double rel=f.Age-throwsAt[k];
                    if(i==(k%2)) {
                        if(rel<0 && rel>-.88) a.Windup=Ease((rel+.88)/.68)*(1-Ease((rel+.16)/.16));
                        if(rel>=-.16 && rel<.55) a.Follow=Ease((rel+.16)/.18)*(1-Ease(rel/.55));
                    } else if(rel>.33 && rel<1.40) a.Duck=Math.Max(a.Duck,Math.Sin(Math.PI*(rel-.33)/1.07));
                }
                if(a.Man!=null) a.Man.Facing=a.Face;
            }
            if(f.Throws<throwsAt.Length && f.Age>=throwsAt[f.Throws]) {
                int who=f.Throws++%2;
                var a=f.Players[who];var b=f.Players[1-who];
                double x=a.X+a.Face*(a.Man==null?24*a.Scale:a.Man.MidRadius*1.07);
                double y=a.Y-(a.Man==null?31*a.Scale:a.Man.Height*.61);
                double tx=b.X,ty=b.Y-(b.Man==null?26*b.Scale:b.Man.Height*.57);
                double duration=Limit(.72+Math.Abs(tx-x)*.00062,.76,1.55)/VisitorPace;
                FriendlyShots.Add(new FriendlyShot {X=x,Y=y,Vx=(tx-x)/duration,Vy=(ty-y)/duration-130*duration,Remaining=duration,Target=b.Man});
                PowderBurst(x,y,5,a.Face*12,.35);
            }
        }
        internal FightPlayer FightingSnowman(Snowman man) {
            if(Fight!=null) foreach(var player in Fight.Players) if(player.Man==man) return player;
            return null;
        }
    }
}
