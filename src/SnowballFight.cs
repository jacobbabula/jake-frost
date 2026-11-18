using System;
using System.Collections.Generic;

namespace Frostpane
{
    internal sealed class FightPlayer
    {
        internal Snowman Man;
        internal double X,Y,Face,Windup,Follow,Duck,Wave,Recoil,NextThrow,LastThrow=-10;
        internal int Team,Health=2;
        internal bool Guest;
    }
    internal sealed class SnowballFight
    {
        internal readonly List<FightPlayer> Players=new List<FightPlayer>();
        internal double Age,FinishAt=24;
        internal int Throws,Hits,Breaks;
    }
    internal sealed partial class SnowScene
    {
        internal SnowballFight Fight;
        private static double Ease(double x) { x=Limit(x,0,1);return x*x*(3-2*x); }
        private void EndFight() {
            if(Fight==null)return;
            foreach(var p in Fight.Players)if(p.Guest && !p.Man.Held)Snowmen.Remove(p.Man);
            FriendlyShots.RemoveAll(s=>s.Shooter!=null);Fight=null;
        }
        private void AddPartner(SnowballFight game,Snowman anchor,double center,int index)
        {
            double r=Limit((anchor.BaseRadius*.42+15)*visitorScales[(int)VisitorSizeTarget.Snowmen],14,36);
            double arena=Math.Min(width*.43,285),x=center,space=-1;
            for(int i=0;i<15;i++) {
                double candidate=Limit(center-arena+2*arena*i/14,r+4,Math.Max(r+4,width-r-4)),clear=double.MaxValue;
                foreach(var m in Snowmen)clear=Math.Min(clear,Math.Abs(m.X-candidate)-m.BaseRadius);
                if(clear>space){space=clear;x=candidate;}
            }
            if(space<r*.9)return;
            double ground;
            FindSupport(x,Math.Max(0,anchor.Y-75),height+10,2,out ground);
            var man=new Snowman {X=x,Y=double.IsInfinity(ground)?VisitorGround(x):ground,BaseRadius=r,
                MidRadius=r*(.70+.035*index),HeadRadius=r*.53,Facing=x<center?1:-1,Style=(index+2)%5};
            Snowmen.Add(man);game.Players.Add(new FightPlayer{Man=man,Guest=true});
            PowderBurst(x,man.Y-3,12,0,.6);
        }
        internal bool StartFight()
        {
            if(floor==null)return false;
            EndFight();
            Snowman anchor=null;
            foreach(var man in Snowmen)if(!man.Held && (anchor==null || man==selectedGiftMan))anchor=man;
            if(anchor==null)return false;
            var game=new SnowballFight();
            game.Players.Add(new FightPlayer{Man=anchor});
            var available=Snowmen.FindAll(m=>m!=anchor && !m.Held && Math.Abs(m.Y-anchor.Y)<240 && Math.Abs(m.X-anchor.X)<850);
            available.Sort((a,b)=>Math.Abs(a.X-anchor.X).CompareTo(Math.Abs(b.X-anchor.X)));
            foreach(var m in available) {
                if(game.Players.Count>=6)break;
                game.Players.Add(new FightPlayer{Man=m});
            }
            double center=Limit(anchor.X,Math.Min(width*.5,200),Math.Max(width*.5,width-200));
            for(int i=0;i<3 && game.Players.Count<4 && Snowmen.Count<70;i++)AddPartner(game,anchor,center,i);
            if(game.Players.Count<2)return false;
            game.Players.Sort((a,b)=>a.Man.X.CompareTo(b.Man.X));
            int split=(game.Players.Count+1)/2;
            for(int i=0;i<game.Players.Count;i++) {
                var p=game.Players[i];p.Team=i<split?0:1;
                p.X=p.Man.X;p.Y=p.Man.Y;p.Face=p.Team==0?1:-1;
                p.NextThrow=1.3+(i%split)*.85+p.Team*.53;
            }
            Fight=game;return true;
        }
        private void StepFight(double dt)
        {
            var f=Fight;if(f==null)return;
            f.Age+=dt*VisitorPace;
            if(f.Age>=f.FinishAt) {EndFight();return;}
            int left=0,right=0;
            foreach(var p in f.Players) {
                if(!Snowmen.Contains(p.Man) || p.Man.Held)p.Health=0;
                if(p.Health>0) {if(p.Team==0)left++;else right++;}
            }
            if(left==0 || right==0)f.FinishAt=Math.Min(f.FinishAt,f.Age+1.0);
            for(int i=0;i<f.Players.Count;i++) {
                var a=f.Players[i];if(a.Health<=0)continue;
                a.X=a.Man.X;a.Y=a.Man.Y;
                FightPlayer other=null;
                for(int j=0;j<f.Players.Count;j++) {
                    var candidate=f.Players[(i+f.Throws+j)%f.Players.Count];
                    if(candidate.Health>0 && candidate.Team!=a.Team){other=candidate;break;}
                }
                a.Recoil=Math.Max(0,a.Recoil-dt*2.5);
                a.Wave=other==null?Math.Abs(Math.Sin(7*f.Age)):0;
                a.Duck=.33*Math.Max(0,Math.Sin(3.7*f.Age+i*1.2));
                double before=a.NextThrow-f.Age,after=f.Age-a.LastThrow;
                a.Windup=other==null?0:Ease(1-before/.72);
                a.Follow=1-Ease(after/.48);
                if(other==null)continue;
                a.Face=other.Man.X>=a.X?1:-1;a.Man.Facing=a.Face;
                if(before>0 || FriendlyShots.Count>=20)continue;
                a.LastThrow=f.Age;a.NextThrow=f.Age+2.45+.24*(i%3);
                double radius=Limit(a.Man.MidRadius*.30,4.2,9);
                double x=a.X+a.Face*(a.Man.MidRadius*1.3+radius),y=a.Y-a.Man.Height*.65;
                bool high=f.Throws%5==4;
                double tx=other.Man.X,ty=other.Man.Y-other.Man.Height*(high?1.20:.60);
                double duration=Limit(.62+Math.Abs(tx-x)*.0013,.64,1.45)/VisitorPace;
                FriendlyShots.Add(new FriendlyShot {X=x,Y=y,Vx=(tx-x)/duration,Vy=(ty-y)/duration-130*duration,
                    Remaining=duration+1.1,Target=other.Man,Shooter=a,Radius=radius});
                f.Throws++;PowderBurst(x,y,5,a.Face*12,.35);
            }
        }
        private bool AdvanceBattleShot(FriendlyShot shot,double dt)
        {
            double travel=Math.Sqrt(shot.Vx*shot.Vx+shot.Vy*shot.Vy)*dt;
            int n=(int)Limit(Math.Ceiling(travel/6),1,18);double step=dt/n;
            for(int i=0;i<n;i++) {
                double oldX=shot.X,oldY=shot.Y;shot.X+=shot.Vx*step;
                shot.Y+=shot.Vy*step+130*step*step;shot.Vy+=260*step;shot.Remaining-=step;
                if(Fight!=null)foreach(var p in Fight.Players) {
                    if(p==shot.Shooter || p.Health<=0 || p.Man.Held || !Snowmen.Contains(p.Man) ||
                       !TouchesFigure(p.Man,shot.X,shot.Y,shot.Radius))continue;
                    Fight.Hits++;p.Health--;p.Recoil=1;
                    ScatterSnow(shot.X,shot.Y,shot.Radius,shot.Vx,Math.Abs(shot.Vy)+110,null);
                    if(p.Health==0){Fight.Breaks++;CrumbleFigure(p.Man,shot.Vx,Math.Abs(shot.Vy)+140);}
                    return true;
                }
                double surface;
                var bank=FindSupport((oldX+shot.X)*.5,oldY+shot.Radius,shot.Y+shot.Radius,1,out surface);
                if(bank!=null) {
                    ScatterSnow(shot.X,surface-1,shot.Radius,shot.Vx,Math.Abs(shot.Vy),bank);return true;
                }
                if(shot.Remaining<=0 || shot.X< -30 || shot.X>width+30 || shot.Y>height+30)return true;
            }
            return false;
        }
        internal FightPlayer FightingSnowman(Snowman man)
        {
            if(Fight!=null)foreach(var p in Fight.Players)if(p.Man==man && p.Health>0)return p;
            return null;
        }
    }
}
