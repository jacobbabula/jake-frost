using System;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;

namespace Frostpane
{
    internal static partial class SnowArtwork
    {
        // A sprite keeps its drawing's original coordinate system. Placement never
        // allocates a transform, even for the small crystals drawn every frame.
        private sealed class Sprite
        {
            private readonly DrawingImage image;
            private readonly Rect bounds;

            internal Sprite(Action<DrawingContext> paint) : this(paint, false) { }

            internal Sprite(Action<DrawingContext> paint, bool mirror)
            {
                DrawingGroup drawing = new DrawingGroup();
                using (DrawingContext dc = drawing.Open()) { paint(dc); }
                if (mirror) drawing.Transform = new ScaleTransform(-1, 1);
                drawing.Freeze();
                bounds = drawing.Bounds;
                image = new DrawingImage(drawing);
                image.Freeze();
            }

            internal void Draw(DrawingContext dc, double x, double y, double scale)
            {
                if (bounds.IsEmpty || scale <= 0) return;
                dc.DrawImage(image, new Rect(x + bounds.X * scale, y + bounds.Y * scale,
                    bounds.Width * scale, bounds.Height * scale));
            }
        }

        private sealed class BankArt
        {
            internal double Width;
            internal double[] Heights;
            internal Sprite Picture;
        }

        private static readonly ConditionalWeakTable<SnowBank, BankArt> BankCache =
            new ConditionalWeakTable<SnowBank, BankArt>();
        private static readonly Brush[] Flurry = {
            Soft("#BDE3EFF7", "#239CB6CA"), Soft("#E5F3F9FC", "#4892B2C9"),
            Soft("#FFF9FDFE", "#82829DB4"), Soft("#FFFFFFFF", "#9E9DB8CA")
        };
        private static readonly Brush BankFill = Vertical("#FFFDFEFF", "#FFF0F7FC", "#EFA7C4D5");
        private static readonly Brush BankCap = Vertical("#56FFFFFF", "#20FFFFFF", "#08FFFFFF");
        private static readonly Brush BankGrain = Ink("#50668AA2");
        private static readonly Brush BankLight = Ink("#B0FFFFFF");
        private static readonly Brush BallFill = SnowMaterial();
        private static readonly Brush Coal = Ink("#344753");
        private static readonly Brush CoalLight = Ink("#9DB4BC");
        private static readonly Pen BankCrest = Stroke("#CBFFFFFF", 0.66);
        private static readonly Pen BaseEdge = Stroke("#AAA2BAC9", 0.65);
        private static readonly Brush Bark = Ink("#795945");
        private static readonly Sprite Snow = new Sprite(DrawSnowSphere);
        private static readonly Sprite Button = new Sprite(DrawButton);
        private static readonly Sprite[][,] Outfits = BuildOutfits();
        private static readonly Sprite[,] Crystals = BuildCrystals();
        private static readonly Sprite[] RollMarks = BuildRollMarks();

        internal static void Draw(DrawingContext dc, SnowScene scene)
        {
            if (scene.Weather==WeatherMode.Off) return;
            if (!scene.HasSnowWeather)
            {
                WinterArt.DrawObjects(dc,scene);
                DrawDecorations(dc,scene);
                DrawWeather(dc,scene);
                VisitorArtwork.Draw(dc,scene);
                return;
            }
            foreach (Flake flake in scene.Flakes)
                if (flake.Depth < .88) DrawFlake(dc, flake);
            foreach (SnowBank bank in scene.Banks)
            {
                if (!bank.IsFloor && scene.IceLevel > 0) WinterArt.DrawIce(dc, bank, scene.IceLevel);
                if (bank.IsFloor || scene.WindowSnowEnabled) DrawBank(dc, bank);
            }
            WinterArt.DrawObjects(dc, scene);
            DrawDecorations(dc,scene);
            DrawSnowplough(dc,scene);
            foreach (Snowman man in scene.Snowmen) DrawSnowman(dc, man);
            foreach (SnowBall ball in scene.Balls)
            {
                if (ball.InFlight) WinterArt.DrawThrow(dc, ball);
                Snow.Draw(dc, ball.X, ball.Y, ball.Radius / 30);
                double turns = ball.Rotation / (2 * Math.PI);
                int frame = (int)((turns - Math.Floor(turns)) * RollMarks.Length);
                RollMarks[frame % RollMarks.Length].Draw(dc, ball.X, ball.Y, ball.Radius / 30);
            }
            foreach (Flake flake in scene.Flakes)
                if (flake.Depth >= .88) DrawFlake(dc, flake);
            VisitorArtwork.Draw(dc,scene);
        }

