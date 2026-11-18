using System;
using System.Collections.Generic;

namespace Frostpane
{
    internal sealed class Ledge
    {
        public string Id;
        public double X, Y, Width;

        public Ledge(string id, double x, double y, double width)
        {
            Id = id; X = x; Y = y; Width = width;
        }
    }

    internal sealed class Flake
    {
        public double X, Y, Radius, Depth, Phase, Angle;
        public bool Crystal;
        internal double FallSpeed, DriftSpeed, Frequency, Spin, ThrowX, ThrowY;
        internal bool Clump, Powder, Wisp;
        internal double Life, Lifetime, SnowArea;
    }

    internal sealed class SnowBank
    {
        public string Id;
        public bool IsFloor;
        public double X, Y, Width;
        public double[] Heights;
        public int Revision;
        internal double MaxDepth;
        internal bool Bare;

        internal double HeightAt(double x)
        {
            return Bare?0:StoredHeightAt(x);
        }

        internal static double Tangent(double before,double after)
        {
            return before*after<=0 ? 0 : 2*before*after/(before+after);
        }

        // Evaluate the same cubic used to paint the drift crest under a resting item.
        internal double PaintedHeightAt(double x)
        {
            if(Bare) return 0;
            int last=Heights.Length-1;
            double p=Math.Max(0,Math.Min(last,(x-X)*last/Width));
            int i=Math.Min(last-1,(int)p);
            double t=p-i, delta=Heights[i+1]-Heights[i];
            if(delta==0) return Heights[i];
            double left=i==0?delta:Tangent(Heights[i]-Heights[i-1],delta);
            double right=i+1==last?delta:Tangent(delta,Heights[i+2]-Heights[i+1]);
            return Heights[i]+t*(left+t*((3-2*t)*delta+(t-2)*left+(t-1)*right));
        }

        internal double StoredHeightAt(double x)
        {
            double p = Math.Max(0, Math.Min(Heights.Length - 1, (x - X) * (Heights.Length - 1) / Width));
            int index = (int)p;
            double a = Heights[index];
            return a + (Heights[Math.Min(index + 1, Heights.Length - 1)] - a) * (p - index);
        }

        internal double Maximum(int index)
        {
            if (IsFloor) return MaxDepth;
            double edge = Math.Min(index, Heights.Length - 1 - index) * Width / (Heights.Length - 1);
            return Math.Min(MaxDepth, 1.6 + edge * 0.65);
        }
    }

    internal sealed class SnowBall
    {
        public double X, Y, Radius, Rotation;
        public bool Held;
        internal double Vx, Vy;
        internal bool InFlight;
        internal SnowBall Below;
        internal int StackSize { get { return Below == null ? 1 : 2; } }
    }

    internal sealed class Snowman
    {
        public double X, Y, BaseRadius, MidRadius, HeadRadius, Facing;
        public int Style;
        public bool Held;
        internal double Vx, Vy;
        internal bool InFlight;
        internal double Height { get { return BaseRadius + .78 * (BaseRadius + 2 * MidRadius + HeadRadius) + HeadRadius; } }
    }

    internal sealed partial class SnowScene
    {
        public readonly List<Flake> Flakes = new List<Flake>();
        public readonly List<SnowBank> Banks = new List<SnowBank>();
        public readonly List<SnowBall> Balls = new List<SnowBall>();
        public readonly List<Snowman> Snowmen = new List<Snowman>();
        public double Time { get; private set; }

        private readonly Random random;
        private readonly Dictionary<string, SnowBank> windows = new Dictionary<string, SnowBank>();
        // Flakes normally travel only a few pixels per physics step. Index the full possible
        // depth of each drift so a flake only checks ledges near its current altitude.
        private const int BandHeight = 64;
        private List<SnowBank>[] supportBands;
        private bool supportBandsDirty = true;
        private double width, height, spawnBudget, relaxationClock, pointerX, pointerY, grabX, grabY;
        private SnowBank floor;
        private SnowBall heldBall;
        private Snowman heldMan;
        private bool initialLedges = true;
        private bool windowSnowEnabled=true;
        internal bool WindowSnowEnabled {
            get { return windowSnowEnabled; }
            set {
                if(value==windowSnowEnabled)return;
                windowSnowEnabled=value;
                foreach(SnowBank bank in Banks) if(!bank.IsFloor) {bank.Bare=!value;bank.Revision++;}
            }
        }

