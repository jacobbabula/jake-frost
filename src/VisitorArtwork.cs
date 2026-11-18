using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;

namespace Frostpane
{
    internal static partial class VisitorArtwork
    {
        private static readonly Dictionary<string,Brush> inks=new Dictionary<string,Brush>();
        private static readonly Dictionary<string,Geometry> paths=new Dictionary<string,Geometry>();
        private static readonly Dictionary<string,Pen> pens=new Dictionary<string,Pen>();
        private static Brush Ink(string hex) {
            Brush b;if(inks.TryGetValue(hex,out b))return b;b=(Brush)new BrushConverter().ConvertFromString(hex);b.Freeze();inks[hex]=b;return b;
        }
        private static Pen Line(string color,double w) {
            string key=color+w.ToString(CultureInfo.InvariantCulture);Pen p;if(pens.TryGetValue(key,out p))return p;
            p=new Pen(Ink(color),w){StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round,LineJoin=PenLineJoin.Round};p.Freeze();pens[key]=p;return p;
        }
        private static void P(DrawingContext d,string c,string path) {
            Geometry g;if(!paths.TryGetValue(path,out g)){g=Geometry.Parse(path);g.Freeze();paths[path]=g;}d.DrawGeometry(Ink(c),null,g);
        }
        private static void E(DrawingContext d,string color,double x,double y,double rx,double ry) { d.DrawEllipse(Ink(color),null,new Point(x,y),rx,ry); }
        private static void L(DrawingContext d,string color,double w,double x,double y,double xx,double yy) { d.DrawLine(Line(color,w),new Point(x,y),new Point(xx,yy)); }
        private static void R(DrawingContext d,string color,double x,double y,double w,double h,double radius) { d.DrawRoundedRectangle(Ink(color),null,new Rect(x,y,w,h),radius,radius); }
        private static readonly Typeface font=new Typeface("Segoe UI");
        private static readonly ConditionalWeakTable<string,FormattedText> captions=new ConditionalWeakTable<string,FormattedText>();
        private static FormattedText FormatCaption(string s) {
            return new FormattedText(s,CultureInfo.CurrentUICulture,FlowDirection.LeftToRight,font,13,Ink("#F4F8EF"),1.0) { MaxTextWidth=248 };
        }
        private static void Bubble(DrawingContext d,string s,double x,double y,SnowScene scene) {
            if(string.IsNullOrEmpty(s))return;
            var t=captions.GetValue(s,FormatCaption);
            double w=t.Width+20,h=t.Height+12;
            double left=x-w/2,top=y-h;
            if(scene.Banks.Count>0) {
                var floor=scene.Banks[0];
                left=Math.Max(2,Math.Min(left,floor.Width-w-2));
                top=Math.Max(2,Math.Min(top,floor.Y-h-2));
            }
            R(d,"#F1223C41",left,top,w,h,8);d.DrawText(t,new Point(left+10,top+6));
        }
        internal static void Draw(DrawingContext d,SnowScene scene) {
            foreach(WinterVisitor v in scene.Visitors) {
                Matrix pose=Matrix.Identity;
                pose.Scale(v.Scale,v.Scale);
                if(v.Incline!=0) pose.Rotate(v.Incline);
                pose.Translate(v.X,v.Y);
                d.PushTransform(new MatrixTransform(pose));
                if(v.Kind==VisitorKind.Yeti)Yeti(d,v);
                else if(v.Kind==VisitorKind.Train)Train(d,v);
                else if(v.Kind==VisitorKind.Santa)Santa(d,v.Age);
                else FallingSnowman(d,v.Age);
                d.Pop();
                if(v.Kind==VisitorKind.Train && v.Met && v.Wait<=v.Dwell)
                    Bubble(d,v.Caption,v.X,v.Y-62*v.Scale,scene);
            }
            foreach(FriendlyShot ball in scene.FriendlyShots) {
                L(d,"#79BCD5DC",2,ball.X,ball.Y,ball.X-ball.Vx*.035,ball.Y-ball.Vy*.035);
                double r=ball.Radius;
                E(d,"#9FBFCD",ball.X,ball.Y+.55,r,r);E(d,"#F3FAFF",ball.X-r*.12,ball.Y-r*.14,r*.83,r*.83);
            }
            WinterPresent box=scene.DailyPresent;
            if(box!=null) {d.PushTransform(new TranslateTransform(box.X,box.Y));Parcel(d,-12,-21,24,20);d.Pop();}
            if(scene.FortuneTime>0)Bubble(d,scene.FortuneLine,scene.FortuneX,scene.FortuneY,scene);
        }
        private static void Parcel(DrawingContext d,double x,double y,double w,double h) {
            R(d,"#963B3E",x,y,w,h,2);R(d,"#C6544B",x-1,y-1,w+2,5,1.5);R(d,"#E5BE64",x+w*.42,y-1,4,h+1,.5);
            L(d,"#F0D28A",2,x+w*.5,y,x+w*.27,y-4);L(d,"#E9BA5C",2,x+w*.5,y,x+w*.74,y-4);
            L(d,"#BD5850",.8,x+2,y+h*.5,x+w*.40,y+h*.5);L(d,"#D98670",.8,x+w*.72,y+h*.5,x+w*.85,y+h*.5);
            L(d,"#F7DFA5",.8,x+w*.47,y+1,x+w*.47,y+h-1);
        }
        private static void YetiLeg(DrawingContext d,WinterVisitor v,YetiFoot foot,bool near)
        {
            var walk=v.Walk;
            double x=(foot.X-v.X)/v.Scale,y=(foot.Y-v.Y)/v.Scale;
            double hipX=(near?3.5:-3.5)*v.Facing+.65*walk.Weight*v.Facing;
            double hipY=-13-walk.Bob,ankleY=y-3.2;
            double dx=x-hipX,dy=ankleY-hipY,length=Math.Max(.1,Math.Sqrt(dx*dx+dy*dy));
            double bend=Math.Sqrt(Math.Max(0,55-length*length*.25));
            double kneeX=(hipX+x)*.5+dy/length*bend*v.Facing;
            double kneeY=(hipY+ankleY)*.5-dx/length*bend*v.Facing;
            string fur=near?"#CBDBDB":"#90ACB7", shadow=near?"#A8C3C9":"#809FAC";
            L(d,fur,5.7,hipX,hipY,kneeX,kneeY);
            L(d,shadow,4.9,kneeX,kneeY,x,ankleY);
            d.PushTransform(new TranslateTransform(x,y));
            double roll=foot.Planted?0:-Math.Sin(foot.Progress*Math.PI*2)*11*v.Facing;
            d.PushTransform(new RotateTransform(foot.Tilt+roll));
            d.PushTransform(new ScaleTransform(v.Facing,1));
            P(d,near?"#8CAAB6":"#7496A6","M-4.8,-2.5 Q-4.8,-6 -2,-6.3 Q1,-7.3 3,-5 Q7,-4.8 7.2,-2.1 Q7.6,0 3,0 L-2,0 Q-4.7,0 -4.8,-2.5 Z");
            P(d,fur,"M-4,-4 Q-3.4,-7 -1,-7.1 Q1,-7.2 2,-5.9 L4,-6 3.6,-5 Q6,-4.9 6.3,-3.5 Q3.9,-2.9 2,-3.4 L.7,-2.7 -1,-3.2 Q-3,-2.4 -4,-4 Z");
            d.Pop();d.Pop();d.Pop();
        }