        private static void DrawFlake(DrawingContext dc, Flake f)
        {
            if (f.Powder)
            {
                WinterArt.DrawPowder(dc, f);
                return;
            }
            int layer = Math.Min(3, Math.Max(0, (int)(f.Depth * 4)));
            if (f.Crystal && f.Radius >= 1.55)
            {
                int angle = (int)(Math.Abs(f.Angle) * 8 / (Math.PI / 3)) % 8;
                Crystals[layer, angle].Draw(dc, f.X, f.Y, f.Radius);
            }
            else dc.DrawEllipse(Flurry[layer], null, new Point(f.X, f.Y), f.Radius, f.Radius * .94);
        }

        private static SolidColorBrush Ink(string color)
        {
            SolidColorBrush brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
            brush.Freeze();
            return brush;
        }

        private static GradientStop Stop(string color, double offset)
        {
            return new GradientStop((Color)ColorConverter.ConvertFromString(color), offset);
        }

        private static Brush Vertical(string top, string middle, string bottom)
        {
            LinearGradientBrush brush = new LinearGradientBrush();
            brush.StartPoint = new Point(.5, 0);
            brush.EndPoint = new Point(.5, 1);
            brush.GradientStops.Add(Stop(top, 0));
            brush.GradientStops.Add(Stop(middle, .46));
            brush.GradientStops.Add(Stop(bottom, 1));
            brush.Freeze();
            return brush;
        }

        private static Brush Soft(string center, string edge)
        {
            RadialGradientBrush brush = new RadialGradientBrush();
            brush.GradientOrigin = new Point(.4, .36);
            brush.GradientStops.Add(Stop(center, 0));
            brush.GradientStops.Add(Stop(center, .42));
            brush.GradientStops.Add(Stop(edge, .84));
            brush.GradientStops.Add(Stop("#0089A9BC", 1));
            brush.Freeze();
            return brush;
        }

        private static Brush SnowMaterial()
        {
            RadialGradientBrush brush = new RadialGradientBrush();
            brush.Center = new Point(.36, .29);
            brush.GradientOrigin = new Point(.31, .22);
            brush.RadiusX = .78;
            brush.RadiusY = .81;
            brush.GradientStops.Add(Stop("#FFFFFFFF", 0));
            brush.GradientStops.Add(Stop("#FFF5FAFC", .42));
            brush.GradientStops.Add(Stop("#FFDFEDF2", .72));
            brush.GradientStops.Add(Stop("#FFA8C3D0", 1));
            brush.Freeze();
            return brush;
        }

        private static Pen Stroke(string color, double width)
        {
            Pen pen = new Pen(Ink(color), width);
            pen.StartLineCap = pen.EndLineCap = PenLineCap.Round;
            pen.LineJoin = PenLineJoin.Round;
            pen.Freeze();
            return pen;
        }

        private static void Path(DrawingContext dc, Brush fill, Pen outline, string commands)
        {
            Geometry path = Geometry.Parse(commands);
            path.Freeze();
            dc.DrawGeometry(fill, outline, path);
        }

        private static void Dot(DrawingContext dc, Brush brush, double x, double y, double rx, double ry)
        {
            dc.DrawEllipse(brush, null, new Point(x, y), rx, ry);
        }

