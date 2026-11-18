using System;
using System.Diagnostics;
using System.Linq;
using System.Windows.Media;
using Frostpane;

internal static class WinterEventChecks
{
    private const int Width=960,Height=540;
    private static SnowScene Fresh(int seed) {
        var scene=new SnowScene(seed){SnowVolume=85,VisitorSpeed=1};
        scene.Resize(Width,Height);return scene;
    }
    internal static void Run()
    {
        CheckTreeStudio();
        CheckStorm();Console.WriteLine("PASS Blizzard from Off, Rain, Heavy snow and Clouds restores settings, respects paused time, clears visitors and leaves trees intact.");
        CheckWakingSnowmen();Console.WriteLine("PASS Wake restarts and clears a snowman battle without saving guests. User throws remove real opponents.");
        var scene=Fresh(21);scene.Weather=WeatherMode.Clouds;
        var visual=new DrawingVisual();
        using(var dc=visual.RenderOpen())SnowArtwork.Draw(dc,scene);
        scene.Step(.1,2,35);
        if(scene.CloudTravel<=0 || scene.WeatherParticles.Count!=0)throw new Exception("Cloud motion spawned unrelated weather.");
        scene.StartBlizzard();scene.Resize(1920,1080);
        for(int i=0;i<90;i++)scene.Step(1.0/30,2,0);
        using(var dc=visual.RenderOpen())SnowArtwork.Draw(dc,scene);
        var sw=Stopwatch.StartNew();
        for(int i=0;i<150;i++){scene.Step(1.0/30,2,0);using(var dc=visual.RenderOpen())SnowArtwork.Draw(dc,scene);}
        Console.WriteLine("Blizzard at 1920x1080: {0} fluffy flakes, {1:F2} ms per simulated and recorded WPF frame.",scene.StormCount,sw.Elapsed.TotalMilliseconds/150);
        scene.Clear();scene.Weather=WeatherMode.Snow;
        for(int i=0;i<4;i++)scene.Snowmen.Add(new Snowman{X=230+i*141,Y=1080,BaseRadius=22+2*i,MidRadius=19-i,HeadRadius=12,Style=i});
        scene.StartFight();var fight=scene.Fight;
        for(int i=0;i<2200 && scene.Fight!=null;i++)scene.Step(1.0/60,1,0);
        if(scene.Fight!=null || fight.Throws<4 || fight.Hits<3 || fight.Breaks<1 || scene.Snowmen.Count>=4)
            throw new Exception("Snowman battle failed to land shots or end after destruction.");
        Console.WriteLine("PASS Snowman battle finished with {0} throws, {1} actual hits and {2} destroyed snowmen.",fight.Throws,fight.Hits,fight.Breaks);
    }
    private static void CheckTreeStudio()
    {
        var scene=Fresh(42);
        scene.NewTreeTrim=TreeTrim.All;scene.NewTreePalette=1;
        WinterTree a=scene.PlantForEditor(230,Height),b=scene.PlantForEditor(550,Height);
        scene.TreePicked=t=>scene.DesignedTree=t;
        scene.Tool=PlayTool.PickTree;
        scene.PlayDown(b.X,b.Y-b.Size*.35);scene.PlayUp(b.X,b.Y-b.Size*.35);
        if(scene.DesignedTree!=b)throw new Exception("The tree picker selected the wrong desktop tree.");
        b.Trim=TreeTrim.Baubles|TreeTrim.Lights;b.Palette=2;
        if(!scene.HangOrnament(b,DecorationKind.Bells) || !scene.HangOrnament(b,DecorationKind.Star) ||
           !scene.RemoveLastOrnament(b) || scene.Decorations.Count!=1 || scene.Decorations[0].Tree!=b ||
           a.Palette!=1 || a.Trim!=TreeTrim.All)throw new Exception("The tree editor changed another tree or lost its ornament.");
        var restored=Fresh(19);restored.ImportDecorations(scene.ExportDecorations());restored.TwinkleLights=false;
        if(restored.DesignedTree!=restored.Trees[1] || restored.DesignedTree.Palette!=2 ||
           restored.DesignedTree.Trim!=b.Trim || restored.Decorations.Single().Tree!=restored.DesignedTree)
            throw new Exception("The chosen tree, custom trim or ornament did not survive relaunch.");
        scene.PlayDown(790,Height-10);scene.PlayUp(790,Height-10);
        if(scene.Trees.Count!=3 || scene.DesignedTree==b)throw new Exception("Clicking empty snow did not plant and select a tree.");
        Console.WriteLine("PASS tree editor selects a desktop tree, plants on empty snow and restores the exact tree, lights and ornament across a scene reload.");
    }
    private static void CheckStorm()
    {
        foreach(WeatherMode mode in new[]{WeatherMode.Off,WeatherMode.Rain,WeatherMode.HeavySnow,WeatherMode.Clouds}) {
            var scene=Fresh(73);
            scene.Weather=mode;scene.SnowVolume=0;scene.LightningEnabled=true;
            var tree=new WinterTree{X=250,Y=Height,Size=115,Support=scene.Banks[0]};scene.Trees.Add(tree);
            scene.StartBlizzard();
            int largest=0;
            for(int i=0;i<115;i++) {
                scene.Step(.085,1,-60);int before=scene.StormCount;
                scene.Step(0,1,70);
                if(scene.StormCount!=before)throw new InvalidOperationException("Paused storm advanced.");
                largest=Math.Max(largest,scene.StormCount);
            }
            scene.StartBlizzard();
            for(int i=0;i<154;i++)scene.Step(.085,1,20);
            if(largest<175 || largest>900 || scene.BlizzardActive || scene.StormCount!=0 ||
               scene.Weather!=mode || scene.SnowVolume!=0 || !scene.LightningEnabled ||
               scene.Visitors.Any(v=>v.Wild) || !scene.Trees.Contains(tree))
                throw new InvalidOperationException("The event did not finish under the original settings.");
            scene.StartBlizzard();scene.Step(.1,2,0);scene.Clear();
            if(scene.BlizzardActive || scene.StormCount!=0 || scene.Visitors.Any(v=>v.Wild) || scene.Weather!=mode)
                throw new InvalidOperationException("Clear failed to stop the storm.");
        }
    }

