using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;

namespace Frostpane
{
    internal enum WeatherMode { Snow, HeavySnow, Rain, Sakura, Leaves, Fireflies, Starfall, Off, Clouds }
    internal enum WeatherState { Airborne, Resting, Splash, Spark }

    internal sealed class WeatherParticle
    {
        internal double X,Y,Vx,Vy,Speed,Size,Phase,Angle,Spin,Life,Duration;
        internal double SupportX,SupportY,SupportWidth,LocalX,SkipUntil;
        internal int Variant;
        internal WeatherState State;
        internal SnowBank Support,Skip;
    }

    internal sealed partial class SnowScene
    {
        internal readonly List<WeatherParticle> WeatherParticles=new List<WeatherParticle>();
        private WeatherMode weather;
        private bool warmWeather, pointerInside;
        private double weatherBudget, wx, wy, pointerMovedAt;
        private double stormClock;
        private bool lightningEnabled;
        internal const double StrikeDuration=.78;
        internal double LightningTime;
        internal StreamGeometry LightningBolt,LightningBranches;
        internal bool LightningEnabled {
            get { return lightningEnabled; }
            set {
                if(value==lightningEnabled) return;
                lightningEnabled=value;
                ResetStorm();
            }
        }
        internal bool HasSnowWeather { get { return BlizzardActive || weather==WeatherMode.Snow || weather==WeatherMode.HeavySnow; } }
        internal WeatherMode Weather {
            get { return weather; }
            set {
                if (value==weather) return;
                bool previousSnow=HasSnowWeather;
                weather=value;
                ClearWeatherParticles();
                if (!HasSnowWeather) Flakes.Clear();
                if (HasSnowWeather && !previousSnow && width>1 && height>1) {
                    int initial=(int)(Limit(width*height/10500,2,300)*Limit(SnowVolume,0,400)/100);
                    for(int i=0;i<initial;i++) Flakes.Add(NewFlake(Between(0,width),Between(0,height)));
                }
                warmWeather=true;
            }
        }

        partial void ClearWeatherParticles()
        {
            WeatherParticles.Clear();
            weatherBudget=0; warmWeather=false;
            ResetStorm();
        }

        private void ResetStorm()
        {
            LightningTime=0;
            LightningBolt=null; LightningBranches=null;
            stormClock=1.15;
        }

        private void StartStrike()
        {
            // Keep a single branching path throughout the flash and its afterglow.
            double x=Between(width*.20,width*.80), y=-4;
            double depth=Between(.25,.48)*height, drift=Between(-.42,.42)*depth;
            LightningBolt=new StreamGeometry();
            LightningBranches=new StreamGeometry();
            using(var bolt=LightningBolt.Open())
            using(var branches=LightningBranches.Open()) {
                var origin=new Point(x,y);
                bolt.BeginFigure(origin,false,false);
                const int segments=15;
                for(int i=1;i<=segments;i++) {
                    double t=i/(double)segments;
                    var point=new Point(Limit(x+drift*t+Between(-.035,.035)*depth,0,width),y+t*depth);
                    bolt.LineTo(point,true,false);
                    if(i==3 || i==6 || i==9) {
                        double reach=Between(.11,.26)*depth*(i==6?-1:1);
                        branches.BeginFigure(point,false,false);
                        for(int j=1;j<=4;j++) {
                            double u=j/4.0;
                            branches.LineTo(new Point(point.X+reach*u+Between(-.012,.012)*depth,
                                point.Y+Math.Abs(reach)*u*.91),true,false);
                        }
                    }
                }
            }
            LightningBolt.Freeze(); LightningBranches.Freeze();
            LightningTime=StrikeDuration;
            stormClock=Between(9,22);
        }

        internal void SetWeatherPointer(double x,double y,bool inside)
        {
            if (!inside) { pointerInside=false; return; }
            double dx=x-wx,dy=y-wy,dist=Math.Sqrt(dx*dx+dy*dy);
            if (!pointerInside || dist>1.5) pointerMovedAt=Time;
            if (pointerInside && dist>2 && (weather==WeatherMode.Leaves || weather==WeatherMode.Sakura)) {
                foreach(WeatherParticle p in WeatherParticles) {
                    double vx=p.X-x,vy=p.Y-y;
                    if (vx*vx+vy*vy>50*50) continue;
                    if (p.Support!=null) Lift(p,0,0);
                    p.Vx=Limit(dx/dist*110+vx*1.8,-175,175);
                    p.Vy=Limit(dy/dist*48-72+vy*.8,-140,-24);
                }
            }
            wx=x;wy=y;pointerInside=true;
        }

