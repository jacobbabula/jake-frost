using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace Frostpane
{
    internal enum PlayTool { Roll, Puff, Pile, Throw, Tree, Lights, Sled, Erase, Decorate, Arrange }

    internal sealed partial class SnowScene
    {
        internal int SnowVolume = 100, DriftDepth = 48, IceLevel;
        private int appliedDepth = -1;
        private PlayTool tool;
        private bool playActive;
        private double playX, playY, stampX, stampY;

        internal PlayTool Tool {
            get { return tool; }
            set { if (tool != value) { CancelPlay(); tool = value; } }
        }

        partial void PropsDown(PlayTool tool,double x,double y);
        partial void PropsMove(double x,double y);
        partial void PropsUp(double x,double y);
        partial void PropsCancel();
        partial void PropsStep(double dt);
        partial void PropsResize();
        partial void PropsClear();
        partial void StepWeather(double dt,double wind);
        partial void ClearWeatherParticles();
        partial void StepSnowplough(double dt);
        partial void ClearSnowplough();
        internal int WeatherIntensity { get; private set; }
        private double SnowWeatherScale {
            get { return Weather==WeatherMode.Snow?1:Weather==WeatherMode.HeavySnow?2.4:0; }
        }

        private int ParticleLimit {
            get { return (int)Math.Min(6000,1050*Math.Max(1,SnowWeatherScale)*Limit(SnowVolume,100,400)/100); }
        }
        private double BankDepth(bool ground)
        {
            double setting = Limit(DriftDepth,24,140);
            return ground ? setting : setting * (22.0 / 48.0);
        }
        private void ApplyDepth()
        {
            int setting=(int)Limit(DriftDepth,24,140);
            if (setting==appliedDepth) return;
            appliedDepth=setting;
            supportBandsDirty = true;
            foreach (SnowBank bank in Banks) {
                bank.MaxDepth=BankDepth(bank.IsFloor);
                for(int i=0;i<bank.Heights.Length;i++)
                    bank.Heights[i]=Math.Min(bank.Heights[i],bank.Maximum(i));
                bank.Revision++;
            }
        }

        internal void PlayDown(double x,double y)
        {
            if (floor==null) return;
            CancelDirect();
            if (playActive) CancelPlay();
            ApplyDepth();
            playActive=true; playX=stampX=x; playY=stampY=y;
            switch (tool) {
                case PlayTool.Roll: PointerDown(x,y); break;
                case PlayTool.Puff: BrushPuff(x,y); break;
                case PlayTool.Pile: SculptAt(x,y,12); break;
                case PlayTool.Throw: BeginThrow(x,y); break;
                default: PropsDown(tool,x,y); break;
            }
        }

        internal void PlayMove(double x,double y)
        {
            if (!playActive) return;
            playX=x; playY=y;
            switch (tool) {
                case PlayTool.Roll: PointerMove(x,y); break;
                case PlayTool.Throw: SampleThrow(x,y); PointerMove(x,y); break;
                case PlayTool.Puff:
                case PlayTool.Pile: BrushStroke(x,y); break;
                default: PropsMove(x,y); break;
            }
        }

        internal void PlayUp(double x,double y)
        {
            if (!playActive) return;
            switch (tool) {
                case PlayTool.Roll: PointerUp(x,y); break;
                case PlayTool.Throw: PlayMove(x,y); FinishThrow(); break;
                case PlayTool.Puff:
                case PlayTool.Pile: BrushStroke(x,y); break;
                default: PropsUp(x,y); break;
            }
            playActive=false;
        }

        internal void CancelPlay()
        {
            CancelDirect();
            playActive=false;
            if (heldBall!=null) { heldBall.Held=false; heldBall=null; }
            if (heldMan!=null) { heldMan.Held=false; heldMan=null; }
            motion.Clear(); PropsCancel();
        }

        // Passive desktop gestures start on snow pixels. Hold the original object
        // while the pointer travels across the otherwise click-through overlay.
        private enum DirectTarget { None, Bank, Ball, Snowman, Sled, Tree }
        private DirectTarget directTarget;
        private bool directDragged;
        private double directX,directY;
        private static double InputClock() { return (double)Stopwatch.GetTimestamp()/Stopwatch.Frequency; }
        private static bool InCircle(double x,double y,double cx,double cy,double radius)
        {
            double dx=x-cx,dy=y-cy; return dx*dx+dy*dy<=radius*radius;
        }
        private Snowman DirectSnowman(double x,double y)
        {
            for (int i=Snowmen.Count-1;i>=0;i--) {
                Snowman m=Snowmen[i];
                double baseY=m.Y-m.BaseRadius;
                double midY=baseY-.78*(m.BaseRadius+m.MidRadius);
                double headY=midY-.78*(m.MidRadius+m.HeadRadius);
                if (InCircle(x,y,m.X,baseY,m.BaseRadius+1) ||
                    InCircle(x,y,m.X,midY,m.MidRadius+1) ||
                    InCircle(x,y,m.X,headY,m.HeadRadius+1) ||
                    (Math.Abs(x-m.X)<=m.HeadRadius*1.36+1 && y>=headY-m.HeadRadius*2.25 && y<headY))
                    return m;
            }
            return null;
        }
        private DirectTarget PickDirectTarget(double x,double y)
        {
            // Props and people are drawn in front of the snowbank.
            if (SledAt(x,y)!=null) return DirectTarget.Sled;
            for(int i=Balls.Count-1;i>=0;i--) {
                SnowBall b=Balls[i];
                if (InCircle(x,y,b.X,b.Y,b.Radius+1)) return DirectTarget.Ball;
            }
            if (DirectSnowman(x,y)!=null) return DirectTarget.Snowman;
            if (TreeAt(x,y)!=null) return DirectTarget.Tree;
            foreach(SnowBank bank in Banks) {
                if(bank.Bare)continue;
                if (x<bank.X || x>bank.X+bank.Width || y>bank.Y+1) continue;
                double h=bank.HeightAt(x);
                if (h>.15 && y>=bank.Y-h-1.5) return DirectTarget.Bank;
            }
            return DirectTarget.None;
        }
        internal bool DirectHit(double x,double y)
        {
            return PickDirectTarget(x,y)!=DirectTarget.None;
        }
        internal bool DirectDown(double x,double y)
        {
            if (playActive || floor==null) return false;
            CancelDirect();
            directTarget=PickDirectTarget(x,y);
            if (directTarget==DirectTarget.None) return false;
            directDragged=false; directX=pointerX=x; directY=pointerY=y;
            motion.Clear(); SampleThrow(x,y,InputClock());
            if (directTarget==DirectTarget.Sled) PropsDown(PlayTool.Sled,x,y);
            if (directTarget==DirectTarget.Tree) PropsDown(PlayTool.Tree,x,y);
            if (directTarget==DirectTarget.Ball) {
                PickBall(x,y);
                if (heldBall!=null) { heldBall.Held=true;heldBall.Vx=heldBall.Vy=0; }
            }
            if (directTarget==DirectTarget.Snowman) {
                heldMan=DirectSnowman(x,y);heldMan.Held=true;
                grabX=x-heldMan.X;grabY=y-heldMan.Y;
            }
            return true;
        }
        internal void DirectMove(double x,double y)
        {
            if (directTarget==DirectTarget.None) return;
            SampleThrow(x,y,InputClock());
            if (!directDragged) {
                if (InCircle(x,y,directX,directY,4)) return;
                directDragged=true;
                if (directTarget==DirectTarget.Bank) {
                    if (Balls.Count+Snowmen.Count>=70) return;
                    heldBall=new SnowBall { X=directX,Y=directY,Radius=9,Held=true };
                    grabX=grabY=0; Balls.Add(heldBall);
                }
            }
            if (directTarget==DirectTarget.Sled || directTarget==DirectTarget.Tree) PropsMove(x,y);
            else PointerMove(x,y);
        }
        internal void DirectUp(double x,double y)
        {
            if (directTarget==DirectTarget.None) return;
            DirectMove(x,y);
            if (directTarget==DirectTarget.Sled || directTarget==DirectTarget.Tree) PropsUp(x,y);
            else if (!directDragged && directTarget==DirectTarget.Bank) PuffAtSnow(directX,directY);
            else if (directDragged && heldBall!=null && LaunchIfFast(heldBall,345)) {
                heldBall.Held=false; heldBall=null;
            }
            else PointerUp(x,y);
            directTarget=DirectTarget.None; motion.Clear();
        }
        internal void CancelDirect()
        {
            if (directTarget==DirectTarget.None) return;
            if (directTarget==DirectTarget.Sled || directTarget==DirectTarget.Tree) PropsCancel();
            if (heldMan!=null) { heldMan.Held=false;heldMan=null; }
            if (heldBall!=null) { heldBall.Held=false;heldBall=null; }
            directTarget=DirectTarget.None;directDragged=false;motion.Clear();
        }

        private void BrushStroke(double x,double y)
        {
            double dx=x-stampX,dy=y-stampY, length=Math.Sqrt(dx*dx+dy*dy);
            double spacing=tool==PlayTool.Pile ? 9 : 17;
            if (length<spacing) return;
            int samples=(int)Math.Min(180,Math.Floor(length/spacing));
            double step=Math.Max(spacing,length/180);
            for (int i=0;i<samples;i++) {
                stampX+=dx/length*step; stampY+=dy/length*step;
                if (tool==PlayTool.Pile) SculptAt(stampX,stampY,3.6);
                else BrushPuff(stampX,stampY);
            }
        }

        private SnowBank BankBelow(double x,double y)
        {
            SnowBank nearest=null;
            double distance=double.PositiveInfinity;
            foreach (SnowBank b in Banks) {
                if(b.Bare)continue;
                if (x<b.X || x>b.X+b.Width || y>b.Y+8) continue;
                double delta=Math.Abs(b.Y-b.HeightAt(x)-y);
                if (delta<distance) { nearest=b; distance=delta; }
            }
            return nearest;
        }

        private void SculptAt(double x,double y,double amount)
        {
            SnowBank bank=BankBelow(x,y);
            if (bank==null) return;
            const double radius=52;
            double step=bank.Width/(bank.Heights.Length-1);
            int first=Math.Max(0,(int)Math.Floor((x-radius-bank.X)/step));
            int end=Math.Min(bank.Heights.Length-1,(int)Math.Ceiling((x+radius-bank.X)/step));
            for (int i=first;i<=end;i++) {
                double d=(bank.X+i*step-x)/radius;
                double weight=Math.Max(0,1-d*d);
                bank.Heights[i]=Math.Min(bank.Maximum(i),bank.Heights[i]+amount*weight*weight);
            }
            bank.Revision++;
            // Keep existing figures on the crest as snow is packed under them.
            foreach (SnowBall b in Balls) {
                if (b.Held || b.InFlight || b.Below!=null || Math.Abs(b.X-x)>radius) continue;
                double bottom=b.Y+b.Radius, top=bank.Y-bank.HeightAt(b.X);
                if (bottom>top && bottom<=bank.Y+.2 && b.X>=bank.X && b.X<=bank.X+bank.Width)
                    b.Y=top-b.Radius;
            }
            foreach (Snowman m in Snowmen) {
                if (m.Held || Math.Abs(m.X-x)>radius || m.X<bank.X || m.X>bank.X+bank.Width) continue;
                double top=bank.Y-bank.HeightAt(m.X);
                if (m.Y>top && m.Y<=bank.Y+.2) m.Y=top;
            }
        }

        // Desktop clicks use strict hit testing. The play brush also works in the surrounding powder.
        internal bool PuffAtSnow(double x,double y) { return DisturbSnow(x,y,true); }
        private void BrushPuff(double x,double y)
        {
            if (!DisturbSnow(x,y,false)) PowderBurst(x,y,7,0,.53);
        }
        private bool DisturbSnow(double x,double y,bool requireHit)
        {
            SnowBank bank=NearbyBank(x,y);
            if (bank!=null) {
                double top=bank.Y-bank.HeightAt(x);
                if (bank.HeightAt(x)<.45 || y<top-(requireHit?2:26) || y>bank.Y+(requireHit?1:6)) bank=null;
            }
            bool hit=bank!=null;
            double range=requireHit?7:26;
            for(int i=Flakes.Count-1;i>=0;i--) {
                Flake f=Flakes[i];
                if (f.Powder) continue;
                double dx=f.X-x,dy=f.Y-y;
                if (dx*dx+dy*dy>(range+f.Radius)*(range+f.Radius)) continue;
                f.Clump=true; f.ThrowX=dx*4+Between(-52,52); f.ThrowY=Between(-155,-65); hit=true;
            }
            if (!hit) return false;
            double originY=y,total=0;
            if (bank!=null) {
                originY=bank.Y-bank.HeightAt(x);
                double step=bank.Width/(bank.Heights.Length-1);
                int min=Math.Max(0,(int)Math.Floor((x-32-bank.X)/step));
                int max=Math.Min(bank.Heights.Length-1,(int)Math.Ceiling((x+32-bank.X)/step));
                for(int i=min;i<=max;i++) {
                    double near=Math.Max(0,1-Math.Abs(bank.X+i*step-x)/32);
                    double take=Math.Min(bank.Heights[i],8*near*near);
                    bank.Heights[i]-=take; total+=take;
                }
                bank.Revision++;
            }
            PowderBurst(x,originY,Math.Min(31,11+(int)total),0,1);
            return true;
        }

        private void PowderBurst(double x,double y,int count,double sideways,double power)
        {
            int n=Math.Min(count,ParticleLimit+300-Flakes.Count);
            for(int i=0;i<n;i++) {
                Flake f=NewFlake(x+Between(-5,5)*power,y+Between(-3,0));
                f.Powder=f.Clump=true; f.Crystal=false; f.Radius=Between(.85,3.4)*power;
                f.Life=f.Lifetime=Between(.38,.92);
                f.ThrowX=sideways*.16+Between(-115,115)*power;
                f.ThrowY=Between(-177,-48)*power;
                Flakes.Add(f);
            }
        }

        private struct ThrowSample
        {
            internal double X,Y,T;
            internal ThrowSample(double x,double y,double time) { X=x;Y=y;T=time; }
        }
        private readonly List<ThrowSample> motion=new List<ThrowSample>(12);

        private void BeginThrow(double x,double y)
        {
            pointerX=x;pointerY=y;
            motion.Clear(); SampleThrow(x,y);
            PickBall(x,y);
            if (heldBall==null) {
                if (Balls.Count+Snowmen.Count>=70) return;
                heldBall=new SnowBall { X=x,Y=y,Radius=12 };
                Balls.Add(heldBall); grabX=grabY=0;
            }
            heldBall.Held=true; heldBall.Vx=heldBall.Vy=0;
            PointerMove(x,y);
        }
        private void SampleThrow(double x,double y)
        {
            SampleThrow(x,y,Time);
        }
        private void SampleThrow(double x,double y,double time)
        {
            // Preserve the original press even if Windows delivers a whole short flick between frames.
            ThrowSample sample=new ThrowSample(x,y,time);
            int last=motion.Count-1;
            if (last>0 && Math.Abs(motion[last].T-time)<.00001) motion[last]=sample;
            else motion.Add(sample);
            while (motion.Count>2 && motion[1].T<time-.125) motion.RemoveAt(0);
        }
        private void FinishThrow()
        {
            SnowBall b=heldBall;
            if (b==null) return;
            b.Held=false; heldBall=null;
            LaunchIfFast(b,55);
            motion.Clear();
        }
        private bool LaunchIfFast(SnowBall b,double threshold)
        {
            if (motion.Count<2) return false;
            ThrowSample first=motion[0],next=motion[1],last=motion[motion.Count-1];
            double start=Math.Max(first.T,last.T-.125);
            if (next.T>first.T && start>first.T) {
                double fraction=Limit((start-first.T)/(next.T-first.T),0,1);
                first.X+=(next.X-first.X)*fraction;first.Y+=(next.Y-first.Y)*fraction;
            }
            double dt=Math.Max(.04,last.T-start);
            double vx=(last.X-first.X)/dt,vy=(last.Y-first.Y)/dt;
            double speed=Math.Sqrt(vx*vx+vy*vy);
            if (speed<=threshold) return false;
            double factor=Math.Min(1,1150/speed);
            b.Vx=vx*factor; b.Vy=vy*factor; b.InFlight=true;
            return true;
        }
        private void AdvanceThrow(SnowBall b,double dt)
        {
            b.Vy=Math.Min(930,b.Vy+565*dt);
            int steps=Math.Max(1,(int)Math.Ceiling(Math.Max(Math.Abs(b.Vx),Math.Abs(b.Vy))*dt/7));
            double slice=dt/steps;
            for(int i=0;i<steps;i++) {
                double foot=b.Y+b.Radius;
                b.X+=b.Vx*slice; b.Y+=b.Vy*slice; b.Rotation+=b.Vx*slice/b.Radius;
                double surface;
                SnowBank bank=FindSupport(b.X,foot,b.Y+b.Radius,2,out surface);
                bool hit=bank!=null || b.X<=b.Radius || b.X>=width-b.Radius || b.Y<=b.Radius || b.Y+b.Radius>=height;
                if (!hit) {
                    foreach (Snowman m in Snowmen)
                        if (!m.Held && Math.Abs(b.X-m.X)<b.Radius+m.BaseRadius*.78 &&
                            b.Y+b.Radius>=m.Y-m.Height && b.Y-b.Radius<=m.Y) { hit=true; break; }
                }
                if (!hit) continue;
                if (bank!=null) { b.Y=surface-b.Radius; Deposit(bank,b.X,b.Radius*.42); }
                PowderBurst(Limit(b.X,1,width-1),Limit(b.Y,1,height-1),32,b.Vx,1.25);
                Balls.Remove(b);
                return;
            }
        }
    }
}