        public SnowScene(int seed) { random = new Random(seed); }

        private static double Limit(double x, double lower, double upper)
        {
            return Math.Max(lower, Math.Min(upper, x));
        }

        private double Between(double a, double b) { return a + (b - a) * random.NextDouble(); }

        public void Resize(double newWidth, double newHeight)
        {
            if (newWidth < 1 || newHeight < 1) return;
            if (Math.Abs(width - newWidth) + Math.Abs(height - newHeight) < .01) return;
            width = newWidth;
            height = newHeight;
            supportBandsDirty = true;
            if (floor == null)
            {
                floor = MakeBank("floor", 0, height, width, true, true);
                Banks.Add(floor);
                int count = (int)(Limit(width * height / 8500, 2, 400) * SnowWeatherScale * Limit(SnowVolume, 0, 400) / 100);
                for (int i = 0; i < count; i++)
                    Flakes.Add(NewFlake(Between(0, width), Between(0, height)));
                PropsResize();
                return;
            }
            Reshape(floor, 0, height, width);
            foreach (SnowBall b in Balls)
            {
                b.X = Limit(b.X, 0, width);
                b.Y = Math.Min(height - b.Radius, b.Y);
            }
            foreach (Snowman m in Snowmen)
            {
                m.X = Limit(m.X, 0, width);
                m.Y = Math.Min(height, m.Y);
            }
            PropsResize();
        }

        private SnowBank MakeBank(string id, double x, double y, double span, bool ground, bool prime)
        {
            SnowBank bank = new SnowBank { Id = id, X = x, Y = y, Width = span, IsFloor = ground,
                Heights = new double[BinCount(span)], MaxDepth = BankDepth(ground),Bare=!ground&&!windowSnowEnabled };
            if (prime && !bank.Bare)
            {
                double offset = Between(0, 6.28);
                for (int i = 0; i < bank.Heights.Length; i++)
                {
                    double u = i * span / (bank.Heights.Length - 1);
                    double ripples = Math.Sin(u * .025 + offset) + .43 * Math.Sin(u * .067 - offset)
                                   + .75 * Math.Sin(u * .009 + offset);
                    bank.Heights[i] = Math.Min(bank.Maximum(i), ground ? 8 + ripples * 2.35 : 2.3 + ripples * .89);
                }
            }
            return bank;
        }

        private static int BinCount(double span) { return (int)Limit(Math.Ceiling(span / 7) + 1, 3, 2000); }

        private static void Reshape(SnowBank bank, double x, double y, double span)
        {
            int bins = BinCount(span);
            if (bins != bank.Heights.Length)
            {
                double[] resized = new double[bins];
                for (int i = 0; i < bins; i++) resized[i] = bank.StoredHeightAt(bank.X + bank.Width * i / (bins - 1));
                bank.Heights = resized;
            }
            bank.X = x;
            bank.Y = y;
            bank.Width = span;
            bank.Revision++;
        }

