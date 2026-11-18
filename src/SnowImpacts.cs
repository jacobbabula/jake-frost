using System;

namespace Frostpane
{
    internal sealed partial class SnowScene
    {
        private void ReleaseFigure(double threshold)
        {
            Snowman m = heldMan;
            heldMan = null;
            m.Held = false;
            SnowBank bank = NearbyBank(m.X, m.Y);
            if (bank != null) m.Y = Math.Min(m.Y, bank.Y - bank.HeightAt(m.X));
            double vx, vy;
            ReleaseVelocity(out vx, out vy);
            double speed = Math.Sqrt(vx * vx + vy * vy);
            m.InFlight = speed > threshold;
            double scale = m.InFlight ? Math.Min(1, 920 / speed) : 0;
            m.Vx = vx * scale;
            m.Vy = vy * scale;
        }

        private void AdvanceFigure(Snowman m, double dt)
        {
            m.Vy = Math.Min(850, m.Vy + (m.InFlight ? 565 : 400) * dt);
            int steps = Math.Max(1, (int)Math.Ceiling(Math.Max(Math.Abs(m.Vx), Math.Abs(m.Vy)) * dt / 7));
            double slice = dt / steps;
            for (int i = 0; i < steps; i++)
            {
                double foot = m.Y, surface;
                m.X += m.Vx * slice;
                m.Y += m.Vy * slice;
                SnowBank bank = FindSupport(m.X, foot, m.Y, 5, out surface);
                if (bank == null && m.Vy >= 0 && m.Y >= floor.Y - floor.HeightAt(m.X))
                {
                    bank = floor;
                    surface = floor.Y - floor.HeightAt(m.X);
                }
                if (bank != null)
                {
                    m.Y = surface;
                    if (m.InFlight || m.Vy >= 155) CrumbleFigure(m, m.Vx, m.Vy, bank);
                    else m.Vy = 0;
                    return;
                }
                if (m.InFlight && ((m.Vx < 0 && m.X <= m.BaseRadius) ||
                    (m.Vx > 0 && m.X >= width - m.BaseRadius) || (m.Vy < 0 && m.Y <= m.Height)))
                {
                    CrumbleFigure(m, m.Vx, m.Vy);
                    return;
                }
            }
        }

        // Fragments carry cross-sectional snow area until they touch a real surface.
        // At the particle cap, reuse a cosmetic particle or combine nearby fragments.
        private void AddImpactFragment(Flake f)
        {
            if (Flakes.Count < ParticleLimit + 300) { Flakes.Add(f); return; }
            int nearest = -1;
            double best = double.PositiveInfinity;
            for (int i = Flakes.Count - 1; i >= 0; i--)
            {
                Flake other = Flakes[i];
                if (other.SnowArea == 0) { Flakes[i] = f; return; }
                double dx = f.X - other.X, dy = f.Y - other.Y;
                double distance = dx * dx + dy * dy;
                if (distance < best) { nearest = i; best = distance; }
            }
            if (nearest >= 0) Flakes[nearest].SnowArea += f.SnowArea;
        }

        // Another fragment can raise the crest over this one between physics steps.
        // A descending piece inside that snow must settle before it crosses the ledge.
        private SnowBank BankAroundFragment(double x, double oldY, double y)
        {
            SnowBank first = null;
            double highest = double.PositiveInfinity;
            foreach (SnowBank bank in Banks)
            {
                if (bank.Bare || x < bank.X || x > bank.X + bank.Width ||
                    oldY > bank.Y + .15 || y < bank.Y - bank.MaxDepth) continue;
                double crest = bank.Y - bank.HeightAt(x);
                if (y >= crest && crest < highest) { first = bank; highest = crest; }
            }
            return first;
        }

        private void SettleImpact(SnowBank bank, double x, double area)
        {
            double step = bank.Width / (bank.Heights.Length - 1);
            double radius = Math.Max(step * 1.8, 1.55 * Math.Sqrt(area));
            x = Limit(x, bank.X, bank.X + bank.Width);
            int first = Math.Max(0, (int)Math.Ceiling((x - radius - bank.X) / step));
            int last = Math.Min(bank.Heights.Length - 1, (int)Math.Floor((x + radius - bank.X) / step));
            double totalWeight = 0;
            for (int i = first; i <= last; i++)
            {
                double u = (bank.X + i * step - x) / radius;
                double weight = 1 - u * u;
                totalWeight += weight * weight;
            }
            if (totalWeight <= 0) return;
            double lift = area / (totalWeight * step);
            for (int i = first; i <= last; i++)
            {
                double u = (bank.X + i * step - x) / radius;
                double weight = 1 - u * u;
                bank.Heights[i] = Math.Min(bank.Maximum(i), bank.Heights[i] + lift * weight * weight);
            }
            bank.Revision++;
            LiftRestingObjects(bank, x, radius + step);
        }
    }
}