        private static Sprite[,] BuildCrystals()
        {
            Sprite[,] result = new Sprite[4, 8];
            string[] core = { "#88ECF6FF", "#B6F4FAFF", "#E2F5FBFF", "#FEFFFFFF" };
            for (int depth = 0; depth < 4; depth++)
            {
                Pen ice = Stroke(core[depth], .19);
                Pen halo = Stroke("#405A8099", .35);
                for (int index = 0; index < 8; index++)
                {
                    double angle = index * Math.PI / 24;
                    result[depth, index] = new Sprite(delegate(DrawingContext dc) {
                        for (int arm = 0; arm < 6; arm++)
                        {
                            double a = angle + arm * Math.PI / 3;
                            double x = Math.Cos(a), y = Math.Sin(a);
                            dc.DrawLine(halo, new Point(0, 0), new Point(x, y));
                            dc.DrawLine(ice, new Point(0, 0), new Point(x, y));
                            Point fork = new Point(.52 * x, .52 * y);
                            dc.DrawLine(ice, fork, new Point(.73*x - .18*y, .73*y + .18*x));
                            dc.DrawLine(ice, fork, new Point(.73*x + .18*y, .73*y - .18*x));
                        }
                    });
                }
            }
            return result;
        }

        private static void DrawBank(DrawingContext dc, SnowBank bank)
        {
            if (bank.Width < 1 || bank.Heights == null || bank.Heights.Length < 2) return;
            BankArt cache = BankCache.GetOrCreateValue(bank);
            bool update = cache.Heights == null || cache.Heights.Length != bank.Heights.Length ||
                Math.Abs(cache.Width - bank.Width) > .15;
            if (!update)
            {
                for (int i = 0; i < bank.Heights.Length; i++)
                    if (Math.Abs(cache.Heights[i] - bank.Heights[i]) > .20) { update = true; break; }
            }
            if (update)
            {
                if (cache.Heights == null || cache.Heights.Length != bank.Heights.Length)
                    cache.Heights = new double[bank.Heights.Length];
                Array.Copy(bank.Heights, cache.Heights, bank.Heights.Length);
                cache.Width = bank.Width;
                cache.Picture = PaintBank(cache.Heights, bank.Width);
            }
            if (cache.Picture != null) cache.Picture.Draw(dc, bank.X, bank.Y, 1);
        }

        private static Sprite PaintBank(double[] heights, double width)
        {
            double max = 0;
            foreach (double height in heights) max = Math.Max(max, height);
            if (max < .13) return null;
            StreamGeometry shape = BankLine(heights, width, true, 0);
            StreamGeometry crest = BankLine(heights, width, false, 0);
            StreamGeometry top = BankLine(heights, width, true, .69);
            return new Sprite(delegate(DrawingContext dc) {
                dc.DrawGeometry(BankFill, null, shape);
                dc.DrawGeometry(BankCap, null, top);
                dc.PushClip(shape);
                dc.DrawGeometry(null, BankCrest, crest);
                dc.Pop();
                double step = width / (heights.Length - 1);
                // Sparse, stable facets give a thick drift texture without sparkling as it settles.
                for (int i = 1; i < heights.Length - 1; i++)
                {
                    uint grain = unchecked((uint)i * 2654435761u);
                    if (heights[i] < 6 || (grain >> 27) > 8) continue;
                    double h = heights[i];
                    double x = i * step;
                    double y = -h * (.2 + ((grain >> 8) & 255) / 512.0);
                    Dot(dc, BankGrain, x, y, .75, .35);
                    Dot(dc, BankLight, x - .25, y - .55, .68, .31);
                }
            });
        }

        private static StreamGeometry BankLine(double[] h, double width, bool closed, double lower)
        {
            double dx = width / (h.Length - 1);
            StreamGeometry geometry = new StreamGeometry();
            using (StreamGeometryContext g = geometry.Open())
            {
                g.BeginFigure(new Point(0, -h[0]), closed, closed);
                for (int i = 0; i < h.Length - 1; i++)
                {
                    double delta = h[i + 1] - h[i];
                    double left = i == 0 ? delta : SnowBank.Tangent(h[i] - h[i - 1], delta);
                    double right = i + 2 == h.Length ? delta : SnowBank.Tangent(delta, h[i + 2] - h[i + 1]);
                    double x = dx * i;
                    g.BezierTo(new Point(x + dx/3, -h[i] - left/3),
                        new Point(x + 2*dx/3, -h[i+1] + right/3),
                        new Point(x + dx, -h[i+1]), true, true);
                }
                if (closed && lower == 0)
                {
                    g.LineTo(new Point(width, 0), true, false);
                    g.LineTo(new Point(0, 0), true, false);
                }
                else if (closed)
                    for (int i = h.Length - 1; i >= 0; i--)
                        g.LineTo(new Point(i * dx, -h[i] * lower), true, false);
            }
            geometry.Freeze();
            return geometry;
        }

