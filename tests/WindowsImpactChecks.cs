using System;
using System.Linq;
using Frostpane;

internal static class WindowsImpactChecks
{
    private const double Width=1440, Height=660, Frame=1.0/60;

    private static SnowScene Empty(Ledge ledge)
    {
        var scene=new SnowScene(170) {SnowVolume=0, DriftDepth=140};
        scene.Resize(Width,Height);
        if(ledge!=null)scene.SetLedges(new[]{ledge});
        scene.Clear();
        scene.Step(Frame,0,0);
        return scene;
    }

    private static void Check(bool value,string failure)
    {
        if(!value)throw new InvalidOperationException(failure);
        Console.WriteLine("PASS "+failure);
    }

    // Integrate the sampled heights over horizontal distance (DIP squared).
    private static double SnowArea(SnowBank bank,double x,double radius)
    {
        double spacing=bank.Width/(bank.Heights.Length-1),total=0;
        for(int i=0;i<bank.Heights.Length;i++)
            if(Math.Abs(bank.X+i*spacing-x)<=radius)total+=bank.Heights[i]*spacing;
        return total;
    }

    private static double AllSnow(SnowBank bank)
    {
        return SnowArea(bank,bank.X+bank.Width/2,bank.Width);
    }

    private static void Settle(SnowScene scene)
    {
        for(int i=0;i<650 && scene.Flakes.Count>0;i++)scene.Step(Frame,0,0);
    }

    private static void ThrowFigure(bool direct)
    {
        var scene=Empty(new Ledge("window",115,418,1180));
        var window=scene.Banks.Single(b=>!b.IsFloor);
        var floor=scene.Banks.Single(b=>b.IsFloor);
        var man=new Snowman {X=385,Y=178,BaseRadius=22,MidRadius=17,HeadRadius=13,Facing=1};
        scene.Snowmen.Add(man);
        double x=man.X,y=man.Y-man.BaseRadius;
        if(direct) {
            Check(scene.DirectDown(x,y),"desktop hit-testing grabs the snowman to throw");
            scene.DirectMove(x+14,y+11);scene.DirectUp(x+31,y+25);
        } else {
            scene.Tool=PlayTool.Throw;
            scene.PlayDown(x,y);scene.Step(.035,0,0);
            scene.PlayMove(x+15,y+11);scene.Step(.035,0,0);scene.PlayUp(x+31,y+25);
        }
        string path=direct?"desktop flick":"Throw tool";
        Check(!man.Held && man.InFlight && man.Vx>80 && man.Vy>30 && scene.Balls.Count==0,
              path+" launches the existing snowman in the release direction");
        double releaseX=man.X;
        scene.Step(Frame,0,0);
        Check(man.X>releaseX && AllSnow(window)==0 && AllSnow(floor)==0,path+" moves the intact figure without adding snow beneath it");
        for(int i=0;i<240 && scene.Snowmen.Contains(man);i++)scene.Step(Frame,0,0);
        Check(!scene.Snowmen.Contains(man) && scene.Flakes.Any(f=>f.Wisp) &&
              scene.Flakes.Any(f=>f.SnowArea>0),path+" crumbles the figure into visible wisps and snow-carrying fragments");
        Settle(scene);
        Check(AllSnow(window)>65 && SnowArea(window,man.X,175)>AllSnow(window)*.55 && AllSnow(floor)<1,
              path+" leaves a local mound on the struck window while the ground below stays clear");
    }

    private static double DropBall(double radius)
    {
        var scene=Empty(new Ledge("shelf",115,412,1180));
        var window=scene.Banks.Single(b=>!b.IsFloor);
        var floor=scene.Banks.Single(b=>b.IsFloor);
        var ball=new SnowBall {X=Width/2,Y=169,Radius=radius};scene.Balls.Add(ball);
        bool premature=false;
        while(scene.Balls.Contains(ball) && scene.Time<4) {
            if(ball.Y+radius<window.Y-2)premature|=AllSnow(window)>0 || AllSnow(floor)>0;
            scene.Step(Frame,0,0);
        }
        Check(!premature && !scene.Balls.Contains(ball),"an unsupported "+radius+" px ball stays intact until its hard landing");
        Settle(scene);
        double total=AllSnow(window),local=SnowArea(window,ball.X,130);
        Console.WriteLine("Drop {0}: total {1:F2}, local {2:F2}, floor {3:F2}, crest {4:F2}",radius,total,local,AllSnow(floor),window.Heights.Max());
        Check(total>20 && local>total*.65 && AllSnow(floor)<1 && window.Heights.Max()>1,
              "the "+radius+" px ball builds up snow close to its landing point");
        return total;
    }

    private static void MidairCollision()
    {
        var scene=Empty(new Ledge("shelf",100,480,1190));
        var window=scene.Banks.Single(b=>!b.IsFloor);
        var floor=scene.Banks.Single(b=>b.IsFloor);
        var man=new Snowman {X=570,Y=183,BaseRadius=18,MidRadius=19,HeadRadius=14,Facing=1};
        scene.Snowmen.Add(man);
        var ball=new SnowBall {X=509,Y=152,Vx=790,InFlight=true,Radius=12};scene.Balls.Add(ball);
        for(int i=0;i<9 && scene.Snowmen.Contains(man);i++)scene.Step(Frame,0,0);
        Check(!scene.Snowmen.Contains(man) && !scene.Balls.Contains(ball) && scene.Flakes.Any(f=>f.SnowArea>0) &&
              scene.Flakes.Any(f=>f.Wisp) && AllSnow(window)==0 && AllSnow(floor)==0,
              "an airborne hit breaks both objects without prematurely depositing on the window below");
        for(int i=0;i<6;i++)scene.Step(Frame,0,0);
        Check(AllSnow(window)==0 && AllSnow(floor)==0,"airborne fragments must reach a surface before they change a bank");
        Settle(scene);
        Check(AllSnow(window)>65 && AllSnow(floor)<1,"fragment snow settles on the first physical shelf it reaches");
    }

    private static void RollOff()
    {
        var scene=Empty(new Ledge("sill",75,270,185));
        var window=scene.Banks.Single(b=>!b.IsFloor);
        var floor=scene.Banks.Single(b=>b.IsFloor);
        var ball=new SnowBall {X=233,Y=256,Radius=14};scene.Balls.Add(ball);
        scene.DirectDown(ball.X,ball.Y);scene.DirectMove(246,256);scene.DirectUp(255,256);
        bool fell=false;
        for(int i=0;i<200 && scene.Balls.Contains(ball);i++) {
            scene.Step(Frame,0,0);
            fell|=ball.X>260 && ball.Y>340 && !ball.InFlight;
        }
        Check(fell && !scene.Balls.Contains(ball),"a gently rolled window ball falls and crumbles without a throw");
        Settle(scene);
        Check(AllSnow(floor)>20 && SnowArea(floor,ball.X,180)>AllSnow(floor)*.55 && AllSnow(window)<1,
              "rolling off deposits snow on the ground below the landing, away from the source window");
    }

    internal static void Run()
    {
        ThrowFigure(true);ThrowFigure(false);MidairCollision();RollOff();
        double small=DropBall(10),big=DropBall(24);
        Check(big>small*2,"larger rolled snowballs leave proportionally more settled snow");
        Console.WriteLine("Settled window cross-section for 10 and 24 px balls: {0:F1}, {1:F1} square DIP",small,big);
    }
}
