using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using Frostpane;

namespace Frostpane
{
    internal sealed partial class SnowScene
    {
        internal void CheckFlakeContacts()
        {
            foreach (var bank in Banks)
            {
                foreach (double x in new double[] {bank.X, bank.X + bank.Width * .5, bank.X + bank.Width})
                {
                    double crest = bank.Y - bank.HeightAt(x);
                    foreach (double y in new double[] {crest - .05, Math.Floor(crest / 64) * 64 - .15, bank.Y})
                    {
                        const double tolerance = .15;
                        double end = y + 7;
                        SnowBank expected = null;
                        double nearest = Double.PositiveInfinity;
                        foreach (var candidate in Banks)
                        {
                            if (candidate.Bare || x < candidate.X || x > candidate.X + candidate.Width) continue;
                            double surface = candidate.Y - candidate.HeightAt(x);
                            if (surface < y - tolerance || surface > end + .05 || surface >= nearest) continue;
                            nearest = surface;
                            expected = candidate;
                        }
                        double actualY;
                        var actual = FindSupport(x, y, end, tolerance, out actualY, true);
                        if (actual != expected || actualY != nearest)
                            throw new Exception("Flake collision disagrees with the full ledge scan.");
                    }
                }
            }
        }
    }
}

internal static class WindowsPerformance
{
    private const int Frames = 360;
    private const int Trials = 5;

    private static List<Ledge> Ledges(int count, int shift)
    {
        var result = new List<Ledge>();
        for (int i = 0; i < count; i++)
            result.Add(new Ledge("window-" + i, (i * 281 + shift * 5) % 1500,
                120 + (i * 113 + shift) % 835, 400 + (i * 53) % 650));
        return result;
    }

    private static SnowScene Scene(int count, bool heavy)
    {
        var scene = new SnowScene(20261117);
        scene.Weather = heavy ? WeatherMode.HeavySnow : WeatherMode.Snow;
        scene.SnowVolume = heavy ? 220 : 100;
        scene.Resize(1920, 1080);
        scene.SetLedges(Ledges(count, 0));
        return scene;
    }

    private static void MeasurePhysics(int ledges, bool heavy)
    {
        var runs = new double[Trials];
        string fingerprint = null;
        for (int run = -1; run < Trials; run++)
        {
            var scene = Scene(ledges, heavy);
            var watch = Stopwatch.StartNew();
            for (int i = 0; i < Frames; i++)
            {
                if (i == 70) scene.SetLedges(Ledges(ledges / 2, 51));
                if (i == 90) scene.SetLedges(Ledges(ledges, 64));
                if (i == 130) scene.DriftDepth = 140;
                if (i == 175) scene.Resize(1850, 1015);
                if (i == 220) scene.WindowSnowEnabled = false;
                if (i == 255) scene.WindowSnowEnabled = true;
                scene.Step(1.0 / 30, heavy ? 3 : 2, 12);
                if (run == -1 && (i == 1 || i == 70 || i == 90 || i == 130 || i == 175 || i == 220 || i == 255))
                    scene.CheckFlakeContacts();
            }
            watch.Stop();
            if (run >= 0) runs[run] = watch.Elapsed.TotalMilliseconds;
            // Stable totals make it possible to compare the scene before and after an optimization.
            var result = String.Format(System.Globalization.CultureInfo.InvariantCulture,
                "{0}/{1:R}/{2:R}", scene.Flakes.Count, scene.Flakes.Sum(f => f.X + f.Y),
                scene.Banks.Sum(b => b.Heights.Sum()));
            if (fingerprint != null && result != fingerprint) throw new Exception("Replay changed between trials.");
            fingerprint = result;
        }
        Array.Sort(runs);
        Console.WriteLine("Physics {0} ledges, {1}, {2} frames: {3:F2} ms median; replay {4}",
            ledges, heavy ? "heavy" : "normal", Frames, runs[Trials/2], fingerprint);
    }

    private static void MeasureDriftDrawing()
    {
        var scene = Scene(16, false);
        scene.Flakes.Clear();
        var visual = new DrawingVisual();
        var runs = new double[Trials];
        for (int run = -1; run < Trials; run++)
        {
            var watch = Stopwatch.StartNew();
            for (int i = 0; i < Frames; i++)
                using (var context = visual.RenderOpen()) SnowArtwork.Draw(context, scene);
            watch.Stop();
            if (run >= 0) runs[run] = watch.Elapsed.TotalMilliseconds;
        }
        Array.Sort(runs);
        Console.WriteLine("Recording 16 static window drifts in WPF, {0} frames: {1:F2} ms median",
            Frames, runs[Trials/2]);
    }

    private static void MeasureGiftHistory(string scratch)
    {
        var post = new GiftPost(scratch);
        var archive = Path.Combine(scratch, "GiftPost", "Received");
        Directory.CreateDirectory(archive);
        var gift = new GiftPayload { Kind = GiftType.Note, Note = "Test", Sender = "Winter" };
        var epoch = new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        for (int i = 0; i < 200; i++)
        {
            gift.Id = Guid.NewGuid().ToString("N");
            string path = Path.Combine(archive, gift.Id + ".fpgift");
            File.WriteAllText(path, gift.Encode());
            File.SetLastWriteTimeUtc(path, epoch.AddMinutes(i));
        }
        var runs = new double[Trials];
        for (int run = -1; run < Trials; run++)
        {
            var watch = Stopwatch.StartNew();
            for (int i = 0; i < 40; i++)
                if (post.Latest().Id != gift.Id) throw new Exception("Wrong most recent gift.");
            watch.Stop();
            if (run >= 0) runs[run] = watch.Elapsed.TotalMilliseconds;
        }
        Array.Sort(runs);
        Console.WriteLine("Reading latest of 200 gifts, 40 polls: {0:F2} ms median", runs[Trials/2]);
    }

    [STAThread]
    public static void Main(string[] args)
    {
        if(args.Length==2 && args[0]=="--window-fixture") {WindowsFrameProbe.ShowTestWindows(args[1]);return;}
#if CHECK_PLOUGH
        WindowsPloughChecks.Run();
        WindowsImpactChecks.Run();
#endif
        MeasurePhysics(0, false);
        MeasurePhysics(4, false);
        MeasurePhysics(16, true);
        MeasureDriftDrawing();
        MeasureGiftHistory(args[0]);
        WindowsFrameProbe.CheckMask(Scene(16,false));
        WindowsFrameProbe.MeasurePolls(args[0]);
    }
}
