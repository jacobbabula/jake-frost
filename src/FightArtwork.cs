using System;
using System.Windows;
using System.Windows.Media;

namespace Frostpane
{
    internal static partial class VisitorArtwork
    {
        internal static Transform SnowmanPose(FightPlayer a) {
            var matrix=Matrix.Identity;
            matrix.ScaleAt(1+.09*a.Duck+.04*a.Recoil,1-.16*a.Duck-.05*a.Recoil,a.X,a.Y);
            matrix.RotateAt(a.Face*(12*a.Follow-11*a.Windup-6*a.Duck-12*a.Recoil),a.X,a.Y);
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
    }
}
