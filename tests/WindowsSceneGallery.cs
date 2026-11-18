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

    private static SnowScene StormAtNight()
    {
        var scene=Fresh(56);
        var tree=Plant(scene,113,122,2);
        scene.Decorations.Add(new PlacedDecoration{Kind=DecorationKind.Cocoa,X=807,Y=Height,Mount=new LightPin{Support=scene.Banks[0],Anchor=807.0/Width}});
        scene.Weather=WeatherMode.Clouds;scene.SetVisitorSize(VisitorSizeTarget.Yeti,160);
        scene.StartBlizzard();
        for(int i=0;i<360;i++)scene.Step(1.0/60,1,0);
        if(scene.StormCount<165 || !scene.Visitors.Any(v=>v.Wild && v.X>30 && v.X<Width-30) || !scene.Trees.Contains(tree))
            throw new InvalidOperationException("Blizzard did not bring a visible herd and a dense snow front.");
        return scene;
    }


    private static void FightPreview(string path,BitmapSource background)
    {
        var scene=Fresh(21);scene.SnowVolume=0;
        for(int i=0;i<4;i++)scene.Snowmen.Add(new Snowman{X=230+i*141,Y=Height,BaseRadius=22+2*i,MidRadius=19-i,HeadRadius=12,Style=i});
        if(!scene.StartFight())throw new InvalidOperationException("Could not start the hand-built snowman battle.");
        var fight=scene.Fight;var gif=new GifBitmapEncoder();
        int impactFrame=-1;
        for(int i=0;i<92;i++) {
            if(impactFrame<0 && fight.Breaks>0)impactFrame=i+1;
            if(i==impactFrame)Capture(Path.Combine(Path.GetDirectoryName(path),"04-switchback-snowman-impact.png"),
                                      WallpaperScene.Switchback,WallpaperTime.Midday,scene);
            var visual=new DrawingVisual();
            using(var dc=visual.RenderOpen()) {
                dc.PushTransform(new MatrixTransform(.92,0,0,.92,-104,-320));
                dc.DrawImage(background,new Rect(0,0,Width,Height));SnowArtwork.Draw(dc,scene);dc.Pop();
            }
            AppendPreviewFrame(gif,visual,620,186);
            scene.Step(.08,1,0);
        }
        if(fight.Throws<4 || fight.Hits<3 || fight.Breaks<1 || scene.Snowmen.Count>=4)
            throw new InvalidOperationException("Captured battle lacks an actual landed hit and destroyed figure.");
        SavePreview(gif,path);
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

    private static int PaletteBytes(int flags)
    {
        return (flags&128)==0 ? 0 : 3*(2<<(flags&7));
    }

    // WPF writes a graphic-control block per frame, but zeroes its duration even
    // when the source BitmapFrame supplies GIF metadata. Patch those blocks only.
    private static void SavePreview(GifBitmapEncoder encoder,string path)
    {
        byte[] data;
        using(var stream=new MemoryStream()) {encoder.Save(stream);data=stream.ToArray();}
        int start=13+PaletteBytes(data[10]), cursor=start, frames=0;
        while(cursor<data.Length) {
            int marker=data[cursor++];
            if(marker==0x3b)break;
            if(marker==0x21) {
                int extension=data[cursor++];
                if(extension==0xf9 && data[cursor]==4) {
                    data[cursor+2]=8;data[cursor+3]=0;frames++;
                }
            } else if(marker==0x2c) {
                cursor+=9+PaletteBytes(data[cursor+8])+1;
            } else throw new InvalidDataException("Unexpected GIF block.");
            while(data[cursor]!=0)cursor+=1+data[cursor];
            cursor++;
        }
        if(frames!=encoder.Frames.Count)throw new InvalidDataException("GIF timing is missing for one or more frames.");
        using(var output=new BinaryWriter(File.Create(path))) {
            output.Write(data,0,start);
            output.Write(new byte[]{0x21,0xff,11});
            output.Write(System.Text.Encoding.ASCII.GetBytes("NETSCAPE2.0"));
            output.Write(new byte[]{3,1,0,0,0}); // Repeat indefinitely.
            output.Write(data,start,data.Length-start);
        }
    }

    private static BitmapSource DaytimeBackground()
    {
        var wallpaper=new WallpaperArt();
        wallpaper.Configure(WallpaperArt.Load(WallpaperScene.Switchback),WallpaperArt.Load(WallpaperScene.Switchback,true),
                            WallpaperScene.Switchback,WallpaperTime.Midday,true);
        var logicalSize=new Size(Width,Height);
        wallpaper.Measure(logicalSize);wallpaper.Arrange(new Rect(logicalSize));wallpaper.UpdateLayout();
        var background=new RenderTargetBitmap(Width,Height,96,96,PixelFormats.Pbgra32);
        background.Render(wallpaper);background.Freeze();
        return background;
    }

    private static void AppendPreviewFrame(GifBitmapEncoder gif,DrawingVisual tile,int width,int height)
    {
        var frame=new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32);
        frame.Render(tile);
        var metadata=new BitmapMetadata("gif");
        metadata.SetQuery("/grctlext/Delay",(ushort)8);
        gif.Frames.Add(BitmapFrame.Create(frame,null,metadata,null));
    }

    private static void YetiPreview(string path,BitmapSource background)
    {
        var scene=Woodcutting(true);
        var gif=new GifBitmapEncoder();
        for(int i=0;i<55;i++) {
            var tile=new DrawingVisual();
            using(var dc=tile.RenderOpen()) {
                dc.PushTransform(new MatrixTransform(1.6,0,0,1.6,-168*1.6,-357*1.6));
                dc.DrawImage(background,new Rect(0,0,Width,Height));SnowArtwork.Draw(dc,scene);
                dc.Pop();
            }
            AppendPreviewFrame(gif,tile,432,292);
            scene.Step(.08,1,0);
        }
        SavePreview(gif,path);
    }

    private static SnowScene WalkingApproach(int direction)
    {
        var scene=Fresh(76);
        scene.SnowVolume=0;
        scene.DriftDepth=82;
        // The second visitor enters from the other side. Clear the first visit before
        // placing the tree so each camera follows just one genuine approach.
        if(direction<0) scene.SendVisitors(VisitorKind.Yeti);
        scene.Clear();
        var floor=scene.Banks[0];
        for(int i=0;i<floor.Heights.Length;i++) {
            double x=floor.X+floor.Width*i/(floor.Heights.Length-1);
            double distance=direction>0 ? x : Width-x;
            floor.Heights[i]=10+34*Math.Exp(-Math.Pow((distance-225)/92,2));
        }
        floor.Revision++;
        Plant(scene,direction>0 ? 320 : Width-320,95,0);
        scene.SetVisitorSize(VisitorSizeTarget.Yeti,165);
        scene.SendVisitors(VisitorKind.Yeti);
        var yeti=scene.Visitors.Single();
        for(int i=0;i<600;i++) {
            scene.Step(1.0/60,0,0);
            double distance=direction>0 ? yeti.X : Width-yeti.X;
            if(distance>=108 && distance<=115 && !yeti.Met && yeti.Facing==direction) return scene;
        }
        throw new InvalidOperationException("The Yeti did not enter the walking camera from the expected side.");
    }

    private static void DrawWalkingLane(DrawingContext dc,SnowScene scene,BitmapSource background,int direction,double y)
    {
        const double zoom=1.25;
        const int width=456,height=192;
        double x=direction>0 ? 55 : Width-55-width/zoom;
        dc.PushClip(new RectangleGeometry(new Rect(0,y,width,height)));
        dc.PushTransform(new MatrixTransform(zoom,0,0,zoom,-x*zoom,y+height-Height*zoom));
        dc.DrawImage(background,new Rect(0,0,Width,Height));
        SnowArtwork.Draw(dc,scene);
        dc.Pop();dc.Pop();
    }

    private static void WalkingPreview(string path,BitmapSource background)
    {
        var toRight=WalkingApproach(1);
        var toLeft=WalkingApproach(-1);
        var rightWalker=toRight.Visitors.Single();
        var leftWalker=toLeft.Visitors.Single();
        var gif=new GifBitmapEncoder();
        bool bothAtTree=false;
        int carryingSteps=0;
        // The fixed crops keep the drift crest and tree still in the frame.
        // Watch the soles against those landmarks as each visitor climbs and descends.
        for(int i=0;i<98;i++) {
            var tile=new DrawingVisual();
            using(var dc=tile.RenderOpen()) {
                DrawWalkingLane(dc,toRight,background,1,0);
                DrawWalkingLane(dc,toLeft,background,-1,192);
            }
            AppendPreviewFrame(gif,tile,456,384);
            bothAtTree|=rightWalker.Timber!=null && leftWalker.Timber!=null && rightWalker.Met && leftWalker.Met;
            double oldRight=rightWalker.X,oldLeft=leftWalker.X;
            toRight.Step(.08,0,0);
            toLeft.Step(.08,0,0);
            if(rightWalker.CarryingLog && leftWalker.CarryingLog &&
               Math.Abs(rightWalker.X-oldRight)>1 && Math.Abs(leftWalker.X-oldLeft)>1) carryingSteps++;
        }
        if(!bothAtTree || carryingSteps<5) throw new InvalidOperationException("The walk preview missed its arrival, rest or departure.");
        SavePreview(gif,path);
    }

    [STAThread] public static void Main(string[] args)
    {
        string output=Path.GetFullPath(args[0]);Directory.CreateDirectory(output);
        Capture(Path.Combine(output,"01-switchback-yeti.png"),WallpaperScene.Switchback,WallpaperTime.Midday,Woodcutting());
        var storm=StormAtNight();
        Capture(Path.Combine(output,"02-lantern-blizzard.png"),WallpaperScene.Lantern,WallpaperTime.Night,storm);
        var clouds=Fresh(81);clouds.Weather=WeatherMode.Clouds;
        for(int i=0;i<240;i++)clouds.Step(1.0/30,2,20);
        Capture(Path.Combine(output,"03-switchback-clouds.png"),WallpaperScene.Switchback,WallpaperTime.Midday,clouds);
        var background=DaytimeBackground();
        FightPreview(Path.Combine(output,"snowman-battle.gif"),background);
        YetiPreview(Path.Combine(output,"yeti-woodcutting.gif"),background);
        WalkingPreview(Path.Combine(output,"yeti-walk.gif"),background);
    }
}