        public void SetLedges(IList<Ledge> ledges)
        {
            if (floor == null) return;
            HashSet<string> seen = new HashSet<string>();
            if (ledges != null)
            {
                foreach (Ledge edge in ledges)
                {
                    if (edge == null || edge.Id == null || edge.Width < 6 || edge.Y < 1 || edge.Y >= height ||
                        edge.X >= width || edge.X + edge.Width <= 0 || !seen.Add(edge.Id)) continue;
                    double x = Math.Max(0, edge.X);
                    double span = Math.Min(width, edge.X + edge.Width) - x;
                    if (span <= 0) continue;
                    SnowBank bank;
                    if (!windows.TryGetValue(edge.Id, out bank))
                    {
                        bank = MakeBank(edge.Id, x, edge.Y, span, false, initialLedges);
                        windows.Add(edge.Id, bank);
                        Banks.Add(bank);
                        supportBandsDirty = true;
                    }
                    else
                    {
                        double dx = x - bank.X, dy = edge.Y - bank.Y;
                        double changed = Math.Abs(dx) + Math.Abs(dy) + Math.Abs(span - bank.Width);
                        if (changed < .25) continue;
                        if (changed > 4) Shed(bank, Limit(changed / 85.0, .10, .9), dx, dy);
                        Reshape(bank, x, edge.Y, span);
                        supportBandsDirty = true;
                    }
                }
            }
            for (int i = Banks.Count - 1; i >= 0; i--)
            {
                SnowBank bank = Banks[i];
                if (bank.IsFloor || seen.Contains(bank.Id)) continue;
                Shed(bank, 1, 0, 0);
                windows.Remove(bank.Id);
                Banks.RemoveAt(i);
                supportBandsDirty = true;
            }
            if (seen.Count > 0) initialLedges = false;
        }

        private Flake NewFlake(double x, double y)
        {
            double d = random.NextDouble();
            return new Flake {
                X = x, Y = y, Depth = d, Radius = .65 + 2.35 * d * d + Between(0, .35),
                Phase = Between(0, Math.PI * 2), Angle = Between(0, Math.PI * 2),
                Frequency = Between(.65, 1.75), Spin = Between(-.75, .75),
                FallSpeed = Between(17, 31) + d * 49, DriftSpeed = Between(5, 13) + d * 8,
                Crystal = d > .73 && random.NextDouble() < .28
            };
        }

        private void Shed(SnowBank bank, double portion, double dx, double dy)
        {
            if(bank.Bare)return;
            double debt = 0;
            for (int i = 0; i < bank.Heights.Length; i++)
            {
                double old = bank.Heights[i];
                double loss = old * portion;
                bank.Heights[i] -= loss;
                debt += loss;
                if (debt < 4.5 || Flakes.Count >= ParticleLimit + 180) continue;
                debt = 0;
                double x = bank.X + (i + Between(-.4, .4)) * bank.Width / (bank.Heights.Length - 1);
                Flake f = NewFlake(x, bank.Y - old - 1);
                f.Clump = true;
                f.Crystal = false;
                f.Radius = Limit(old * .32 + Between(.6, 1.8), 1.3, 4.4);
                f.ThrowX = Limit(dx * .65, -105, 105) + Between(-15, 15);
                f.ThrowY = Between(-56, -20) + Limit(dy * .25, -40, 30);
                Flakes.Add(f);
            }
            bank.Revision++;
        }

        public void Step(double dt, int intensity, double wind)
        {
            if (floor == null || dt <= 0 || double.IsNaN(dt)) return;
            ApplyDepth();
            if (supportBandsDirty) RebuildSupportBands();
            dt = Math.Min(.12, dt);
            int steps = Math.Max(1, (int)Math.Ceiling(dt * 45));
            for (int i = 0; i < steps; i++) Update(dt / steps, intensity, Limit(wind, -190, 190));
        }

