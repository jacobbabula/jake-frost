using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Frostpane
{
    internal struct StormFlake
    {
        internal double X,Y,Depth,Radius,Phase;
        internal int Shape;
    }
    internal sealed partial class SnowScene
    {
        internal const double BlizzardDuration=22;
        internal StormFlake[] StormSnow;
        internal int StormCount;
        internal double SkyWidth {get{return width;}}
        internal double SkyHeight {get{return height;}}
        internal double CloudTravel,StormStrength;
        private double weatherRemaining,waveIn;
        private int wave;
        internal bool BlizzardActive {get{return weatherRemaining>0;}}
        internal void StartBlizzard()
        {
            if(BlizzardActive)return;
            weatherRemaining=BlizzardDuration;wave=0;waveIn=.35;StormStrength=0;StormCount=0;
        }
        internal void EndBlizzard()
        {
            if(!BlizzardActive && StormCount==0)return;
            weatherRemaining=0;StormStrength=0;StormCount=0;
            for(int i=Visitors.Count-1;i>=0;i--)if(Visitors[i].Wild)Visitors.RemoveAt(i);
        }
        private void Scatter(ref StormFlake flake,bool across)
        {
            flake.Depth=random.NextDouble();
            flake.Radius=1.15+4.0*flake.Depth*flake.Depth+random.NextDouble();
            flake.X=Between(-12,width+12);flake.Y=across?Between(-8,height):-8;
            flake.Phase=Between(0,Math.PI*2);flake.Shape=random.Next(4);
        }
        private void StepSky(double dt,double wind)
        {
            if(!BlizzardActive) {
                if(weather==WeatherMode.Clouds)CloudTravel+=dt*(8+wind*.6);
                return;
            }
            if(weatherRemaining<=dt){EndBlizzard();return;}
            weatherRemaining-=dt;
            double age=BlizzardDuration-weatherRemaining;
            double ramp=Limit(age/2.2,0,1)*Limit(weatherRemaining/3.8,0,1);
            double gust=.5+.5*Math.Sin(age*1.16+.6*Math.Sin(age*.72));
            StormStrength=ramp*(.80+.20*gust);
            CloudTravel+=dt*(22+68*StormStrength);
            int capacity=(int)Limit(width*height/1720,140,900);
            if(StormSnow==null || StormSnow.Length<capacity)Array.Resize(ref StormSnow,capacity);
            int target=(int)(capacity*StormStrength);
            if(StormCount>target)StormCount=target;
            while(StormCount<target)Scatter(ref StormSnow[StormCount++],true);
            double horizontal=wind*.38+StormStrength*(86+180*gust), descent=60+35*gust;
            for(int i=0;i<StormCount;i++) {
                StormFlake f=StormSnow[i];
                double depth=f.Depth,oldX=f.X,oldY=f.Y;
                f.X+=(horizontal*(.47+.84*depth)+15*Math.Sin(Time+f.Phase))*dt;
                f.Y+=(26+descent*depth+7*Math.Cos(Time*1.4+f.Phase))*dt;
                double sy;
                var hit=FindSupport((oldX+f.X)*.5,oldY,f.Y,.15,out sy,true);
                if(hit!=null || f.Y>height+9) {
                    if(hit!=null && depth>.63)Deposit(hit,f.X,.43+f.Radius*.19);
                    Scatter(ref f,false);
                } else if(f.X>width+12)f.X=-10;
                else if(f.X< -12)f.X=width+10;
                StormSnow[i]=f;
            }
            if(age<BlizzardDuration-6 && (waveIn-=dt)<=0) {
                int onStage=0;foreach(var visitor in Visitors)if(visitor.Wild)onStage++;
                int direction=(wave/3)%2==0?1:-1;
                if(onStage<5 && Visitors.Count<12)SendBlizzardYeti(direction);
                wave++;waveIn=wave%3==0?3.5:1.10;
            }
        }
    }

    internal static partial class SnowArtwork
    {
        private static readonly Lazy<BitmapSource[]> CloudImages=new Lazy<BitmapSource[]>(delegate {
            var result=new BitmapSource[3];for(int i=0;i<result.Length;i++)result[i]=CloudTexture(i);return result;
        });
        private static readonly Lazy<BitmapSource[]> FluffyImages=new Lazy<BitmapSource[]>(delegate {
            var result=new BitmapSource[4];for(int i=0;i<4;i++)result[i]=FluffyTexture(i);return result;
        });
        private static double Unit(double x){return Math.Max(0,Math.Min(1,x));}
        private static double CloudHash(int x,int y,int seed) {
            unchecked {
                uint h=(uint)(x*1597334677+y*381201581+seed*171713);
                h=(h^(h>>16))*0x85ebca6bU;h=(h^(h>>13))*0xc2b2ae35U;
                return ((h^(h>>16))&65535)/65535.0;
            }
        }
        private static double Noise(double x,double y,int seed) {
            int a=(int)Math.Floor(x),b=(int)Math.Floor(y);
            double u=x-a,v=y-b;u=u*u*(3-2*u);v=v*v*(3-2*v);
            double top=CloudHash(a,b,seed)*(1-u)+CloudHash(a+1,b,seed)*u;
            double bottom=CloudHash(a,b+1,seed)*(1-u)+CloudHash(a+1,b+1,seed)*u;
            return top+(bottom-top)*v;
        }
        private static BitmapSource Bitmap(int w,int h,byte[] pixels) {
            var image=BitmapSource.Create(w,h,96,96,PixelFormats.Pbgra32,null,pixels,w*4);image.Freeze();return image;
        }
        private static BitmapSource CloudTexture(int seed)
        {
            const int w=328,h=112;
            var densities=new double[w*h];var rgba=new byte[w*h*4];
            for(int y=0;y<h;y++)for(int x=0;x<w;x++) {
                double u=(x+.5)/w,v=(y+.5)/h;
                double crown=.51-.13*Math.Sin(6.3*u+seed*.85)-.052*Math.Sin(16*u+seed);
                double height=.35+.09*Math.Sin(8*u-seed);
                double dome=1-Math.Pow((u-.5)/.46,2)-Math.Pow((v-crown)/height,2);
                double noise=(Noise(u*5,v*2.3,seed)-.5)*.95+(Noise(u*14,v*5.3,seed+24)-.5)*.43+
                    (Noise(u*39,v*15,seed+17)-.5)*.20+(Noise(u*92,v*31,seed+30)-.5)*.07;
                double edge=Unit(Math.Min(Math.Min(x,w-1-x),Math.Min(y,h-1-y))/8.0);
                densities[y*w+x]=Unit((dome*.74+noise-.13)*1.9)*edge;
            }
            for(int y=0;y<h;y++)for(int x=0;x<w;x++) {
                int i=y*w+x,p=i*4;double density=densities[i];if(density<=0)continue;
                double occlusion=densities[Math.Max(0,y-9)*w+Math.Max(0,x-7)];
                double light=Unit(.82+density*.31-occlusion*.54-.18*y/h);
                double alpha=density*.78;
                rgba[p]=(byte)((202+51*light)*alpha);rgba[p+1]=(byte)((161+90*light)*alpha);
                rgba[p+2]=(byte)((139+114*light)*alpha);rgba[p+3]=(byte)(alpha*255);
            }
            return Bitmap(w,h,rgba);
        }
        private static BitmapSource FluffyTexture(int seed)
        {
            const int n=24;var pixels=new byte[n*n*4];
            for(int y=0;y<n;y++)for(int x=0;x<n;x++) {
                double dx=(x+.5-12)/11,dy=(y+.5-12)/10;
                double shape=Math.Sqrt(dx*dx+dy*dy)+.12*Math.Sin(5*Math.Atan2(dy,dx)+seed);
                double a=Unit((1-shape)*2.25),light=Unit(.79-.22*dx-.24*dy);
                int p=(y*n+x)*4;pixels[p]=(byte)(255*a);pixels[p+1]=(byte)((214+41*light)*a);
                pixels[p+2]=(byte)((193+62*light)*a);pixels[p+3]=(byte)(255*a);
            }
            return Bitmap(n,n,pixels);
        }
        private static void DrawClouds(DrawingContext dc,SnowScene scene)
        {
            if(scene.SkyWidth<=0 || (!scene.BlizzardActive && scene.SnowVolume<=0))return;
            double w=scene.SkyWidth,h=scene.SkyHeight;
            double density=scene.BlizzardActive?scene.StormStrength:Unit(scene.SnowVolume/140.0)*(.69+.10*scene.WeatherIntensity);
            var texture=CloudImages.Value;
            for(int layer=0;layer<3;layer++) {
                double size=Math.Max(170,Math.Min(620,w*(.34+.10*layer)));
                double spacing=size*(1.12-.09*layer),period=3*spacing;
                double phase=scene.CloudTravel*(.49+.39*layer)+size*(.34+.85*layer);
                phase=(phase%period+period)%period;
                dc.PushOpacity(density*(.50+.14*layer));
                int first=(int)Math.Floor((-size-phase)/spacing);
                for(int i=first;;i++) {
                    double x=phase+i*spacing;if(x>w)break;
                    int tile=((i%3)+3)%3;
                    double y=h*(.025+.071*layer)+size*(.022*Math.Sin(i*1.8+layer)-.046);
                    dc.DrawImage(texture[(tile+layer)%3],new Rect(x,y,size,size*(.26+.018*layer)));
                }
                dc.Pop();
            }
        }
        private static void DrawStormSnow(DrawingContext dc,SnowScene scene,bool front)
        {
            var textures=FluffyImages.Value;
            for(int i=0;i<scene.StormCount;i++) {
                var f=scene.StormSnow[i];if((f.Depth>.78)!=front)continue;
                double r=f.Radius,w=r*1.17;
                dc.DrawImage(textures[f.Shape],new Rect(f.X-w,f.Y-r,2*w,2*r));
            }
        }
    }
}