        private static void DrawSnowSphere(DrawingContext dc)
        {
            Path(dc, BallFill, BaseEdge,
                "M -29,1 C -30,-9 -26,-20 -16,-25 C -10,-29 -4,-29 1,-29.5 " +
                "C 13,-29.8 23,-22 27,-13.5 C 31,-5 31,5 27,13 C 24,21 17,26 10,28 " +
                "C 1,31 -10,30 -18,25 C -26,20 -29.5,11 -29,1 Z");
            Path(dc, null, Stroke("#AAFFFFFF", 1.05), "M -23,-12 Q -17,-24 -6,-25");
            Brush shade = Ink("#537CA0B4"), white = Ink("#B2FFFFFF");
            double[] specks = { -21,10, -17,14, -19,12, 13,20, 17,16, 21,13, 18,19, 22,3, 5,23, -24,-2 };
            for (int i = 0; i < specks.Length; i += 2)
            {
                Dot(dc, shade, specks[i], specks[i+1], .66, .43);
                Dot(dc, white, specks[i]-.2, specks[i+1]-.55, .52, .32);
            }
        }

        private static void DrawButton(DrawingContext dc)
        {
            Path(dc, Coal, null, "M -1.5,-2.5 Q .8,-3.1 2.1,-1.7 L 2.4,.5 Q 2,2.5 -.3,2.7 L -2.5,1.4 -2.8,-.8 Z");
            Dot(dc, CoalLight, -.7, -1, .71, .46);
        }

        private static Sprite[] BuildRollMarks()
        {
            Sprite[] marks = new Sprite[32];
            Pen groove = Stroke("#667E9FAC", 1.45), glint = Stroke("#DCFFFFFF", 1.1);
            for (int i = 0; i < marks.Length; i++)
            {
                int index = i;
                marks[i] = new Sprite(delegate(DrawingContext dc) {
                    dc.PushTransform(new RotateTransform(index * 360.0 / marks.Length));
                    Path(dc, null, groove, "M -15,-10 Q -10,-17 -2,-17 M 15,4 Q 17,10 13,14 M -7,14 L -4,15");
                    Path(dc, null, glint, "M -14,-9 Q -10,-15 -5,-15 M 14,4 L 14,7");
                    dc.Pop();
                });
            }
            return marks;
        }

        // Each accessory is drawn once, with both facings cached. Coordinates
        // are relative to a 30-DIP head or torso, so every stack retains its proportions.
        private static Sprite[][,] BuildOutfits()
        {
            Sprite[][,] outfits = new Sprite[3][,];
            for (int style = 0; style < outfits.Length; style++)
            {
                int variant = style;
                outfits[style] = new Sprite[3, 2];
                for (int facing = 0; facing < 2; facing++)
                {
                    bool mirror = facing == 1;
                    outfits[style][0, facing] = new Sprite(delegate(DrawingContext dc) { DrawArms(dc, variant); }, mirror);
                    outfits[style][1, facing] = new Sprite(delegate(DrawingContext dc) { DrawScarf(dc, variant); }, mirror);
                    outfits[style][2, facing] = new Sprite(delegate(DrawingContext dc) { DrawHead(dc, variant); }, mirror);
                }
            }
            return outfits;
        }

        private static void DrawArms(DrawingContext dc, int style)
        {
            Pen twigs = Stroke("#795945", 2.35);
            Pen tips = Stroke("#9A7558", 1.65);
            Path(dc, null, twigs, "M -20,0 Q -31,-5 -39,-12 L -48,-20 M -39,-12 L -39,-22 M -45,-17 L -53,-16");
            if (style == 1)
                Path(dc, null, twigs, "M 19,1 Q 36,-6 42,-23 L 45,-33 M 42,-23 L 51,-28 M 39,-17 L 37,-28");
            else
                Path(dc, null, twigs, "M 18,2 Q 31,-2 42,-8 L 52,-15 M 42,-8 L 45,-19 M 49,-13 L 55,-11");
            Path(dc, null, tips, "M -50,-18 L -54,-21");
            Dot(dc, Bark, -40, -13, 1.5, 1.55);
        }