        private void Update(double dt, int intensity, double wind)
        {
            Time += dt;
            WeatherIntensity=intensity;
            StepSky(dt,wind);
            StepWeather(dt,wind);
            double rate = intensity <= 0 ? 0 : intensity == 1 ? 8 : intensity == 2 ? 20 : 40;
            spawnBudget += rate * width / 1300 * dt * SnowWeatherScale * Limit(SnowVolume, 0, 400) / 100;
            int available = (int)spawnBudget;
            spawnBudget -= available;
            int admit = Math.Min(available, ParticleLimit - Flakes.Count);
            for (int i=0;i<admit;i++) Flakes.Add(NewFlake(Between(-8, width + 8), -4));
            double breeze = 7 * Math.Sin(Time * .31) + 4 * Math.Cos(Time * .57) + wind;
            for (int i = Flakes.Count - 1; i >= 0; i--)
            {
                Flake f = Flakes[i];
                double x0 = f.X, y0 = f.Y;
                if (f.Clump)
                {
                    if (f.Powder && (f.Life -= dt) <= 0) { Flakes.RemoveAt(i); continue; }
                    f.ThrowY = Math.Min(360, f.ThrowY + (f.Wisp ? 42 : 290) * dt);
                    f.ThrowX *= 1 - (f.Wisp ? 2.0 : .6) * dt;
                    f.X += (f.ThrowX + breeze * .55) * dt;
                    f.Y += f.ThrowY * dt;
                    if (f.SnowArea > 0 && (f.X < 0 || f.X > width))
                    {
                        f.X = Limit(f.X, 0, width);
                        f.ThrowX *= -.24;
                    }
                }
                else
                {
                    f.X += (breeze * (.5 + .6 * f.Depth) + Math.Sin(Time * f.Frequency + f.Phase) * f.DriftSpeed) * dt;
                    f.Y += (f.FallSpeed + 3 * Math.Cos(Time + f.Phase)) * dt;
                }
                f.Angle += f.Spin * dt;
                if (!f.Clump && f.X < -12) f.X = width + 10;
                if (!f.Clump && f.X > width + 12) f.X = -10;
                if (Math.Abs(f.X - x0) > width * .5) x0 = f.X;
                double sy;
                SnowBank target = FindSupport((x0 + f.X) * .5, y0, f.Y, .15, out sy,true);
                if (f.SnowArea > 0 && target == null && f.ThrowY >= 0)
                    target = BankAroundFragment(f.X, y0, f.Y);
                if (target != null)
                {
                    if (f.SnowArea > 0) SettleImpact(target, f.X, f.SnowArea);
                    else if (!f.Wisp) Deposit(target, f.X, (f.Powder ? .15 : f.Clump ? .8 : .37) * f.Radius + .18);
                    Flakes.RemoveAt(i);
                }
                else if (f.SnowArea > 0 && f.Y >= floor.Y - floor.HeightAt(f.X) && f.ThrowY >= 0)
                {
                    SettleImpact(floor, f.X, f.SnowArea);
                    Flakes.RemoveAt(i);
                }
                else if (f.Y > height + 12 || (f.Clump && (f.X < -12 || f.X > width + 12))) Flakes.RemoveAt(i);
            }
            relaxationClock += dt;
            if (relaxationClock >= .22)
            {
                relaxationClock = 0;
                foreach (SnowBank b in Banks) if(!b.Bare)Relax(b);
            }
            UpdateBalls(dt);
            if (playActive && Tool == PlayTool.Pile) SculptAt(playX, playY, dt * 24);
            PropsStep(dt);
            StepSnowplough(dt);
            UpdateVisitors(dt);
            for (int i = Snowmen.Count - 1; i >= 0; i--)
            {
                Snowman m = Snowmen[i];
                if (m.Held) continue;
                AdvanceFigure(m, dt);
            }
        }

        private void RebuildSupportBands()
        {
            int count = (int)Math.Min(1024, height / BandHeight + 1);
            if (supportBands == null || supportBands.Length != count)
                supportBands = new List<SnowBank>[count];
            else
                foreach (var band in supportBands) if (band != null) band.Clear();
            foreach (var bank in Banks)
            {
                int first = (int)(Math.Max(0, bank.Y - bank.MaxDepth) / BandHeight);
                int last = (int)Math.Min(count - 1, bank.Y / BandHeight);
                for (int i = first; i <= last; i++)
                {
                    if (supportBands[i] == null) supportBands[i] = new List<SnowBank>();
                    supportBands[i].Add(bank);
                }
            }
            supportBandsDirty = false;
        }

