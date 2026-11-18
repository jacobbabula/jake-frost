using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

namespace Frostpane
{
    internal sealed class DecorationPicker : WrapPanel
    {
        private readonly Dictionary<DecorationKind,Button> tiles=new Dictionary<DecorationKind,Button>();
        private static readonly string[] names={"Christmas tree","String lights","Candle","Red bauble","Gold bauble","Star","Wreath",
            "Stocking","Candy cane","Gift","Bells","Gingerbread","Holly","Santa hat","Snow globe","Hot cocoa","Boat"};
        internal static string NameOf(DecorationKind kind) { return names[(int)kind]; }
        public DecorationPicker(Action<DecorationKind> choose)
        {
            Orientation=Orientation.Horizontal;
            foreach(DecorationKind option in Enum.GetValues(typeof(DecorationKind))) {
                DecorationKind kind=option;
                var content=new StackPanel {Orientation=Orientation.Vertical,HorizontalAlignment=HorizontalAlignment.Center};
                content.Children.Add(new Image{Source=DecorationArt.Icon(kind),Width=34,Height=34});
                content.Children.Add(new TextBlock{Text=NameOf(kind),HorizontalAlignment=HorizontalAlignment.Center,
                    FontSize=11,Margin=new Thickness(0,3,0,0),Foreground=Brushes.MidnightBlue});
                var button=new Button{Content=content,Width=77,Height=62,Margin=new Thickness(2),Padding=new Thickness(1),
                    Background=DecorationArt.Tile,Cursor=Cursors.Hand,ToolTip=NameOf(kind)};
                AutomationProperties.SetName(button,NameOf(kind));
                AutomationProperties.SetAutomationId(button,"Decor"+kind.ToString());
                button.Click+=delegate{SelectKind(kind);if(choose!=null) choose(kind);};
                tiles.Add(kind,button);Children.Add(button);
            }
            SelectKind(DecorationKind.Tree);
        }
        public void SelectKind(DecorationKind kind)
        {
            foreach(var pair in tiles) pair.Value.Background=pair.Key==kind?DecorationArt.Selected:DecorationArt.Tile;
        }
    }