        private int AirTarget()
        {
            if (SnowVolume<=0 || WeatherIntensity<=0) return 0;
            double density,minimum,maximum;
            switch(weather) {
                case WeatherMode.Rain: density=13700;minimum=10;maximum=360;break;
                case WeatherMode.Sakura: density=26500;minimum=5;maximum=190;break;
                case WeatherMode.Leaves: density=37000;minimum=5;maximum=135;break;
                case WeatherMode.Fireflies: density=48000;minimum=7;maximum=105;break;
                default: density=150000;minimum=2;maximum=17;break;
            }
            double intensity=WeatherIntensity==1?.57:WeatherIntensity>=3?1.55:1;
            return (int)Math.Ceiling(Limit(width*height/density,minimum,maximum)*Math.Min(4,SnowVolume/100.0)*intensity);
        }

        private WeatherParticle NewWeather(bool scattered)
        {
            var p=new WeatherParticle { X=Between(1,Math.Max(2,width)),Y=scattered?Between(0,height):-9,
                Phase=Between(0,6.28),Angle=Between(0,6.28),Spin=Between(-2.4,2.4),Variant=random.Next(3) };
            if (weather==WeatherMode.Rain) {p.Size=Between(.65,1.5);p.Speed=Between(390,660);p.Vy=p.Speed;}
            else if (weather==WeatherMode.Sakura || weather==WeatherMode.Leaves) {
                bool leaf=weather==WeatherMode.Leaves;
                p.Size=leaf?Between(.52,1.2):Between(.48,1.08);
                p.Speed=leaf?Between(28,63):Between(17,42); p.Vy=p.Speed;
            }
            else if (weather==WeatherMode.Fireflies) {
                p.Y=Between(height*.12,height*.94);p.Size=Between(.68,1.32);p.Speed=Between(.54,1.3);
                p.Duration=Between(6,14);p.Life=p.Duration*(scattered?Between(.35,.95):1);
            }
            else {
                p.Size=Between(.60,1.35); p.Speed=Between(250,430);p.Vx=-p.Speed*Between(.95,1.45);p.Vy=p.Speed;
                if (!scattered) {
                    p.X=Between(8,width+height*.9);
                    // Stars entering from the right are visible immediately on tall displays.
                    if (p.X>width){p.Y=(p.X-width)*.85;p.X=width+3;}
                }
            }
            return p;
        }

        partial void StepWeather(double dt,double wind)
        {
            if (HasSnowWeather || weather==WeatherMode.Off || weather==WeatherMode.Clouds || width<1 || height<1) return;
            int target=AirTarget();
            if (warmWeather && target>0) {
                for(int i=0;i<target;i++) WeatherParticles.Add(NewWeather(true));
                warmWeather=false;
            }
            int airborne=0;
            for(int i=WeatherParticles.Count-1;i>=0;i--){
                WeatherParticle p=WeatherParticles[i];
                if (!MoveWeather(p,dt,wind)) { WeatherParticles.RemoveAt(i);continue; }
                if (p.State==WeatherState.Airborne) airborne++;
            }
            if (airborne<target && WeatherParticles.Count<target*3+48) {
                double travel=weather==WeatherMode.Fireflies?8:height/(weather==WeatherMode.Rain?560:
                    weather==WeatherMode.Starfall?345:weather==WeatherMode.Leaves?43:29);
                weatherBudget=Math.Min(target,weatherBudget+target/Math.Max(.22,travel)*dt);
                int add=Math.Min((int)weatherBudget,target-airborne);
                for(int i=0;i<add;i++) WeatherParticles.Add(NewWeather(false));
                weatherBudget-=add;
            }
            else weatherBudget=0;
            LightningTime=Math.Max(0,LightningTime-dt);
            if (weather!=WeatherMode.Rain || !LightningEnabled || target==0) { LightningTime=0; return; }
            if ((stormClock-=dt)<=0) StartStrike();
        }