        private SnowBank FindSupport(double x, double fromY, double toY, double tolerance, out double surface,bool fallingSnow=false)
        {
            surface = double.PositiveInfinity;
            if (toY < fromY) return null;
            List<SnowBank> candidates = Banks;
            if (fallingSnow)
            {
                int band = (int)(Math.Max(0, fromY - tolerance) / BandHeight);
                // A segment crossing a band boundary checks the original bank list.
                if (band < supportBands.Length && toY + .1 < (band + 1) * BandHeight)
                {
                    candidates = supportBands[band];
                    if (candidates == null) return null;
                }
            }
            SnowBank best = null;
            foreach (SnowBank b in candidates)
            {
                if(fallingSnow && b.Bare)continue;
                if (x < b.X || x > b.X + b.Width || b.Y < fromY - tolerance || b.Y - b.MaxDepth > toY + .1) continue;
                double sy = b.Y - b.HeightAt(x);
                if (sy < fromY - tolerance || sy > toY + .05 || sy >= surface) continue;
                best = b;
                surface = sy;
            }
            return best;
        }

        private static void Deposit(SnowBank bank, double x, double amount)
        {
            if(bank.Bare)return;
            double p = Limit((x - bank.X) * (bank.Heights.Length - 1) / bank.Width, 0, bank.Heights.Length - 1);
            int center = (int)Math.Round(p);
            for (int i = Math.Max(0, center - 1); i <= Math.Min(bank.Heights.Length - 1, center + 1); i++)
                bank.Heights[i] = Math.Min(bank.Maximum(i), bank.Heights[i] + amount * Math.Max(0, 1 - .52 * Math.Abs(i - p)));
            bank.Revision++;
        }

        private static void Relax(SnowBank bank)
        {
            bool changed = false;
            for (int i = 1; i < bank.Heights.Length; i++)
            {
                double diff = bank.Heights[i] - bank.Heights[i - 1];
                if (Math.Abs(diff) < 2.8) continue;
                double moved = (Math.Abs(diff) - 2.4) * .3 * Math.Sign(diff);
                bank.Heights[i] = Math.Min(bank.Maximum(i), bank.Heights[i] - moved);
                bank.Heights[i - 1] = Math.Min(bank.Maximum(i - 1), bank.Heights[i - 1] + moved);
                changed = true;
            }
            if (changed) bank.Revision++;
        }

        private void UpdateBalls(double dt)
        {
            for (int i = Balls.Count - 1; i >= 0; i--)
            {
                // Assembling a figure can consume other balls earlier in the list.
                if (i >= Balls.Count) continue;
                SnowBall b = Balls[i];
                if (b.Held || b.Below != null) continue;
                if (b.InFlight) { AdvanceThrow(b,dt); continue; }
                double foot = b.Y + b.Radius;
                b.Vy = Math.Min(650, b.Vy + 410 * dt);
                b.X = Limit(b.X + b.Vx * dt, b.Radius, Math.Max(b.Radius, width - b.Radius));
                b.Rotation += b.Vx * dt / b.Radius;
                double next = foot + b.Vy * dt;
                double sy;
                SnowBank bank = FindSupport(b.X, foot, next, 5, out sy);
                if ((b.Vy >= 175 || Math.Abs(b.Vx) >= 100) && HitFigure(b)) { BreakBall(b, null); continue; }
                if (b.Vy > 0 && b.Vy < 175 && TryStack(b, foot, bank == null ? next : Math.Min(next, sy), false)) continue;
                if (bank != null || next >= height)
                {
                    b.Y = Math.Min(height, sy) - b.Radius;
                    if (b.Vy >= 175) { BreakBall(b, bank); continue; }
                    if (bank != null && !HasBallAbove(b))
                    {
                        double span = Math.Max(4, b.Radius * .55);
                        double grade = (bank.HeightAt(b.X - span) - bank.HeightAt(b.X + span)) / (2 * span);
                        // Static friction holds a hand-placed ball on shallow irregularities.
                        if (Math.Abs(grade) > .14 || Math.Abs(b.Vx) > 2)
                            b.Vx += Limit(grade, -1, 1) * 255 * dt;
                    }
                    double friction = (14 + .58 * Math.Abs(b.Vx)) * dt;
                    b.Vx = Math.Sign(b.Vx) * Math.Max(0, Math.Abs(b.Vx) - friction);
                    if ((b.X <= b.Radius && b.Vx < 0) || (b.X >= width - b.Radius && b.Vx > 0)) b.Vx = 0;
                    b.Vy = 0;
                }
                else b.Y = next - b.Radius;
            }
            foreach (SnowBall b in Balls)
            {
                if (b.Below == null) continue;
                b.X = b.Below.X;
                b.Y = b.Below.Y - (b.Radius + b.Below.Radius) * .78;
            }
        }

