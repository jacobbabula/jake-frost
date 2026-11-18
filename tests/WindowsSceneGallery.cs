using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Frostpane;

// Capture the shipping wallpaper and desktop renderers at the same logical size.
// No shell, taskbar, account name or real user's desktop enters these screenshots.
internal static class WindowsSceneGallery
{
    private const int Width=960, Height=540;
    private const int OutputWidth=1920, OutputHeight=1080;

    private static SnowScene Fresh(int seed)
    {
        var scene=new SnowScene(seed){Weather=WeatherMode.Snow,SnowVolume=85,VisitorSpeed=1};
        scene.Resize(Width,Height);
        return scene;
    }

    private static WinterTree Plant(SnowScene scene,double x,double size,int palette)
    {
        var tree=new WinterTree {X=x, Y=Height, Size=size, Support=scene.Banks[0],Anchor=x/Width,Palette=palette};
        scene.Trees.Add(tree);
        return tree;
    }

    private static void Lights(SnowScene scene,double x1,double y1,double x2,double y2,double sag,double size,int palette)
    {
        scene.Lights.Add(new LightString{X1=x1,Y1=y1,X2=x2,Y2=y2,Bend=sag,BulbScale=size,Palette=palette});
    }

    private static SnowScene Woodcutting(bool onApproach=false)
    {
        var scene=Fresh(34);
        var target=Plant(scene,308,142,0);
        scene.Decorations.Add(new PlacedDecoration{Kind=DecorationKind.GoldBauble,Tree=target,LocalX=-.10,LocalY=-.44});
        scene.Decorations.Add(new PlacedDecoration{Kind=DecorationKind.Gift,X=772,Y=Height,Mount=new LightPin{Support=scene.Banks[0],Anchor=772.0/Width}});
        scene.Sleds.Add(new WinterSled{X=837,Y=Height,Support=scene.Banks[0]});
        // Two strands follow the two roof pitches of the Switchback signal hut.
        Lights(scene,788,187,832,134,5,1.15,0);
        Lights(scene,832,134,928,174,9,1.15,0);
        scene.SetVisitorSize(VisitorSizeTarget.Yeti,225);
        scene.SendVisitors(VisitorKind.Yeti);
        var yeti=scene.Visitors.Single();
        for(int i=0;i<1500;i++) {
            scene.Step(1.0/60,1,0);
            if(onApproach ? yeti.X>200 : yeti.Met && yeti.Chops==1 && yeti.Wait>.78*SnowScene.ChopBeat) return scene;
        }
        throw new InvalidOperationException("Yeti did not reach its woodcutting pose.");
    }

    private static SnowScene SnowballGame()
    {
        var scene=Fresh(56);
        Plant(scene,113,122,2);
        scene.Decorations.Add(new PlacedDecoration{Kind=DecorationKind.Cocoa,X=807,Y=Height,Mount=new LightPin{Support=scene.Banks[0],Anchor=807.0/Width}});
        scene.SetVisitorSize(VisitorSizeTarget.Train,215);
        if(!scene.StartFight(false)) throw new InvalidOperationException("The visitor snowball game did not begin.");
        for(int i=0;i<800;i++) {
            scene.Step(1.0/60,1,0);
            if(scene.Fight.Throws==1 && scene.Fight.Age>3.56 && scene.FriendlyShots.Count>0) return scene;
        }
        throw new InvalidOperationException("An airborne snowball was never visible.");
    }

    private static void CheckWakingSnowmen()
    {
        var scene=Fresh(80);
        var first=new Snowman{X=355,Y=Height-10,BaseRadius=18,MidRadius=21,HeadRadius=13};
        var second=new Snowman{X=525,Y=Height-10,BaseRadius=26,MidRadius=15,HeadRadius=16};
        scene.Snowmen.Add(first);
        if(!scene.StartFight(true) || scene.Fight.Players[0].Man!=first || scene.Fight.Players[1].Man!=null)
            throw new InvalidOperationException("One hand-built figure must play alongside an elf.");
        scene.Snowmen.Add(second);
        if(!scene.StartFight(true) || !scene.Fight.Players.Any(p=>p.Man==first) || !scene.Fight.Players.Any(p=>p.Man==second))
            throw new InvalidOperationException("Waking two snowmen must animate the existing figures.");
        scene.Balls.Add(new SnowBall{X=first.X-60,Y=first.Y-first.BaseRadius-10,Radius=10,Vx=770,InFlight=true});
        for(int i=0;i<60 && scene.Fight!=null;i++)scene.Step(1.0/60,0,0);
        if(scene.Fight!=null || scene.Snowmen.Contains(first) || !scene.Snowmen.Contains(second))
            throw new InvalidOperationException("A crumbled player must end the match while its partner survives.");
    }