        private static void DrawScarf(DrawingContext dc, int style)
        {
            string[] dark = { "#8F3546", "#975B29", "#24565D" };
            string[] mid = { "#BB4B53", "#CF8A3F", "#347B7B" };
            string[] light = { "#E88678", "#F4C675", "#82B7A1" };
            Brush main = Vertical(light[style], mid[style], dark[style]);
            Brush ends = Vertical(mid[style], mid[style], dark[style]);
            Pen stripe = Stroke(light[style], 1.25);
            Path(dc, ends, null, "M -9,-1 Q -13,4 -14,10 L -20,22 Q -17,25 -11,25 L -4,12 Q 0,5 -1,1 Z");
            Path(dc, ends, null, "M -2,0 Q 1,6 -2,13 L -2,18 Q 2,20 7,19 Q 6,14 8,7 Q 10,3 7,-1 Z");
            Path(dc, null, stripe, "M -18,19 L -11,22 M -2,14 Q 1,16 7,15");
            Path(dc, null, Stroke(dark[style], 1.45), "M -19,22 L -21,25 M -16,24 L -17,27 M -12,24 L -13,27");
            Path(dc, main, null, "M -24,-7 Q -6,0 13,-5 Q 22,-9 24,-6 Q 26,-3 24,1 Q 13,8 -3,7 Q -18,8 -25,1 Q -27,-3 -24,-7 Z");
            Path(dc, null, stripe, "M -20,-3 Q -12,1 -5,1 M 8,1 Q 16,-.3 20,-3");
        }

        private static void DrawHead(DrawingContext dc, int style)
        {
            Brush cheeks = Ink("#75E7A7A0");
            Dot(dc, cheeks, -12, 7.9, 4.2, 2.25);
            Dot(dc, cheeks, 19.5, 6.9, 2.9, 1.9);
            Dot(dc, Coal, -7.8, -.2, 2.4, 2.8);
            Dot(dc, Coal, 12.8, -1.6, 2.1, 2.5);
            Dot(dc, CoalLight, -8.45, -1.2, .74, .75);
            Dot(dc, CoalLight, 12.2, -2.5, .6, .64);
            Path(dc, Vertical("#FBB975", "#ED8D4A", "#D36B3E"), null,
                "M 1,2.5 Q 2.3,-.2 5.1,.9 L 23,2.5 Q 24.5,3.1 22.3,4 L 5,7.4 Q 1.2,8 1,2.5 Z");
            Path(dc, null, Stroke("#B95734", .8), "M 7.5,4.5 L 8.5,6.4 M 13.6,2 L 13.1,3.6");
            Dot(dc, Coal, -5, 11.8, 1.28, 1.16);
            Dot(dc, Coal, .1, 14.6, 1.29, 1.13);
            Dot(dc, Coal, 5.8, 15.4, 1.33, 1.15);
            Dot(dc, Coal, 11, 14.1, 1.22, 1.07);
            if (style == 0) DrawBeanie(dc);
            else if (style == 1) DrawHat(dc);
            else DrawEarmuffs(dc);
        }

