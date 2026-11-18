using System;
using System.Windows;
using System.Windows.Media;

namespace Frostpane
{
    internal static partial class VisitorArtwork
    {
        internal static Transform SnowmanPose(FightPlayer a) {
            var matrix=Matrix.Identity;
            matrix.ScaleAt(1+.045*a.Duck,1-.10*a.Duck,a.X,a.Y);
            matrix.RotateAt(a.Face*(7*a.Follow-6*a.Windup-4*a.Duck),a.X,a.Y);
            return new MatrixTransform(matrix);
        }
        internal static void ThrowingTwig(DrawingContext d,FightPlayer a) {
            var man=a.Man;double r=man.MidRadius;
            double y=man.Y-man.BaseRadius-.78*(man.BaseRadius+r);
            double sx=man.X+a.Face*r*.6,ex=sx+a.Face*r*(.65+1.05*a.Follow-.65*a.Windup);
            double ey=y-r*(.3+1.15*a.Windup+.7*a.Follow+.7*a.Wave);
            L(d,"#79543E",2.15,sx,y,ex,ey);L(d,"#946849",1.45,ex-a.Face*2,ey+1,ex+a.Face*3,ey-3);
            if(a.Windup>.15) {E(d,"#C5E1EC",ex,ey-2,4,4);E(d,"#F6FDFF",ex-.6,ey-2.8,3.3,3.3);}
        }
        private static void DrawFight(DrawingContext d,SnowScene scene) {
            var fight=scene.Fight;if(fight==null) return;
            foreach(var a in fight.Players) {
                if(a.Man!=null) continue;
                bool departing=fight.Age>16;
                double face=departing?(a.Entry<a.Home?-1:1):a.Face;
                var matrix=Matrix.Identity;matrix.Scale(a.Scale*face,a.Scale);matrix.Translate(a.X,a.Y);
                d.PushTransform(new MatrixTransform(matrix));
                E(d,"#34374A53",0,-1,14,2.4);
                double gait=a.Stride, crouch=4.8*a.Duck+2.2*a.Windup,bob=1.5*Math.Abs(gait);
                Boot(d,-3-gait*5,-9+crouch*.6, -4+6*gait,-1-Math.Max(0,gait)*4);
                Boot(d,3+gait*4,-8+crouch*.6, 5-5*gait,-1-Math.Max(0,-gait)*4);
                d.PushTransform(new TranslateTransform(0,crouch-bob));
                d.PushTransform(new RotateTransform(7*a.Follow-9*a.Windup,-1,-10));
                string coat=a.Red?"#BA4B4A":"#2D8279",shade=a.Red?"#793744":"#225862",light=a.Red?"#E77E66":"#62B09C";
                double handX=13+11*a.Follow-14*a.Windup;
                double handY=-23-8*a.Follow-11*a.Windup-10*a.Wave;
                L(d,shade,5,-4,-22,-9-2*gait,-16-a.Wave*8);
                E(d,"#EAC199",-9-2*gait,-16-a.Wave*8,2.9,3);
                P(d,coat,"M-7,-25 Q-1,-29 6,-24 L10,-10 Q7,-6 -9,-9 L-7,-19 Z");
                P(d,shade,"M-7,-22 Q-4,-14 -2,-9 L-9,-9 Z");L(d,light,1.1,3,-21,6,-11);
                L(d,"#EDCC8F",1.6,-7,-10,8,-10);E(d,"#EFCC85",3,-17,1.1,1.1);
                P(d,"#E9B24D","M-5,-25 L5,-25 5,-21 -5,-21 -9,-16 -12,-18 Z");
                E(d,"#E9AD82",-1,-30,7.4,7.3);P(d,"#F5C5A0","M-5,-29 Q-12,-36 -11,-29 Q-9,-25 -5,-26 Z");
                E(d,"#F6C5A0",4,-30,5.3,5.7);E(d,"#E89A80",3.8,-28,2.8,1.7);
                E(d,"#523F42",5.3,-31.9,.9,1.15);E(d,"#FFDBA7",8.5,-30,2.1,1.5);
                L(d,"#9A605C",.85,4.8,-26.7,7,-27.3);
                double swing=2*Math.Sin(fight.Age*5)*Math.Abs(gait)+3*a.Follow-3*a.Duck;
                d.PushTransform(new RotateTransform(swing,0,-34));
                P(d,shade,"M-8,-34 Q-7,-45 -18,-42 Q-12,-50 -3,-47 Q3,-45 8,-35 Z");
                P(d,coat,"M-8,-35 Q-7,-44 -15,-43 Q-7,-49 -1,-43 L6,-35 Z");
                L(d,"#FAE6BD",3,-6.8,-34,6,-35.2);E(d,"#F8DFAB",-16.8,-42.3,2.5,2.5);d.Pop();
                L(d,coat,5,4,-22,handX,handY);E(d,"#F5D49B",handX,handY,3.5,3.2);
                if(a.Windup>.15) {E(d,"#BCD9E4",handX+.4,handY-3.4,4.1,4);E(d,"#F8FDF7",handX-.4,handY-4.3,3.4,3.1);}
                d.Pop();d.Pop();d.Pop();
            }
        }
        private static void Boot(DrawingContext d,double hip,double top,double foot,double y) {
            L(d,"#503F48",3.4,hip,top,foot,y-1.8);L(d,"#ECD2AD",1.2,foot-1,y-4,foot+1.2,y-4.4);
            E(d,"#613F3A",foot+1.8,y-1.5,4.15,2);E(d,"#A36948",foot+3,y-2.5,1.65,.6);
        }
    }
}