        private bool ValidSupport(SnowBank bank)
        {
            if (bank==null) return false;
            if (bank.IsFloor) return bank==floor;
            SnowBank current;return windows.TryGetValue(bank.Id,out current) && current==bank;
        }

        private void Lift(WeatherParticle p,double dx,double dy)
        {
            p.Skip=p.Support;p.SkipUntil=Time+.7;p.Support=null;p.State=WeatherState.Airborne;
            p.Vx=Limit(dx*2,-135,135)+Between(-20,20);p.Vy=Limit(dy,-60,40)-Between(30,72);
        }

        private SnowBank WeatherSupport(double oldX,double oldY,WeatherParticle p)
        {
            if (p.Y<=oldY) return null;
            SnowBank first=null;
            foreach(SnowBank bank in Banks){
                if (bank==p.Skip && Time<p.SkipUntil || bank.Y<oldY-.001 || bank.Y>p.Y || first!=null && bank.Y>=first.Y) continue;
                double x=oldX+(p.X-oldX)*(bank.Y-oldY)/(p.Y-oldY);
                if (x>=bank.X && x<=bank.X+bank.Width) first=bank;
            }
            return first;
        }

        private bool MoveWeather(WeatherParticle p,double dt,double wind)
        {
            if (p.State==WeatherState.Splash || p.State==WeatherState.Spark){
                if (p.State==WeatherState.Spark){p.X+=p.Vx*dt;p.Y+=p.Vy*dt;p.Vy+=105*dt;}
                return (p.Life-=dt)>0;
            }
            if (p.State==WeatherState.Resting) {
                if ((p.Life-=dt)<=0) return false;
                SnowBank bank=p.Support;
                if (!ValidSupport(bank) || Math.Abs(bank.X-p.SupportX)>1.75 || Math.Abs(bank.Y-p.SupportY)>1.75 ||
                    Math.Abs(bank.Width-p.SupportWidth)>2.5 || p.LocalX>bank.Width) {
                    Lift(p,bank==null?0:bank.X-p.SupportX,bank==null?0:bank.Y-p.SupportY);
                } else {p.X=bank.X+p.LocalX;p.Y=bank.Y-1;return true;}
            }
            if (weather==WeatherMode.Fireflies) {
                if((p.Life-=dt)<=0) return false;
                double vx=wind*.23+19*Math.Sin(Time*p.Speed+p.Phase)+8*Math.Cos(Time*.39-p.Phase);
                double vy=12*Math.Cos(Time*.75*p.Speed+p.Phase);
                if (pointerInside && Time-pointerMovedAt>.42) {
                    double dx=wx-p.X,dy=wy-p.Y;
                    if (dx*dx+dy*dy<310*310) {
                        vx+=Limit((dx+34*Math.Cos(Time*.61+p.Phase))*.68,-105,105);
                        vy+=Limit((dy+26*Math.Sin(Time*.54+p.Phase))*.68,-95,95);
                    }
                }
                p.X+=vx*dt;p.Y=Limit(p.Y+vy*dt,1,height-1);
                if(p.X< -6)p.X=width+4;if(p.X>width+6)p.X=-4;
                return true;
            }
            double oldX=p.X,oldY=p.Y;
            if (weather==WeatherMode.Rain) {
                p.Vx=wind*1.8-29;p.X+=p.Vx*dt;p.Y+=p.Vy*dt;
            } else if (weather==WeatherMode.Starfall) {p.X+=(p.Vx+wind*.46)*dt;p.Y+=p.Vy*dt;}
            else {
                double flutter=weather==WeatherMode.Leaves?26:17;
                double vx=wind*.78+flutter*Math.Sin(Time*(weather==WeatherMode.Leaves?1.32:1.04)+p.Phase);
                p.Vx+=(vx-p.Vx)*Math.Min(1,dt*1.3);
                p.Vy+=(p.Speed+(4*Math.Cos(Time*1.5+p.Phase))-p.Vy)*Math.Min(1,dt*1.9);
                p.Angle+=p.Spin*dt;p.X+=p.Vx*dt;p.Y+=p.Vy*dt;
            }
            SnowBank hit=WeatherSupport(oldX,oldY,p);
            if (hit!=null){
                p.X=Limit(oldX+(p.X-oldX)*(hit.Y-oldY)/(p.Y-oldY),hit.X,hit.X+hit.Width);p.Y=hit.Y-1;
                if (weather==WeatherMode.Rain) {
                    p.State=WeatherState.Splash;p.Life=p.Duration=Between(.16,.30);return true;
                }
                if (weather==WeatherMode.Starfall) {
                    if(WeatherParticles.Count<640) for(int j=0;j<7;j++) {
                        double angle=Between(Math.PI,Math.PI*2); double kick=Between(23,77);
                        var spark=new WeatherParticle{X=p.X,Y=p.Y,Size=p.Size*.75,Variant=p.Variant,
                            State=WeatherState.Spark,Vx=Math.Cos(angle)*kick,Vy=Math.Sin(angle)*kick,Life=Between(.24,.56)};
                        spark.Duration=spark.Life;WeatherParticles.Add(spark);
                    }
                    return false;
                }
                p.State=WeatherState.Resting;p.Life=p.Duration=Between(4,11);p.Support=hit;
                p.LocalX=p.X-hit.X;p.SupportX=hit.X;p.SupportY=hit.Y;p.SupportWidth=hit.Width;
                p.Angle=Between(-.28,.28)+(p.Vx<0?Math.PI:0);return true;
            }
            if(weather!=WeatherMode.Starfall) {
                if(p.X< -12)p.X=width+8;if(p.X>width+12)p.X=-8;
            }
            return p.Y<height+12 && p.X> -35;
        }
    }

