using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Windows.Threading;
using Frostpane;
using Forms = System.Windows.Forms;

internal static class WindowsFrameProbe
{
    private static bool HostedWindows {
        get {return Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT")=="github-hosted" &&
            Environment.GetEnvironmentVariable("RUNNER_OS")=="Windows";}
    }

    internal static void ShowTestWindows(string scratch)
    {
        if (!HostedWindows) throw new InvalidOperationException("Use a disposable Windows runner.");
        var forms=new List<Forms.Form>();
        var area=Forms.Screen.PrimaryScreen.WorkingArea;
        for (int i=0; i<24; i++) {
            var window=new Forms.Form {Text="Frame timing fixture", ShowInTaskbar=false,
                StartPosition=Forms.FormStartPosition.Manual, Width=124, Height=75,
                Left=area.Left+22+(i%6)*Math.Max(14,(area.Width-240)/7),
                Top=area.Top+26+(i/6)*Math.Max(14,(area.Height-160)/5)};
            window.Show();forms.Add(window);
        }
        var front=forms[forms.Count-1];
        var timer=new Forms.Timer {Interval=30};
        timer.Tick+=delegate {
            if (!File.Exists(Path.Combine(scratch,"move-window"))) return;
            timer.Stop();front.Left+=16;front.Top+=11;
        };
        timer.Start();
        File.WriteAllText(Path.Combine(scratch,"front-window"),front.Handle.ToInt64().ToString("X",CultureInfo.InvariantCulture));
        Forms.Application.Run();
    }

    private static void Pump()
    {
        var frame=new DispatcherFrame();
        Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle,
            new Action(delegate {frame.Continue=false;}));
        Dispatcher.PushFrame(frame);
    }

    internal static void MeasurePolls(string scratch)
    {
        if (!HostedWindows) return;
        var start=new ProcessStartInfo(Assembly.GetExecutingAssembly().Location,
            "--window-fixture \""+scratch+"\"") {UseShellExecute=false,CreateNoWindow=true};
        using (var fixture=Process.Start(start)) {
            try {
                string ready=Path.Combine(scratch,"front-window");
                var timer=Stopwatch.StartNew();
                while (!File.Exists(ready) && timer.ElapsedMilliseconds<15000 && !fixture.HasExited) Thread.Sleep(20);
                string front=fixture.Id.ToString("X")+"-"+File.ReadAllText(ready)+"/edge";
                var monitor=DesktopMap.Monitors().First(m=>m.Bounds.Contains(Forms.Screen.PrimaryScreen.WorkingArea.Location));
                var overlay=new Overlay(monitor,77);
                var scene=overlay.Surface.Scene;
                scene.Resize(monitor.Work.Width/monitor.Scale,monitor.Work.Height/monitor.Scale);
                // Capture the initial ledges before timing steady-state refreshes.
                overlay.Poll(false,false,false,true,true);Pump();
                var bank=scene.Banks.FirstOrDefault(b=>b.Id==front);
                if (bank==null) throw new Exception("External top window was not observed by Jake Frost.");
                double originalX=bank.X;
                var samples=new double[50];
                for (int i=0;i<samples.Length;i++) {
                    Thread.Sleep(105);Pump();
                    timer.Restart();
                    overlay.Poll(false,false,false,true,true);
                    samples[i]=timer.Elapsed.TotalMilliseconds;
                }
                Array.Sort(samples);
                Console.WriteLine("UI-thread desktop poll with 24 external windows: median {0:F3} ms, p95 {1:F3} ms, p99 {2:F3} ms",
                    samples[25],samples[47],samples[49]);
                File.WriteAllText(Path.Combine(scratch,"move-window"),"1");
                timer.Restart();
                while (Math.Abs(bank.X-originalX)<3 && timer.ElapsedMilliseconds<5000) {
                    Thread.Sleep(30);overlay.Poll(false,false,false,true,true);Pump();
                }
                if (Math.Abs(bank.X-originalX)<3) throw new Exception("Window movement did not update its drift.");
                overlay.Close();
                Console.WriteLine("PASS the live ledge follows the external window after a snapshot changes.");
            } finally {
                if (!fixture.HasExited) {fixture.Kill();fixture.WaitForExit();}
            }
        }
    }

    internal static void CheckMask(SnowScene scene)
    {
        var type=typeof(DesktopGrab).GetNestedType("Mask",BindingFlags.NonPublic);
        var changedMethod=type.GetMethod("HitTargetsChanged",BindingFlags.Instance|BindingFlags.NonPublic);
        if (changedMethod==null) return; // A baseline build invalidates its mask on every tick.
        var mask=Activator.CreateInstance(type,BindingFlags.Instance|BindingFlags.NonPublic,null,new object[]{scene},null);
        var changed=(Func<bool>)Delegate.CreateDelegate(typeof(Func<bool>),mask,changedMethod);
        if (!changed() || changed()) throw new Exception("Unchanged snow banks should retain their hit mask.");
        scene.Banks[0].Revision++;
        if (!changed()) throw new Exception("Changed drift missed an input update.");
        var ball=new SnowBall {X=40,Y=50,Radius=12};scene.Balls.Add(ball);
        if (!changed()) throw new Exception("New snowball missed an input update.");
        ball.X+=.125;
        if (!changed()) throw new Exception("Moving snowball missed an input update.");
        scene.Balls.Clear();
        if (!changed() || changed()) throw new Exception("Removed snowball left a stale target.");
        var tree=new WinterTree {X=55,Y=100,Size=70};scene.Trees.Add(tree);
        if (!changed()) throw new Exception("New tree missed an input update.");
        tree.Angle=31;
        if (!changed()) throw new Exception("Rotated tree missed an input update.");
        tree.Hidden=true;
        if (!changed() || changed()) throw new Exception("Hidden tree left a stale target.");
        Console.WriteLine("PASS unchanged snow keeps the input surface; moving, rotating and removing targets refresh it.");
    }
}