    private static void Capture(string path,WallpaperScene landscape,WallpaperTime time,SnowScene scene)
    {
        var wallpaper=new WallpaperArt { Seconds=scene.Time };
        wallpaper.Configure(WallpaperArt.Load(landscape),WallpaperArt.Load(landscape,true),landscape,time,true);
        var outputSize=new Size(OutputWidth,OutputHeight);
        wallpaper.Measure(outputSize); wallpaper.Arrange(new Rect(outputSize)); wallpaper.UpdateLayout();
        var frame=new RenderTargetBitmap(OutputWidth,OutputHeight,96,96,PixelFormats.Pbgra32);
        frame.Render(wallpaper);
        var effect=new DrawingVisual();
        using(var dc=effect.RenderOpen()) {
            dc.PushTransform(new ScaleTransform((double)OutputWidth/Width,(double)OutputHeight/Height));
            SnowArtwork.Draw(dc,scene);
            dc.Pop();
        }
        frame.Render(effect);
        var png=new PngBitmapEncoder();
        png.Frames.Add(BitmapFrame.Create(frame));
        using(var file=File.Create(path)) png.Save(file);
        Console.WriteLine("Rendered {0} at {1} x {2}",Path.GetFileName(path),frame.PixelWidth,frame.PixelHeight);
    }

    private static void YetiPreview(string path)
    {
        var scene=Woodcutting(true);
        var wallpaper=new WallpaperArt();
        wallpaper.Configure(WallpaperArt.Load(WallpaperScene.Switchback),WallpaperArt.Load(WallpaperScene.Switchback,true),
                            WallpaperScene.Switchback,WallpaperTime.Midday,true);
        var logicalSize=new Size(Width,Height);
        wallpaper.Measure(logicalSize);wallpaper.Arrange(new Rect(logicalSize));wallpaper.UpdateLayout();
        var background=new RenderTargetBitmap(Width,Height,96,96,PixelFormats.Pbgra32);
        background.Render(wallpaper);background.Freeze();
        var gif=new GifBitmapEncoder();
        for(int i=0;i<55;i++) {
            var tile=new DrawingVisual();
            using(var dc=tile.RenderOpen()) {
                dc.PushTransform(new MatrixTransform(1.6,0,0,1.6,-168*1.6,-357*1.6));
                dc.DrawImage(background,new Rect(logicalSize));SnowArtwork.Draw(dc,scene);
                dc.Pop();
            }
            var frame=new RenderTargetBitmap(432,292,96,96,PixelFormats.Pbgra32);
            frame.Render(tile);
            var metadata=new BitmapMetadata("gif");
            metadata.SetQuery("/grctlext/Delay",(ushort)8);
            gif.Frames.Add(BitmapFrame.Create(frame,null,metadata,null));
            scene.Step(.08,1,0);
        }
        using(var file=File.Create(path))gif.Save(file);
    }

    [STAThread] public static void Main(string[] args)
    {
        CheckWakingSnowmen();
        string output=Path.GetFullPath(args[0]);Directory.CreateDirectory(output);
        Capture(Path.Combine(output,"01-switchback-yeti.png"),WallpaperScene.Switchback,WallpaperTime.Midday,Woodcutting());
        var game=SnowballGame();
        Capture(Path.Combine(output,"02-lantern-snowball-game.png"),WallpaperScene.Lantern,WallpaperTime.Night,game);
        int maxThrows=game.Fight.Throws;bool duck=false;
        for(int i=0;game.Fight!=null && i<1800;i++) {
            game.Step(1.0/60,1,0);
            if(game.Fight!=null) {
                maxThrows=Math.Max(maxThrows,game.Fight.Throws);
                duck|=game.Fight.Players.Any(p=>p.Duck>.5);
            }
        }
        if(game.Fight!=null || maxThrows!=6 || !duck)throw new InvalidOperationException("The snowball-game sequence did not finish all its turns.");
        YetiPreview(Path.Combine(output,"yeti-woodcutting.gif"));
    }
}