        private bool TryStack(SnowBall b, double prevFoot, double nextFoot, bool byHand)
        {
            SnowBall nearest = null;
            double best = double.PositiveInfinity;
            foreach (SnowBall candidate in Balls)
            {
                if (candidate == b || candidate.Held || candidate.InFlight || HasBallAbove(candidate) || IsBelow(candidate, b)) continue;
                double dx = Math.Abs(b.X - candidate.X);
                double top = candidate.Y - candidate.Radius;
                if (byHand)
                {
                    // Dropping onto any part of a short stack is an intentional placement.
                    // Aim at its visible silhouette; the new ball belongs on top.
                    SnowBall bottom = candidate.Below ?? candidate;
                    double reach = Math.Max(bottom.Radius, candidate.Radius) + b.Radius;
                    if (dx > Math.Max(24, reach * .93) ||
                        b.Y < top - b.Radius - 22 || b.Y > bottom.Y + bottom.Radius + 6) continue;
                }
                else
                {
                    if (dx > Math.Max(8, (b.Radius + candidate.Radius) * .6) ||
                        prevFoot > top + 2 || nextFoot < top) continue;
                }
                double score = dx + Math.Abs(prevFoot - top) * .28;
                if (score < best) { best = score; nearest = candidate; }
            }
            if (nearest == null) return false;
            b.X = nearest.X;
            b.Y = nearest.Y - .78 * (b.Radius + nearest.Radius);
            b.Vx = b.Vy = 0;
            b.Below = nearest;
            if (nearest.StackSize == 2) BuildSnowman(nearest.Below, nearest, b);
            return true;
        }

        private bool HasBallAbove(SnowBall ball)
        {
            foreach (SnowBall b in Balls) if (b.Below == ball) return true;
            return false;
        }

        private static bool IsBelow(SnowBall candidate, SnowBall ball)
        {
            return candidate.Below == ball || (candidate.Below != null && candidate.Below.Below == ball);
        }

        private void BuildSnowman(SnowBall bottom, SnowBall middle, SnowBall top)
        {
            Snowmen.Add(new Snowman { X = bottom.X, Y = bottom.Y + bottom.Radius,
                BaseRadius = bottom.Radius, MidRadius = middle.Radius,
                HeadRadius = top.Radius, Facing = random.Next(2) == 0 ? -1 : 1,
                Style = random.Next(3) });
            Balls.Remove(bottom);
            Balls.Remove(middle);
            Balls.Remove(top);
        }

        private SnowBank NearbyBank(double x, double y)
        {
            SnowBank result = null;
            double best = double.PositiveInfinity;
            foreach (SnowBank bank in Banks)
            {
                if(bank.Bare)continue;
                if (x < bank.X || x > bank.X + bank.Width) continue;
                double sy = bank.Y - bank.HeightAt(x);
                double distance = Math.Abs(y - sy);
                if (y < sy - 30 || y > bank.Y + 8 || distance >= best) continue;
                best = distance;
                result = bank;
            }
            return result;
        }

        private void PickBall(double x,double y)
        {
            for (int i = Balls.Count - 1; i >= 0; i--)
            {
                SnowBall b = Balls[i];
                double dx = x - b.X, dy = y - b.Y;
                if (dx * dx + dy * dy > (b.Radius + 3) * (b.Radius + 3)) continue;
                foreach (SnowBall other in Balls) if (other.Below == b) other.Below = null;
                b.Below = null;
                b.InFlight = false;
                heldBall = b;
                grabX = dx; grabY = dy;
                break;
            }
        }