        private static void DrawBeanie(DrawingContext dc)
        {
            Path(dc, Vertical("#6BA09B", "#478083", "#315B68"), null,
                "M -27,-10 Q -30,-29 -18,-38 Q -10,-44 -1,-43 Q 17,-41 23,-26 L 27,-15 Z");
            Pen weave = Stroke("#74C0C6AE", 1.1);
            Path(dc, null, weave, "M -18,-15 Q -20,-32 -9,-39 M -7,-15 Q -8,-32 -4,-39 M 4,-18 Q 4,-32 0,-39 M 15,-19 Q 13,-32 4,-39");
            Path(dc, Vertical("#6E9D9A", "#477B80", "#315D66"), null,
                "M -29,-17 Q -7,-15 23,-23 Q 28,-24 29,-16 L 28,-12 Q 3,-3 -27,-6 Q -31,-7 -29,-17 Z");
            Pen rib = Stroke("#89B4A9", 1.15);
            for (int x = -25; x <= 25; x += 4)
            {
                double t = (x + 25) / 50.0, bottom = -8.2 - 4.5 * t * t;
                dc.DrawLine(rib, new Point(x, bottom - 5.8), new Point(x + .8, bottom));
            }
            Path(dc, Ink("#D7D8BF"), null, "M -13,-44 C -17,-46 -16,-51 -13,-52 Q -13,-56 -9,-55 Q -6,-58 -3,-55 Q 2,-55 1,-51 Q 4,-46 0,-44 Q -4,-40 -9,-42 Z");
            Dot(dc, Ink("#EFF0CD"), -10, -51, 2.6, 1.7);
        }

        private static void DrawHat(DrawingContext dc)
        {
            Path(dc, Vertical("#536373", "#364350", "#23323C"), null,
                "M -22,-23 L -25,-47 Q -25,-51 -21,-52 L 8,-56 Q 12,-56 13,-51 L 20,-22 Z");
            Path(dc, Vertical("#CF9782", "#A66660", "#8D5055"), null,
                "M -22,-27 L 16,-34 L 18.5,-24 L -21,-18 Z");
            Path(dc, Vertical("#5C6C76", "#364550", "#25323C"), null,
                "M -33,-17 Q -28,-22 -8,-24 L 24,-29 Q 30,-30 32,-26 Q 31,-20 6,-15 Q -18,-10 -31,-12 Q -35,-13 -33,-17 Z");
            Path(dc, null, Stroke("#BDCFD3", 1), "M -21,-49 Q -12,-51 5,-53");
            Path(dc, Ink("#819C87"), null, "M -16,-24 Q -28,-27 -27,-35 Q -17,-33 -16,-24 Z M -17,-25 Q -19,-37 -13,-40 Q -9,-33 -17,-25 Z");
            Dot(dc, Ink("#D8836D"), -16, -25, 2.9, 2.7);
        }

        private static void DrawEarmuffs(DrawingContext dc)
        {
            Path(dc, null, Stroke("#664B65", 5.2), "M -28,0 C -29,-34 11,-47 25,-16 Q 28,-8 28,-2");
            Path(dc, null, Stroke("#BA89A0", 1.55), "M -28,-8 C -25,-32 6,-40 18,-25");
            Brush wool = Vertical("#DEA8B2", "#AE778C", "#805A73");
            dc.DrawEllipse(wool, Stroke("#956880", 1.25), new Point(-26, -.3), 7.4, 10.5);
            dc.DrawEllipse(wool, null, new Point(27, -2), 4.7, 8);
            Path(dc, null, Stroke("#E4B7BD", 1.4), "M -30,-4 Q -30,-8 -26,-8 M -27,-5 L -28,-2 M 26,-6 L 25,-4");
        }

        private static void DrawSnowman(DrawingContext dc, Snowman man)
        {
            double b = man.BaseRadius, m = man.MidRadius, h = man.HeadRadius;
            double baseY = man.Y - b;
            double midY = baseY - .78 * (b + m);
            double headY = midY - .78 * (m + h);
            int face = man.Facing < 0 ? 1 : 0;
            Sprite[,] outfit = Outfits[Math.Abs(man.Style % 3)];
            outfit[0, face].Draw(dc, man.X, midY, m / 30);
            Snow.Draw(dc, man.X, baseY, b / 30);
            Snow.Draw(dc, man.X, midY, m / 30);
            Snow.Draw(dc, man.X, headY, h / 30);
            double lean = man.Facing < 0 ? -1 : 1;
            Button.Draw(dc, man.X + .13 * m * lean, midY, m / 30);
            Button.Draw(dc, man.X + .09 * m * lean, midY + .45*m, m / 34);
            outfit[1, face].Draw(dc, man.X, headY + h * .77, Math.Min(h*1.27, m) / 30);
            outfit[2, face].Draw(dc, man.X, headY, h / 30);
        }
    }
}