    internal static class DecorationArt
    {
        private static readonly Dictionary<string,Brush> ink=new Dictionary<string,Brush>();
        private static readonly Dictionary<DecorationKind,DrawingImage> pictures=new Dictionary<DecorationKind,DrawingImage>();
        internal static readonly Brush Tile=B("#F0F7FC"), Selected=B("#C7E7FA"), Remove=B("#B64F42");
        internal static readonly Pen Handle=Pen("#53786E",1.6), Cross=Pen("#FFFFFF",1.4);
        internal static readonly Brush Grip=B("#E619454C");
        internal static readonly Pen Edge=Pen("#E4F3FFF7",1.2), Frame=Pen("#A7A8E2D6",1);
        private static Brush B(string hex)
        {
            Brush b;
            if(!ink.TryGetValue(hex,out b)) {b=new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));b.Freeze();ink.Add(hex,b);}
            return b;
        }
        private static Pen Pen(string color,double width)
        {
            var p=new Pen(B(color),width){StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round,LineJoin=PenLineJoin.Round};p.Freeze();return p;
        }
        private static void Path(DrawingContext g,string fill,string commands,string line=null,double thickness=.9)
        { g.DrawGeometry(fill==null?null:B(fill),line==null?null:Pen(line,thickness),Geometry.Parse(commands)); }
        private static void Stroke(DrawingContext g,string color,double thickness,string cmds) {Path(g,null,cmds,color,thickness);}
        private static void Dot(DrawingContext g,string color,double x,double y,double rx,double ry)
        {g.DrawEllipse(B(color),null,new Point(x,y),rx,ry);}
        private static void Enamel(DrawingContext g,double x,double y,double rx,double ry,string highlight,string body,string shade)
        {
            var brush=new RadialGradientBrush {Center=new Point(.44,.37),GradientOrigin=new Point(.32,.22),RadiusX=.72,RadiusY=.74};
            brush.GradientStops.Add(new GradientStop(((SolidColorBrush)B(highlight)).Color,0));
            brush.GradientStops.Add(new GradientStop(((SolidColorBrush)B(body)).Color,.54));
            brush.GradientStops.Add(new GradientStop(((SolidColorBrush)B(shade)).Color,1));
            brush.Freeze();g.DrawEllipse(brush,null,new Point(x,y),rx,ry);
        }
        private static void R(DrawingContext g,string color,double x,double y,double w,double h,double radius)
        {g.DrawRoundedRectangle(B(color),null,new Rect(x,y,w,h),radius,radius);}
        private static void Star(DrawingContext g,string color,double x,double y,double r)
        {
            var shape=new StreamGeometry();
            using(var c=shape.Open()) for(int i=0;i<10;i++) {
                double angle=-Math.PI*.5+i*Math.PI/5, size=i%2==0?r:r*.44;
                var p=new Point(x+Math.Cos(angle)*size,y+Math.Sin(angle)*size);
                if(i==0)c.BeginFigure(p,true,true); else c.LineTo(p,true,false);
            }
            shape.Freeze();g.DrawGeometry(B(color),null,shape);
        }
        internal static DrawingImage Icon(DecorationKind kind)
        {
            DrawingImage img;
            if(pictures.TryGetValue(kind,out img))return img;
            var group=new DrawingGroup();
            using(var g=group.Open()) {
                g.DrawRectangle(Brushes.Transparent,null,new Rect(0,0,44,44));
                Paint(g,kind);
            }
            group.Freeze();img=new DrawingImage(group);img.Freeze();pictures.Add(kind,img);return img;
        }
        private static void Pine(DrawingContext g,double x,double y,double scale)
        {
            g.PushTransform(new TranslateTransform(x,y));g.PushTransform(new ScaleTransform(scale,scale));
            R(g,"#93634C",-2,-1,4,8,.8);
            Path(g,"#32684F","M0,-24 L-7,-12 -4,-13 -11,-4 -7,-5 -15,2 Q0,7 15,2 L7,-5 11,-4 4,-13 7,-12 Z");
            Path(g,"#7EB092","M0,-24 L-2,-14 -6,-12 -3,-13 -8,-6 -2,-10 Z");
            Path(g,"#4F9274","M-13,1 Q-4,1 2,-5 Q6,-1 11,1 Q0,5 -13,2 Z");
            Stroke(g,"#96C8AD",.64,"M-1,-18 L-3,-15 M-2,-13 L-5,-11 M1,-15 L3,-12 M0,-8 L-6,-4 M-4,-5 L-9,-2 M3,-8 L7,-5 M3,-2 L8,0 M-4,-1 L-10,2");
            Path(g,"#E0EEE0","M-10,-3 Q-7,-3 -4,-6 Q-5,-3 -7,-2 Z M2,-13 L6,-10 3,-10 Z M-13,2 Q-10,2 -8,1 Q-9,3 -12,3 Z");
            g.Pop();g.Pop();
        }
        private static void Bauble(DrawingContext g,bool gold)
        {
            Stroke(g,"#D5C391",1.2,"M20,9 C17,3 27,3 24,9");
            R(g,"#A18048",18,8,8,5,1);R(g,"#E9C974",18.5,8,7,1.6,.5);
            Enamel(g,22,25,12.3,13,gold?"#FFF5AE":"#FFAFA1",gold?"#F3B53F":"#EA404D",gold?"#9E5521":"#87183C");
            Path(g,gold?"#FFDD76":"#E87976","M12,20 Q18,12 27,15 Q19,14 15,22 Z");
            Stroke(g,gold?"#FFF0AC":"#FFD3AF",1.1,"M10.5,25 Q16,29 22,25 T33.5,25 M12,29 Q18,32 23,29 T32.7,29");
            Star(g,"#FFEEB1",22,23,2.8);Star(g,"#FFE4A1",29,22,1.3);
            Stroke(g,"#BFFFF1BF",.82,"M16,35 Q20,37 24,36");
            Dot(g,"#FFF2C5",17,18.4,1.6,2.3);Dot(g,"#FFE1AC",19,16.6,.7,.7);
        }
        private static void Paint(DrawingContext g,DecorationKind k)
        {
            switch(k) {
            case DecorationKind.Tree:
                Pine(g,22,33,1.06);Star(g,"#F2CB68",22,7,4.8);
                Stroke(g,"#E8C56D",1.15,"M16,18 Q22,21 28,18 M12,26 Q22,30 33,24");
                Dot(g,"#D9605E",17,21,1.7,1.7);Dot(g,"#E6BC57",25,25,1.7,1.7);Dot(g,"#DB7369",27,31,1.6,1.6);break;
            case DecorationKind.Lights:
                Stroke(g,"#8EAA9E",1.9,"M3,10 Q19,29 41,12");
                string[] bulbs={"#FF5959","#FFD34A","#48EB9A","#41C4FF","#CC7BFF"};
                for(int i=0;i<5;i++){double x=6+i*8,y=13+Math.Sin(i*Math.PI/4)*8;R(g,"#698378",x-1.4,y-1,2.8,5,1);
                    Dot(g,"#42"+bulbs[i].Substring(1),x,y+6,4,5);
                    Enamel(g,x,y+6,2.6,3.7,"#FFFFED",bulbs[i],bulbs[i]);Dot(g,"#FFFFE1",x-.7,y+5.1,.55,1);}
                break;
            case DecorationKind.Candle:
                Dot(g,"#49FFD96E",22,11,7,8);Path(g,"#F5AC45","M22,2 Q30,13 22,17 Q16,15 19,10 Q22,7 22,2 Z");
                Path(g,"#FFECA2","M22,8 Q25,14 22,15 Q20,14 22,8 Z");
                R(g,"#BA977C",15.5,17,13,19,2);R(g,"#EDE3C5",16,17,11,18,2);
                Path(g,"#FFF4DA","M16,17 Q21,15 28,17 L28,21 Q26,24 25,21 L25,19 Q23,18 22,22 Q20,25 20,20 L16,20 Z");
                Dot(g,"#858F78",22,36,12,3);Dot(g,"#AFB99C",22,35.5,10,1.4);break;
            case DecorationKind.RedBauble: Bauble(g,false);break; case DecorationKind.GoldBauble: Bauble(g,true);break;
            case DecorationKind.Star:
                Stroke(g,"#ECD8A0",1.2,"M22,9 Q18,2 23,3 Q27,4 23,8");Star(g,"#D7993E",22,24,17.5);
                Path(g,"#FFE197","M22,7 L22,24 16,19 7,19 17,17 Z M22,24 L36.5,19 26,25 Z M22,24 L22,29 12,37 Z");
                Path(g,"#F6C766","M22,7 L27,17 22,24 Z");break;
            case DecorationKind.Wreath:
                g.DrawEllipse(null,Pen("#315E48",8),new Point(22,23),12,13);
                for(int j=0;j<16;j++){double a=j*Math.PI/8,x=22+12*Math.Cos(a),y=23+13*Math.Sin(a);
                    g.PushTransform(new RotateTransform(j*22.5+38,x,y));Dot(g,j%2==0?"#568F68":"#6DA37E",x,y,2,4);g.Pop();}
                foreach(int ix in new int[]{2,7,11}){double a=ix*.43;Dot(g,"#D3655E",22+12*Math.Cos(a),23+13*Math.Sin(a),1.7,1.7);}
                Path(g,"#C9534D","M21,10 Q11,2 12,9 Q13,14 21,12 L17,18 22,15 25,18 24,12 Q34,14 32,7 Q30,3 22,10 Z");
                Dot(g,"#E28071",22,11,2.2,2.2);break;
            case DecorationKind.Stocking:
                Path(g,"#A53E46","M19,8 L33,9 29,28 Q26,36 14,38 Q6,39 5,33 Q4,27 14,26 L17,25 Z");
                Path(g,"#D8625D","M19,12 L30,13 26,27 Q23,32 17,33 L11,28 16,25 Z");
                Path(g,"#EEE4CC","M17,7 Q25,5 35,8 L33,15 Q25,12 16,14 Z M6,30 Q12,30 15,37 Q8,40 6,36 Q4,33 6,30 Z");
                Star(g,"#F4C977",23,21,4.5);break;
            case DecorationKind.CandyCane:
                Stroke(g,"#B5484C",7.2,"M15,36 L24,12 C27,4 39,11 33,18");
                Stroke(g,"#F6EBD8",6.1,"M15,36 L24,12 C27,4 39,11 33,18");
                Stroke(g,"#CE5551",3.4,"M13.5,31 L18.5,33 M17,23 L21.5,25 M20,15 L25,17 M27,8.4 L28.8,12 M33,12 L36,13.4");
                break;
            case DecorationKind.Gift:
                Path(g,"#A94D4A","M7,20 L35,18 35,35 8,37 Z");Path(g,"#CD6960","M8,20 L30,21 30,36 8,37 Z");
                Path(g,"#E5B95E","M17,20 L22,20 22,36 17,36 Z");
                Path(g,"#E08470","M6,16 L35,15 37,17 36,22 6,23 Z");Path(g,"#E9C778","M16,16 L22,16 22,22 17,22 Z");
                Stroke(g,"#F1CD78",2.3,"M20,16 C6,14 10,5 15,9 Q19,11 20,16 C25,4 34,7 28,13 Q25,16 20,16");
                break;
            case DecorationKind.Bells:
                g.PushTransform(new RotateTransform(-17,15,22));Bell(g,15,25,.85);g.Pop();
                g.PushTransform(new RotateTransform(16,28,21));Bell(g,28,24,1.04);g.Pop();
                Path(g,"#BF514B","M21,11 Q10,4 11,10 Q12,15 21,13 L19,17 23,15 26,17 24,13 Q34,15 33,8 Q30,5 22,11 Z");break;
            case DecorationKind.Gingerbread:
                Path(g,"#BC8255","M17,16 C9,6 20,1 25,6 Q31,11 26,16 L35,15 Q40,16 36,21 L28,24 31,34 Q32,40 26,38 L21,30 16,37 Q10,42 10,35 L14,24 7,22 Q1,17 7,16 Z","#986548");
                Dot(g,"#FFEDCB",18.5,11,1,1);Dot(g,"#FFEDCB",23.5,11,1,1);
                Stroke(g,"#F6DEB7",1.3,"M18,14 Q21,16 24,13 M7,19 L10,20 M33,18 L35,18 M12,33 L15,35 M26,34 L29,32");
                Dot(g,"#B44642",21,21,1.6,1.6);Dot(g,"#F5CE6E",21,25,1.4,1.4);break;
            case DecorationKind.Holly:
                Path(g,"#3A7758","M22,27 Q11,29 6,22 Q10,22 9,18 Q7,17 5,13 Q12,15 15,12 Q15,16 19,16 Q19,22 23,25 Z");
                Path(g,"#6FA581","M21,26 Q20,15 28,5 Q29,10 33,9 Q31,13 36,15 Q32,17 33,21 Q26,22 24,28 Z");
                Stroke(g,"#B4C895",1,"M10,17 L23,27 M29,11 L23,25");
                Dot(g,"#AC424A",21,28,4.2,4.2);Dot(g,"#CE625D",27,28,4,4);Dot(g,"#C74F52",23,33,3.8,3.8);
                Dot(g,"#EFA99A",25.7,26.4,1.1,1.1);break;
            case DecorationKind.SantaHat:
                Path(g,"#B74A4B","M7,30 Q14,14 22,8 Q32,3 37,18 L35,23 Q31,16 28,16 L29,30 Z");
                Path(g,"#D66B63","M9,28 Q17,12 25,9 Q29,8 31,11 Q21,11 17,28 Z");
                Path(g,"#EBE9D7","M6,29 Q17,26 30,28 L31,34 Q17,32 6,36 Q3,34 6,29 Z");
                Dot(g,"#F3F0DB",35,23,4.8,4.8);break;
            case DecorationKind.SnowGlobe:
                Enamel(g,22,20,14,14,"#F2FFFA","#A7DADB","#497786");
                Dot(g,"#AABAD9DB",22,19,12.4,12.4);
                Pine(g,23,24,.45);Path(g,"#E4F0E8","M11,25 Q17,23 21,25 T33,24 Q28,35 17,30 Z");
                Stroke(g,"#ECF7F3",1.7,"M12,19 Q12,12 18,10");Dot(g,"#EAF6F2",28,14,1,1);Dot(g,"#EAF6F2",15,21,.8,.8);
                Path(g,"#93684F","M13,31 L31,31 34,36 Q22,40 10,36 Z");R(g,"#BB8C61",11,34,22,2.4,1);break;
            case DecorationKind.Cocoa:
                g.DrawEllipse(null,Pen("#B4574E",3.5),new Point(32,24),5.6,6.7);
                Path(g,"#B9504A","M7,17 Q18,13 30,17 L28,32 Q25,38 13,36 Q8,34 8,30 Z");
                Dot(g,"#E9B49B",18.5,17,11.5,3.7);Dot(g,"#754A3B",18.5,17,9.7,2.5);
                R(g,"#FAEAD1",13,13,6,4,1);R(g,"#E9D8BF",21,15,5,3,1);Star(g,"#F2D5A5",18,26,4.3);
                Stroke(g,"#EDAA91",1.25,"M10,21 L10.6,28 Q11,32 13,32.5");
                Stroke(g,"#AFDBCBC0",1.25,"M14,12 C11,9 17,8 15,5 M23,12 C21,9 26,8 24,5");break;
            case DecorationKind.Boat:
                Path(g,"#B5704D","M4,28 Q19,33 40,25 L34,34 Q19,39 10,34 Z");
                Stroke(g,"#E8B67B",1.5,"M6,29 Q20,33 38,27");
                Stroke(g,"#977456",1.65,"M22,29 L22,5");
                Path(g,"#E4DED0","M20,8 L20,26 6,25 Q13,18 20,8 Z");
                Path(g,"#C5625B","M24,11 L36,24 24,25 Z");Path(g,"#E6C57C","M22,5 L30,6 22,9 Z");break;
            }
        }
        private static void Bell(DrawingContext g,double x,double y,double scale)
        {
            g.PushTransform(new TranslateTransform(x,y));g.PushTransform(new ScaleTransform(scale,scale));
            Dot(g,"#9A6A36",0,7,2.5,3);
            Path(g,"#DEA64B","M-8,5 Q-4,1 -5,-5 Q-4,-11 0,-12 Q6,-11 6,-5 Q5,1 9,5 Q2,8 -8,5 Z");
            Stroke(g,"#FFE09A",1.7,"M-3,-4 Q-3,-8 0,-9 M-7,5 Q1,7 8,5");g.Pop();g.Pop();
        }
    }
}