        private static void Yeti(DrawingContext d,WinterVisitor v) {
            var walk=v.Walk;
            E(d,"#3557777B",0,-.55,14,1.7);
            YetiLeg(d,v,walk.Far,false);YetiLeg(d,v,walk.Near,true);
            if(Math.Abs(walk.Look)<.999) {
                // A planted pivot briefly shows the in-between silhouette of the two facing poses.
                double right=(walk.Look+1)*.5;
                var turning=new DrawingGroup();
                using(var layer=turning.Open()) {
                    layer.PushOpacity(1-right);YetiBody(layer,v,-1);layer.Pop();
                    layer.PushOpacity(right);YetiBody(layer,v,1);layer.Pop();
                }
                d.DrawDrawing(turning);
            } else YetiBody(d,v,Math.Sign(walk.Look));
        }

        private static void YetiBody(DrawingContext d,WinterVisitor v,int facing) {
            bool stopped=v.Met && v.Wait<=v.Dwell;
            bool chopping=v.Timber!=null && v.Met;
            var walk=v.Walk;
            double beat=(v.Wait/SnowScene.ChopBeat)%1;
            double breathe=stopped?.34*Math.Sin(v.Age*2.5):0;
            double windup=beat<.54 ? -25-78*beat/.54 :
                          beat<.72 ? -103+127*(beat-.54)/.18 : 24-49*(beat-.72)/.28;
            d.PushTransform(new ScaleTransform(facing,1));
            d.PushTransform(new TranslateTransform(.65*walk.Weight,-4.1-walk.Bob+breathe));
            d.PushTransform(new RotateTransform((v.Wild?7.0:1.4)*walk.SpeedRatio+.9*walk.Weight,0,-14));
            // A little ridge of curled fur frames a round muzzle and two short ram horns.
            d.PushTransform(new RotateTransform(-walk.Arm*.82,-11,-27));
            P(d,"#798FA2","M-14,-29 Q-20,-26 -20,-17 Q-22,-12 -17,-12 Q-14,-10 -11,-18 Z");
            d.Pop();
            P(d,"#95AEBB","M-12,-28 Q-19,-22 -18,-12 L-19,-9 -16,-10 Q-13,-3 -8,-4 L-7,-2 -4,-4 Q1,-2 5,-4 L8,-3 9,-5 Q17,-5 17,-16 Q17,-28 9,-30 Z");
            P(d,"#EDF0E7","M-11,-28 Q-17,-20 -15,-13 L-17,-11 -14,-12 Q-14,-6 -9,-7 L-8,-5 -5,-7 Q1,-4 5,-6 L7,-5 9,-7 Q16,-8 15,-18 Q15,-27 8,-29 Z");
            P(d,"#BED4D7","M-10,-15 Q-8,-11 -6,-12 L-4,-10 -3,-12 1,-10 2,-12 4,-11 7,-14 Q2,-7 -4,-9 Q-10,-9 -10,-15 Z");
            P(d,"#A7504A","M-9,-25 Q-12,-20 -14,-17 L-11,-17 -11,-15 Q-6,-17 -4,-23 Z");
            L(d,"#E89472",1.8,-12,-18,-9,-17.5);
            E(d,"#BD6056",1,-26.2,13.1,3.8);E(d,"#E58B71",2,-27,10,1.6);
            d.PushTransform(new RotateTransform(-.8*walk.Weight,1,-28));
            P(d,"#756B70","M-12,-38 Q-20,-40 -18,-48 Q-17,-52 -14,-53 Q-16,-46 -9,-45 Z M10,-41 Q15,-47 12,-52 Q20,-49 18,-43 Q17,-38 12,-37 Z");
            P(d,"#D9AE87","M-13,-41 Q-18,-43 -16,-49 Q-16,-45 -10,-44 Z M12,-42 Q16,-46 14,-49 Q18,-46 16,-42 Z");
            P(d,"#91AFBC","M-16,-40 Q-15,-49 -6,-50 L-2,-55 1,-52 6,-54 7,-51 Q16,-49 18,-39 L20,-36 17,-36 19,-32 16,-32 Q13,-25 5,-25 L3,-23 0,-25 -3,-23 -5,-25 Q-15,-25 -17,-33 L-19,-32 -18,-37 -20,-37 Z");
            P(d,"#F6F3E6","M-15,-40 Q-14,-48 -5,-48 L-2,-52 0,-49 5,-52 5,-49 Q15,-48 16,-39 L18,-37 15,-37 17,-34 14,-34 Q13,-28 5,-27 L2,-25 0,-27 -3,-25 -5,-27 Q-13,-27 -15,-34 L-17,-34 -16,-38 -18,-38 Z");
            E(d,"#A7C6CC",2,-36.7,11.8,7.6);E(d,"#BBDADD",3,-36,10,5.7);
            E(d,"#DDACA5",-6,-34.9,2.5,1.35);E(d,"#DDACA5",11.4,-35.5,2.1,1.2);
            E(d,"#293944",-1.3,-38,1.9,2.4);E(d,"#293944",8.1,-38.6,1.8,2.25);
            E(d,"#FFFFFF",-1.8,-38.9,.68,.82);E(d,"#FFFFFF",7.6,-39.35,.65,.75);
            E(d,"#526674",4,-35.6,2.1,1.25);
            P(d,"#485762","M.3,-33.6 Q3,-31.9 7,-33.7 Q6.4,-30 3.8,-30.3 Q1.5,-30.2 .3,-33.6 Z");
            P(d,"#FFFBE8","M1,-33.3 L3.2,-32.8 2.5,-31.7 Z");
            d.Pop();
            if(v.CarryingLog) {
                d.PushTransform(new RotateTransform(-14,8,-20));
                R(d,"#946543",-16,-27,36,10,4);L(d,"#C99A69",1.3,-12,-24,11,-24);
                E(d,"#E3B579",18,-22,4.8,5);E(d,"#AD7B51",18,-22,2.8,3.4);E(d,"#E3B579",18,-22,1.7,2.1);
                d.Pop();
            }
            double arm=chopping ? windup : v.CarryingLog?-48+walk.Arm*.08:stopped?-89+Math.Sin(v.Wait*5)*14:walk.Arm;
            d.PushTransform(new RotateTransform(arm,10,-21));
            P(d,"#9AB6C0","M8,-24 Q12,-28 15,-22 L19,-16 Q21,-11 17,-10 Q13,-8 10,-15 Z");
            P(d,"#E1EAE4","M9,-24 Q12,-26 14,-21 L17,-17 16,-15 18,-15 Q17,-12 14,-13 Q11,-15 9,-20 Z");
            if(chopping) {
                L(d,"#7C5948",2.9,14,-14,25,-19);
                L(d,"#D4AF82",.95,16,-15,24,-18.6);
                P(d,"#647D8A","M21,-21 L25,-23 Q26,-21 29,-21 L29,-16 Q26,-13 24,-13 L23,-17 20,-18 Z");
                P(d,"#D3E4E3","M27,-20 L29,-21 29,-16 Q26,-13 24,-13 L24,-15 Q27,-17 27,-20 Z");
                E(d,"#AEC8CC",15,-15,2.4,2.4);
            }
            d.Pop();d.Pop();d.Pop();d.Pop();
        }
        private static void Deer(DrawingContext d,double x,double y,double t) {
            d.PushTransform(new TranslateTransform(x,y));
            double step=Math.Sin(t*6)*5;
            L(d,"#6A4A3D",2.2,-5,0,-9+step,8);L(d,"#76513E",2,6,-1,10-step,6);
            E(d,"#BB8D61",0,-2,9,4.6);
            P(d,"#B08258","M4,-4 L10,-13 14,-11 13,-3 8,-1 Z");E(d,"#BB915F",13,-12,4.9,3.6);
            E(d,"#653B30",17,-11,1.6,1.3);E(d,"#263D3F",14,-13,1,1);
            L(d,"#CCB28D",1.25,11,-14,9,-22);L(d,"#CCB28D",1,10,-18,6,-20);L(d,"#CCB28D",1,9,-20,11,-23);
            E(d,"#F2DBAE",-8,-4,2.7,2);L(d,"#AD4F46",1.7,7,-8,11,-6);E(d,"#F0CA7D",9,-6.7,1.1,1.1);
            L(d,"#D6AA79",.8,-4,-4,2,-4.5);d.Pop();
        }
        private static void Santa(DrawingContext d,double t) {
            double y=Math.Sin(t*2)*2;
            L(d,"#C7AC71",.8,9,-7,55,-12+y);L(d,"#C7AC71",.8,55,-12+y,91,-20-y);
            Deer(d,55,-10+y,t);Deer(d,90,-18-y,t+.5);
            E(d,"#A96D45",-25,-10,11,11);P(d,"#8C543D","M-29,-19 L-33,-26 -21,-25 -23,-19 Z");
            E(d,"#B84941",-6,-14,12,12);E(d,"#E8B995",-4,-26,7.4,7.5);
            L(d,"#D99855",1.1,-31,-18,-22,-20);L(d,"#D99855",.7,-29,-16,-32,-12);
            E(d,"#403E38",-1.6,-27.1,.8,.94);E(d,"#F1BD94",2.5,-25.2,1.7,1.35);E(d,"#D48770",-4,-24,1.6,.9);
            P(d,"#EEF0DE","M-11,-27 Q-11,-22 -5,-23 Q0,-21 3,-24 Q4,-17 -2,-14 Q-7,-14 -10,-20 Z");
            P(d,"#D0D9D2","M-7,-19 L-4,-17 -3,-19 -1,-17 1,-19 Q0,-14 -3,-14 Q-6,-16 -7,-19 Z");
            P(d,"#B74942","M-12,-30 Q-13,-44 -23,-36 Q-15,-46 -8,-42 Q-2,-40 2,-31 Z");
            R(d,"#F1E9D6",-12,-32,16,4,2);E(d,"#E4E7D9",-22,-36,2.9,2.9);
            P(d,"#9D373B","M-38,-12 Q-32,-14 -28,-9 L6,-10 Q12,-8 15,-18 L19,-18 Q17,-4 6,-2 L-27,-2 Q-33,-3 -38,-12 Z");
            L(d,"#8B3938",4.5,-5,-14,4,-11);E(d,"#F0E8D1",3.2,-11.7,2.2,2.5);E(d,"#406651",5.7,-12,2.7,2.1);
            L(d,"#E2B860",1.8,-33,-12,8,-10);L(d,"#DEA94F",2,-27,3,12,3);L(d,"#E2B860",1.7,12,3,18,-.5);
            E(d,"#E1B959",17.3,-18.2,2,2);E(d,"#A74340",17.3,-18.3,.85,.85);
            L(d,"#DDA951",1.5,-21,-2,-17,3);L(d,"#DDA951",1.5,1,-2,4,3);
        }
        private static void Train(DrawingContext d,WinterVisitor v) {
            double t=v.Age;
            for(int j=0;j<4;j++) {
                double f=(t*.85+j*.25)%1;E(d,"#74DBE7E3",14-f*24,-32-f*26,2+f*4.5,2+f*3.6);
            }
            R(d,"#8A583D",-77,-21,38,15,2);R(d,"#C5834E",-80,-23,44,4,1);L(d,"#526569",2.2,-39,-8,-28,-9);
            L(d,"#A97248",1,-74,-14,-42,-14);L(d,"#734936",.7,-66,-19,-66,-8);L(d,"#734936",.7,-49,-19,-49,-8);
            if (!v.Met)Parcel(d,-68,-35,17,14);
            R(d,"#315755",-29,-25,44,17,3);R(d,"#C38F53",-32,-10,59,4,1);
            R(d,"#42645A",-20,-39,20,26,2);R(d,"#A44A43",-23,-41,26,4,2);R(d,"#A4BCB0",-17,-36,14,10,1);
            E(d,"#E4AD85",-9,-30,4.2,4.6);P(d,"#416D52","M-15,-32 L-12,-41 -5,-33 Z");R(d,"#B54540",-15,-34,11,2,1);
            P(d,"#F0C4A1","M-12,-31 L-16,-33 -14,-29 Z");E(d,"#324341",-7.7,-30.6,.7,.85);E(d,"#D48F78",-9.7,-29,1,.65);
            E(d,"#E5C57C",-12,-40,1.4,1.4);R(d,"#DBB981",-17,-26,15,1.2,.5);
            R(d,"#4C8277",0,-25,23,13,4);R(d,"#3A514D",10,-32,7,11,1);R(d,"#C18452",8,-34,11,4,1);
            L(d,"#77A294",1.4,3,-22,19,-22);L(d,"#8C734F",1.2,5,-24.5,5,-13);L(d,"#AE9366",1.1,17,-24,17,-13);
            E(d,"#A7C7B3",-24,-17,1.2,1.2);E(d,"#A7C7B3",-18,-17,1.2,1.2);
            E(d,"#F3CB76",23,-21,2.7,3.2);
            foreach(double x in new[]{-70.0,-47.0,-20.0,-2.0,15.0}) {
                E(d,"#3D5151",x,-4,4.4,4.4);E(d,"#D6A55E",x,-4,2.7,2.7);
                L(d,"#684F42",1.3,x,-4,x+Math.Cos(v.Travel/(4.4*v.Scale))*2.6,-4+Math.Sin(v.Travel/(4.4*v.Scale))*2.6);
            }
        }
        private static void FallingSnowman(DrawingContext d,double t) {
            double sway=Math.Sin(t*2)*4;
            d.PushTransform(new TranslateTransform(sway,0));
            P(d,"#AD4E47","M-25,-78 Q0,-103 25,-78 Q19,-82 13,-77 Q6,-82 0,-77 Q-6,-82 -13,-77 Q-19,-82 -25,-78 Z");
            P(d,"#C87560","M-24,-78 Q-12,-90 0,-90 Q-9,-85 -13,-77 Q-19,-81 -24,-78 Z M0,-90 Q10,-86 13,-77 Q7,-81 0,-77 Z");
            L(d,"#CABD98",.85,-24,-78,-6,-43);L(d,"#CABD98",.85,24,-78,6,-43);L(d,"#CABD98",.7,0,-79,0,-45);
            E(d,"#DBE6E5",0,-14,14,14);E(d,"#E7EFEC",0,-34,10,10);E(d,"#F3F5E9",0,-48,7.8,7.8);
            R(d,"#B35A42",-8,-42,16,3.2,1);R(d,"#B07646",-5,-56,11,3,1);R(d,"#344846",-4,-61,8,6,1);
            E(d,"#364A4B",-2,-50,.8,1);E(d,"#364A4B",2,-50,1,1);P(d,"#CC8D43","M3,-48 L12,-47 3,-46 Z");
            E(d,"#485756",1.4,-34,1.1,1.2);E(d,"#485756",1.4,-29.8,1,1.1);
            P(d,"#C46953","M-7,-40 L-3,-40 -6,-32 -9,-33 Z");
            L(d,"#92765A",1.3,-7,-35,-17,-42);L(d,"#92765A",1.1,-15,-40,-14,-44);
            L(d,"#92765A",1.3,8,-35,16,-42);d.Pop();
        }
    }
}