    private static void CheckWakingSnowmen()
    {
        var scene=Fresh(80);
        if(scene.StartFight())throw new InvalidOperationException("An empty scene started a battle.");
        var first=new Snowman{X=355,Y=Height-10,BaseRadius=18,MidRadius=21,HeadRadius=13};
        scene.Snowmen.Add(first);
        string original=scene.ExportDecorations();
        if(!scene.StartFight() || scene.Fight.Players.Count<3 || !scene.Fight.Players.Any(p=>p.Man==first))
            throw new InvalidOperationException("A solo builder did not get snowman opponents.");
        if(scene.ExportDecorations()!=original)throw new InvalidOperationException("Temporary players entered the saved scene.");
        int count=scene.Snowmen.Count;
        if(!scene.StartFight() || scene.Snowmen.Count!=count)throw new InvalidOperationException("Restart doubled the cast.");
        scene.Balls.Add(new SnowBall{X=first.X-60,Y=first.Y-first.BaseRadius-10,Radius=10,Vx=770,InFlight=true});
        for(int i=0;i<30 && scene.Snowmen.Contains(first);i++)scene.Step(1.0/60,0,0);
        if(scene.Snowmen.Contains(first))throw new InvalidOperationException("A thrown ball did not crumble an active player.");
        scene.Clear();
        if(scene.Fight!=null || scene.FriendlyShots.Count!=0 || scene.Snowmen.Count!=0)
            throw new InvalidOperationException("Clear left a match or one of its players behind.");
    }
}