    internal static partial class SnowArtwork
    {
        private static void DrawWeather(DrawingContext dc,SnowScene scene) { SeasonalArt.Draw(dc,scene); }
        private static class SeasonalArt
        {
            private static readonly Pen[] Rain={Stroke("#7086ACC9",.8),Stroke("#AAA4CAE3",1),Stroke("#BFC6E3F4",1.22)};
            private static readonly Pen RainGlint=Stroke("#A7E6F7FF",.7);
            private static readonly Pen Splash=Stroke("#A1C7E2F1",.84);
            private static readonly Brush Spray=Ink("#DDE0F4FF");
            private static readonly Brush[] Ruby={Ink("#FFF2F5"),Ink("#FCD6E5"),Ink("#FFC1D8")};
            private static readonly Brush[] PetalBack={Ink("#FBB8D0"),Ink("#E997B7"),Ink("#EC95B5")};
            private static readonly Brush[] LeafFill={Vertical("#FFD186","#E99551","#C16342"),Vertical("#E8AE75","#C86E4E","#9D4E3B"),Vertical("#FFE39A","#E1AA4F","#B47E39")};
            private static readonly Pen LeafVein=Stroke("#926D422B",.72);
            private static readonly Pen PetalVein=Stroke("#AAEFA6BF",.6);
            private static readonly Brush[] FireCore={Ink("#C8EA90"),Ink("#F2EB9C"),Ink("#E3FFB4")};
            private static readonly Lazy<Sprite[,]> Petals=new Lazy<Sprite[,]>(delegate {return Foliage(false);});
            private static readonly Lazy<Sprite[,]> Leaves=new Lazy<Sprite[,]>(delegate {return Foliage(true);});
            private static readonly Lazy<Sprite[,]> Glow=new Lazy<Sprite[,]>(FireflySprites);
            private static readonly Pen[] StarCore={Stroke("#FFEBF2FF",1.6),Stroke("#FFFFE5B4",1.6),Stroke("#FFEDE3FF",1.6)};
            private static readonly Pen[] StarTrail={Stroke("#A290B9EC",1.21),Stroke("#ABBBA875",1.21),Stroke("#A7BA99DA",1.21)};
            private static readonly Pen[] StarWake={Stroke("#4B99B7E6",.81),Stroke("#53C4A076",.81),Stroke("#52AD99CD",.81)};
            private static readonly Brush[] StarHead={Ink("#F2F6FF"),Ink("#FFF3D4"),Ink("#F3EDFF")};
            private static readonly Pen BoltHalo=Stroke("#367A9FF9",8), BoltEdge=Stroke("#ABB1CFFF",3.4);
            private static readonly Pen BoltCore=Stroke("#FFF1F6FF",1.45), Branch=Stroke("#BFC6DCFF",1.08);
            private static Sprite[,] Foliage(bool isLeaf) {
                Sprite[,] result=new Sprite[3,36];
                for(int v=0;v<3;v++) {
                    int variant=v;
                    Sprite element=new Sprite(delegate(DrawingContext dc){
                        if(isLeaf) PaintLeaf(dc,variant);else PaintPetal(dc,variant);
                    });
                    for(int f=0;f<36;f++) {
                        int frame=f;
                        result[v,f]=new Sprite(delegate(DrawingContext dc){
                            dc.PushTransform(new RotateTransform((frame%12)*30));
                            dc.PushTransform(new ScaleTransform(1,(frame/12+1)/3.0));
                            element.Draw(dc,0,0,1);dc.Pop();dc.Pop();
                        });
                    }
                }
                return result;
            }
            private static void PaintPetal(DrawingContext dc,int v) {
                Path(dc,PetalBack[v],Stroke("#AAD890A9",.46),"M -5.9,.7 C -2.9,-3.5 1.3,-5.7 4.1,-4 L 3.75,-2.4 5.15,-2.8 C 7.15,-.2 3.15,3.2 -.6,3.15 Q -3.6,3.15 -5.9,.7 Z");
                Path(dc,Ruby[v],null,"M -5.8,.6 Q -1,-6.1 3.9,-4 L 3.6,-2.1 5,-2.6 Q 5.7,-1.4 5.3,-.1 Q .4,1.5 -5.8,.6 Z");
                dc.DrawLine(PetalVein,new Point(-4.8,.75),new Point(2.2,-1.3));
            }
            private static void PaintLeaf(DrawingContext dc,int v) {
                if(v==1) Path(dc,LeafFill[v],null,"M -7,1 -5,-1 -7,-4 -3,-3 -2,-8 1,-5 4,-7 4,-3 8,-4 7,-1 10,.2 6,2 7,4 3,4 1,7 -1,4 -4,5 -4,3 Z");
                else if(v==0) Path(dc,LeafFill[v],null,"M -8,.7 Q -5.4,-4 -1.6,-4.65 L -.8,-5.5 1,-4.8 Q 4.2,-4.9 8.4,-3.7 Q 5.4,2.8 1,4.4 L .3,4 -2,4.7 Q -5.6,4.4 -8,.7 Z");
                else Path(dc,LeafFill[v],null,"M -7,1 Q -5,-5 1,-5.4 Q 4,-5.6 8,-4.9 Q 7,-.5 4,3.1 Q -1.2,7 -7,1 Z");
                Path(dc,null,LeafVein,"M -10.3,2.3 Q -4.4,.7 5.5,-2.2 M -3,.2 L -2,-2.7 M .1,-.7 L 1.8,-3.4 M -2.9,.1 L -.8,2.6 M .7,-.8 L 3.1,.8");
            }
            private static Sprite[,] FireflySprites() {
                var result=new Sprite[3,8];
                for(int v=0;v<3;v++)for(int k=0;k<8;k++){
                    int variant=v,frame=k;
                    result[v,k]=new Sprite(delegate(DrawingContext dc) {
                        double power=(frame+1)/8.0,r=4.7+5.3*power;
                        RadialGradientBrush halo=new RadialGradientBrush();
                        Color tint=((SolidColorBrush)FireCore[variant]).Color;
                        halo.GradientStops.Add(new GradientStop(Color.FromArgb((byte)(100*power),tint.R,tint.G,tint.B),0));
                        halo.GradientStops.Add(new GradientStop(Color.FromArgb((byte)(48*power),tint.R,tint.G,tint.B),.36));
                        halo.GradientStops.Add(new GradientStop(Color.FromArgb(0,tint.R,tint.G,tint.B),1));halo.Freeze();
                        Dot(dc,halo,0,0,r,r);Dot(dc,Ink("#C84D5840"),.2,-.9,.8,1.1);
                        Dot(dc,FireCore[variant],0,0,.65+power*.7,.7+power*.61);
                        if(frame>3)Dot(dc,Ink("#FFFBDC"),-.12,-.08,.46,.39);
                    });
                }
                return result;
            }
            internal static void Draw(DrawingContext dc,SnowScene scene) {
                foreach(WeatherParticle p in scene.WeatherParticles) {
                    switch(scene.Weather) {
                        case WeatherMode.Rain: DrawRain(dc,p);break;
                        case WeatherMode.Sakura: case WeatherMode.Leaves:
                            int angle=((int)Math.Floor(p.Angle*6/Math.PI+.5)%12+12)%12;
                            int tilt=p.State==WeatherState.Resting?0:Math.Min(2,(int)(Math.Abs(Math.Cos(scene.Time*1.8+p.Phase))*3));
                            bool fading=p.State==WeatherState.Resting && p.Life<1.4;
                            if(fading)dc.PushOpacity(Math.Max(0,p.Life/1.4));
                            (scene.Weather==WeatherMode.Leaves?Leaves:Petals).Value[p.Variant,angle+12*tilt].Draw(dc,p.X,p.Y,p.Size);
                            if(fading)dc.Pop();break;
                        case WeatherMode.Fireflies:
                            double pulse=.5+.5*Math.Sin(scene.Time*(1.6+p.Speed)+p.Phase);
                            int glow=(int)LimitGlow(pulse*Math.Min(1,p.Life/.9)*Math.Min(1,(p.Duration-p.Life)/.55));
                            Glow.Value[p.Variant,glow].Draw(dc,p.X,p.Y,p.Size);break;
                        case WeatherMode.Starfall: DrawStar(dc,p);break;
                    }
                }
                if(scene.Weather==WeatherMode.Rain && scene.LightningEnabled && scene.LightningTime>0) {
                    double age=1-scene.LightningTime/SnowScene.StrikeDuration;
                    double brightness=Math.Min(1,.2+age*18)*Math.Pow(1-age,1.45);
                    dc.PushOpacity(brightness);
                    dc.DrawGeometry(null,BoltHalo,scene.LightningBolt);
                    dc.DrawGeometry(null,Branch,scene.LightningBranches);
                    dc.DrawGeometry(null,BoltEdge,scene.LightningBolt);
                    dc.DrawGeometry(null,BoltCore,scene.LightningBolt);
                    dc.Pop();
                }
            }
            private static double LimitGlow(double value){return Math.Max(0,Math.Min(7,value*7.99));}
            private static void DrawRain(DrawingContext dc,WeatherParticle p){
                if(p.State==WeatherState.Splash){
                    double age=1-p.Life/p.Duration,spread=2+5*age;
                    dc.PushOpacity(Math.Max(0,1-age));
                    dc.DrawEllipse(null,Splash,new Point(p.X,p.Y+.4),spread,.45+.85*age);
                    Dot(dc,Spray,p.X-spread*.68,p.Y-10*age*(1-age),.6,.73);
                    Dot(dc,Spray,p.X+spread*.73,p.Y-13*age*(1-age),.62,.85);dc.Pop();return;
                }
                double dy=(7+p.Size*6.4),dx=dy*p.Vx/p.Vy;
                Point tip=new Point(p.X,p.Y);
                dc.DrawLine(Rain[p.Variant],new Point(p.X-dx,p.Y-dy),tip);
                dc.DrawLine(RainGlint,new Point(p.X-dx*.25,p.Y-dy*.25),tip);
            }
            private static void DrawStar(DrawingContext dc,WeatherParticle p){
                Point tip=new Point(p.X,p.Y);
                if(p.State==WeatherState.Spark){
                    dc.PushOpacity(p.Life/p.Duration);dc.DrawLine(StarCore[p.Variant],tip,new Point(p.X-p.Vx*.026,p.Y-p.Vy*.026));dc.Pop();return;
                }
                double t=.081*p.Size;
                dc.DrawLine(StarWake[p.Variant],new Point(p.X-p.Vx*t,p.Y-p.Vy*t),new Point(p.X-p.Vx*t*.56,p.Y-p.Vy*t*.56));
                dc.DrawLine(StarTrail[p.Variant],new Point(p.X-p.Vx*t*.56,p.Y-p.Vy*t*.56),new Point(p.X-p.Vx*t*.16,p.Y-p.Vy*t*.16));
                dc.DrawLine(StarCore[p.Variant],new Point(p.X-p.Vx*t*.16,p.Y-p.Vy*t*.16),tip);
                double r=p.Size*2.7;dc.DrawLine(StarTrail[p.Variant],new Point(p.X-r,p.Y),new Point(p.X+r,p.Y));
                dc.DrawLine(StarTrail[p.Variant],new Point(p.X,p.Y-r),new Point(p.X,p.Y+r));
                Dot(dc,StarHead[p.Variant],p.X,p.Y,p.Size,p.Size);
            }
        }
    }
}