        public void PointerDown(double x, double y)
        {
            if (floor == null || heldBall != null || heldMan != null) return;
            pointerX = x; pointerY = y;
            PickBall(x,y);
            if (heldBall == null)
            {
                heldMan = DirectSnowman(x,y);
                if (heldMan != null)
                {
                    heldMan.Held = true;
                    heldMan.InFlight = false; heldMan.Vx = heldMan.Vy = 0;
                    grabX = x - heldMan.X; grabY = y - heldMan.Y;
                    return;
                }
                if (Balls.Count + Snowmen.Count >= 70) return;
                heldBall = new SnowBall { X = x, Y = Math.Min(y, height - 9), Radius = 9 };
                Balls.Add(heldBall);
                grabX = 0; grabY = y - heldBall.Y;
            }
            heldBall.Held = true;
            heldBall.Vx = heldBall.Vy = 0;
        }

        public void PointerMove(double x, double y)
        {
            if (heldMan != null)
            {
                heldMan.X = Limit(x - grabX, 0, width);
                heldMan.Y = Limit(y - grabY, 0, height);
            }
            if (heldBall != null)
            {
                SnowBall b = heldBall;
                double dx = x - pointerX;
                SnowBank bank = NearbyBank(x, y);
                if (bank != null && Math.Abs(dx) >= .25)
                {
                    double from = Math.Max(Math.Min(pointerX, x), bank.X);
                    double to = Math.Min(Math.Max(pointerX, x), bank.X + bank.Width);
                    int first = (int)Limit(Math.Floor((from - bank.X) * (bank.Heights.Length - 1) / bank.Width), 0, bank.Heights.Length - 1);
                    int last = (int)Limit(Math.Ceiling((to - bank.X) * (bank.Heights.Length - 1) / bank.Width), first, bank.Heights.Length - 1);
                    double growth = Math.Min(180, Math.Max(0, to - from));
                    double take = Math.Min(2.2, growth * .22);
                    double collected = 0;
                    for (int i = first; i <= last; i++)
                    {
                        double swept = Math.Min(bank.Heights[i], take);
                        bank.Heights[i] -= swept;
                        collected += swept;
                    }
                    b.Radius = Math.Min(31, b.Radius + growth * .034 + collected * .095);
                    bank.Revision++;
                }
                b.Rotation += dx / b.Radius;
                b.X = Limit(x - grabX, b.Radius, Math.Max(b.Radius, width - b.Radius));
                b.Y = Limit(y - grabY, -b.Radius, height - b.Radius);
                if (bank != null) b.Y = Math.Min(b.Y, bank.Y - bank.HeightAt(b.X) - b.Radius);
            }
            pointerX = x; pointerY = y;
        }

        public void PointerUp(double x, double y)
        {
            PointerMove(x, y);
            if (heldMan != null)
            {
                ReleaseFigure(345);
            }
            if (heldBall == null) return;
            SnowBall b = heldBall;
            b.Held = false;
            heldBall = null;
            if (!TryStack(b, b.Y + b.Radius, b.Y + b.Radius, true) && motion.Count >= 2)
            {
                double vx, vy;
                ReleaseVelocity(out vx, out vy);
                if (Math.Abs(vx) > 34) b.Vx = Limit(vx * .63, -410, 410);
            }
        }

        public void Clear()
        {
            EndBlizzard();
            CancelPlay();
            PropsClear();
            ClearWeatherParticles();
            ClearSnowplough();
            ClearVisitors();
            Flakes.Clear();
            Balls.Clear();
            Snowmen.Clear();
            heldMan = null; heldBall = null;
            foreach (SnowBank b in Banks)
            {
                Array.Clear(b.Heights, 0, b.Heights.Length);
                b.Revision++;
            }
            spawnBudget = 0;
            initialLedges = false;
        }
    }
}
