using System;
using System.Linq;
using Frostpane;

internal static class WindowsPloughChecks
{
    private const double Width = 840, Height = 400;

    private static void Check(bool ok, string message)
    {
        if (!ok) throw new InvalidOperationException(message);
        Console.WriteLine("PASS " + message);
    }

    private static SnowScene Scene(int direction, int size)
    {
        var scene = new SnowScene(21) { DriftDepth = 140, SnowVolume = 0, VisitorSpeed = 2 };
        scene.Resize(Width, Height);
        if (direction < 0) scene.SendSnowplough();
        scene.Clear();
        scene.SetVisitorSize(VisitorSizeTarget.Snowplow, size);
        scene.Step(1.0 / 60, 0, 0);
        return scene;
    }

    private static void Terrain(int direction, int size)
    {
        var scene = Scene(direction, size);
        var ground = scene.Banks.First(b => b.IsFloor);
        double spacing = ground.Width / (ground.Heights.Length - 1);
        for (int i=0; i<ground.Heights.Length; i++) {
            double x = i * spacing;
            ground.Heights[i] = x>315 && x<475 ? 115 : 10;
        }
        ground.Revision++;
        scene.SendSnowplough();
        Check(scene.Plough != null && scene.Plough.Facing == direction, "requested plough direction " + direction);
        double maxPitch=0, maxUnderTruck=0, maxToeExcess=0;
        bool crossedRidge=false;
        for (int frame=0; scene.Plough!=null && frame<1300; frame++) {
            scene.Step(frame%4==0 ? 0.08 : 1.0/60,0,0);
            var p=scene.Plough;
            if (p==null || p.X<100 || p.X>Width-100) continue;
            maxPitch=Math.Max(maxPitch,Math.Abs(p.Incline));
            double angle=p.Incline*Math.PI/180,tipX=p.X+direction*37*p.Scale*Math.Cos(angle);
            double tipDepth=ground.Y-(p.Y+direction*37*p.Scale*Math.Sin(angle));
            int ahead=direction>0 ? (int)Math.Floor(tipX/spacing)+1 : (int)Math.Ceiling(tipX/spacing)-1;
            if (ahead>=0 && ahead<ground.Heights.Length)
                maxToeExcess=Math.Max(maxToeExcess,ground.Heights[ahead]-tipDepth-0.45*Math.Abs(ahead*spacing-tipX));
            if (p.X>=320 && p.X<=470) {
                crossedRidge=true;
                for (double dx=-17;dx<=12;dx+=3)
                    maxUnderTruck=Math.Max(maxUnderTruck,ground.PaintedHeightAt(p.X+dx*p.Scale*p.Facing));
            }
        }
        Check(scene.Plough==null && crossedRidge && maxPitch<=8.1 && maxUnderTruck<5,
            String.Format("plough clears a tall squared ridge at {0}% size in direction {1} (maximum pitch {2:F2} degrees, snow under chassis {3:F2} px)",size,direction,maxPitch,maxUnderTruck));
        Check(maxToeExcess<1.2,"the first snow ahead of the steel lip forms a sloping mound rather than a cliff");
        Check(ground.HeightAt(180)<4 && ground.HeightAt(405)<4 && ground.HeightAt(625)<4,
              "an entire pass clears both a flat snow blanket and the piled ridge");
    }

    private static void Objects(int dir)
    {
        var scene = Scene(dir,100);
        var ground = scene.Banks.First(b => b.IsFloor);
        Func<double,double> x = distance => dir>0 ? distance : Width-distance;
        var shelf=new Ledge("upper",100,150,640);scene.SetLedges(new[]{shelf});
        var ledge=scene.Banks.First(b=>!b.IsFloor);
        var ball=new SnowBall{X=x(170),Y=Height-12,Radius=12};scene.Balls.Add(ball);
        var figure=new Snowman{X=x(255),Y=Height,BaseRadius=16,MidRadius=12,HeadRadius=8,Facing=1};scene.Snowmen.Add(figure);
        var sled=new WinterSled{X=x(330),Y=Height,Support=ground};scene.Sleds.Add(sled);
        var tree=new WinterTree{X=x(402),Y=Height,Size=65,Support=ground,Anchor=x(402)/Width};scene.Trees.Add(tree);
        var ornament=new PlacedDecoration{Kind=DecorationKind.RedBauble,Tree=tree,LocalX=.1,LocalY=-.4};scene.Decorations.Add(ornament);
        var gift=new PlacedDecoration{Kind=DecorationKind.Gift,X=x(480),Mount=new LightPin{Support=ground,Anchor=x(480)/Width}};scene.Decorations.Add(gift);
        var overhead=new WinterTree{X=x(380),Y=ledge.Y,Size=40,Support=ledge,Anchor=(x(380)-ledge.X)/ledge.Width};scene.Trees.Add(overhead);
        var strand=new LightString{X1=x(565),X2=x(605),Y1=Height-5,Y2=Height-5,Bend=0};scene.Lights.Add(strand);
        var overheadWire=new LightString{X1=x(280),X2=x(345),Y1=80,Y2=82,Bend=3};scene.Lights.Add(overheadWire);
        scene.DailyPresent=new WinterPresent{X=x(700),Y=Height};
        scene.SendSnowplough();
        bool checkedSave=false;
        for (int i=0;i<1200;i++) {
            scene.Step(1.0/60,0,0);
            if(!checkedSave && scene.Lights.Contains(strand) && (dir>0 ? strand.X2>Width : strand.X1<0)) {
                var restored=Scene(dir,100);
                restored.ImportDecorations(scene.ExportDecorations());
                checkedSave=restored.Lights.Count==1 && restored.Lights[0].Y1<150;
            }
        }
        Check(checkedSave,"exiting mid-sweep cannot restore a clipped strand in a corner");
        Check(scene.Plough==null,"vehicle completes its pass with loose objects on the ground");
        Check(scene.Balls.Contains(ball) && dir*(ball.X-x(170))>12,"loose snowball moves in blade direction");
        Check(scene.Snowmen.Contains(figure) && dir*(figure.X-x(255))>12,"built snowman is pushed and survives");
        Check(scene.Sleds.Contains(sled) && dir*(sled.X-x(330))>12,"sled is pushed and survives");
        Check(!scene.Trees.Contains(tree) && !scene.Decorations.Contains(ornament) && dir*(tree.X-x(402))>12,
              "a contacted tree and its ornaments leave the desktop together");
        Check(!scene.Decorations.Contains(gift) && dir*(gift.X-x(480))>12,"a loose decoration clears the screen");
        Check(!scene.Lights.Contains(strand) && (dir>0 ? Math.Min(strand.X1,strand.X2)>Width : Math.Max(strand.X1,strand.X2)<0),
              "both ends of a low light strand move fully offscreen");
        Check(scene.DailyPresent!=null && dir*(scene.DailyPresent.X-x(700))>8,"Santa's unopened present is pushed intact");
        Check(scene.Trees.Contains(overhead) && scene.Lights.Contains(overheadWire) &&
              Math.Abs(overhead.X-x(380))<0.1 && Math.Abs(overheadWire.X1-Math.Min(x(280),x(345)))<0.1 &&
              Math.Abs(overheadWire.X2-Math.Max(x(280),x(345)))<0.1,"a ledge tree and overhead lights stay in place");
        Check(new[]{ball.X,figure.X,sled.X,scene.DailyPresent.X}.All(p=>p>=0 && p<=Width),"pushed pieces remain accessible at the edge");
    }

    private static void SnowPhysics()
    {
        var scene=Scene(1,100);
        var bottom=new SnowBall{X=400,Y=Height-13,Radius=13};
        scene.Balls.Add(bottom);
        foreach(double r in new[]{23.0,17.0}) {
            var ball=new SnowBall{X=200,Y=180,Radius=r};
            scene.Balls.Add(ball);
            scene.PointerDown(ball.X,ball.Y);
            scene.PointerUp(bottom.X,bottom.Y-25);
        }
        var man=scene.Snowmen.Single();
        Check(scene.Balls.Count==0 && man.BaseRadius==13 && man.MidRadius==23 && man.HeadRadius==17,
              "stacking preserves all three placed radii and their order");
        var restored=Scene(1,100);
        restored.ImportDecorations(scene.ExportDecorations());
        var saved=restored.Snowmen.Single();
        Check(saved.BaseRadius==13 && saved.MidRadius==23 && saved.HeadRadius==17,"hand-built proportions round-trip through scene storage");
        var received=GiftPayload.DecodeGift(new GiftPayload{Kind=GiftType.Snowman,Size=13,Mid=23,Head=17}.Encode());
        Check(received.Size==13 && received.Mid==23 && received.Head==17,"gift decoding accepts independently sized snowman balls");

        double midY=man.Y-man.BaseRadius-.78*(man.BaseRadius+man.MidRadius);
        scene.Balls.Add(new SnowBall{X=man.X-65,Y=midY,Radius=9,Vx=760,InFlight=true});
        for(int i=0;i<10 && scene.Snowmen.Count>0;i++)scene.Step(.017,0,0);
        Check(scene.Snowmen.Count==0 && scene.Balls.Count==0 && scene.Flakes.Any(f=>f.Powder) &&
              scene.Flakes.Any(f=>f.Clump && !f.Powder && f.ThrowX>50),
              "a thrown ball knocks apart a snowman with powder and directional fragments");

        scene=Scene(1,100);
        man=new Snowman{X=200,Y=Height-8,BaseRadius=14,MidRadius=12,HeadRadius=10};scene.Snowmen.Add(man);
        for(int i=0;i<60;i++)scene.Step(.017,0,0);
        Check(scene.Snowmen.Contains(man),"a short placement survives");
        scene.PointerDown(man.X,man.Y-man.BaseRadius);scene.PointerUp(man.X,130);
        for(int i=0;i<120 && scene.Snowmen.Count>0;i++)scene.Step(.017,0,0);
        Check(scene.Snowmen.Count==0 && scene.Flakes.Any(f=>f.Powder),"a dropped figure crumbles on landing");

        scene=Scene(1,100);
        scene.SetLedges(new[]{new Ledge("window",80,180,170)});
        scene.Clear();
        var rolling=new SnowBall{X=223,Y=168,Radius=12};scene.Balls.Add(rolling);
        Check(scene.DirectDown(223,168),"desktop pointer picks up the ball on the window");
        scene.DirectMove(239,168);scene.DirectUp(246,168);
        Check(!rolling.InFlight && rolling.Vx>40,"a horizontal release on the ledge keeps rolling momentum");
        bool fell=false;
        for(int i=0;i<150 && scene.Balls.Contains(rolling);i++) {
            scene.Step(.017,0,0);
            fell|=rolling.X>250 && rolling.Y>210;
        }
        Check(fell && !scene.Balls.Contains(rolling) && scene.Flakes.Any(f=>f.Powder),
              "a ball rolls off a real window ledge and crumbles on floor impact");
    }

    private static void GroundedWalk(int direction,int size)
    {
        var scene=Scene(1,100);
        scene.SetVisitorSize(VisitorSizeTarget.Yeti,size);
        if(direction<0) {scene.SendVisitors(VisitorKind.Yeti);scene.Clear();}
        var ground=scene.Banks[0];
        for(int i=0;i<ground.Heights.Length;i++) {
            double x=i*Width/(ground.Heights.Length-1);
            double p=(x-Width*.50)/125;
            ground.Heights[i]=8+32*Math.Exp(-p*p);
        }
        ground.Revision++;
        scene.SendVisitors(VisitorKind.Yeti);var v=scene.Visitors.Single();
        v.TargetX=direction>0?Width-170:170;
        var w=v.Walk;var feet=new[]{w.Far,w.Near};
        int[] plants={0,0},supportFrames={0,0};
        double greatestLift=0,highestSlope=0,slip=0,error=0,fastestChange=0;
        for(int frame=0;frame<3300;frame++) {
            double left=feet[0].X,right=feet[1].X,oldSpeed=w.Velocity;
            bool a=feet[0].Planted,b=feet[1].Planted;
            scene.Step(1.0/60,0,0);
            fastestChange=Math.Max(fastestChange,Math.Abs(w.Velocity-oldSpeed));
            if(!feet[0].Planted && !feet[1].Planted)throw new InvalidOperationException("Both Yeti feet left the bank.");
            for(int i=0;i<2;i++) {
                var foot=feet[i];bool wasDown=i==0?a:b;
                if(foot.Planted) {
                    if(wasDown)slip=Math.Max(slip,Math.Abs(foot.X-(i==0?left:right)));else plants[i]++;
                    error=Math.Max(error,Math.Abs(foot.Y-(ground.Y-ground.PaintedHeightAt(foot.X))));
                    if(w.Velocity*direction>35)supportFrames[i]++;
                    highestSlope=Math.Max(highestSlope,Math.Abs(foot.Tilt));
                }
                greatestLift=Math.Max(greatestLift,foot.Clearance/v.Scale);
            }
            if(v.Met && v.Wait>1.7)break;
        }
        Console.WriteLine("Gait {0}% dir {1}: plants {2}/{3}, travel frames {4}/{5}, lift {6:F3}, slope {7:F3}, slip {8:F4}, clearance error {9:F3}, largest speed change {10:F3}, final speed {11:F3}",
              size,direction,plants[0],plants[1],supportFrames[0],supportFrames[1],greatestLift,highestSlope,slip,error,fastestChange,w.Velocity);
        Check(plants.All(n=>n>=4) && supportFrames.All(n=>n>=30) && greatestLift>4 && highestSlope>4 &&
              slip<.001 && error<.001 && fastestChange<6 && Math.Abs(w.Velocity)<.001,
              String.Format("Yeti at {0}% walking {1} plants both soles without slip on slopes, lifts alternate feet, and brakes to a stop",
                            size,direction>0?"right":"left"));
        Check(v.Met && feet.All(f=>f.Planted) && Math.Abs(feet[0].X-feet[1].X)>4*v.Scale,
              "Yeti finishes the last swing into a balanced resting stance");
    }

    private static void RunningYeti()
    {
        var scene=Scene(1,100);
        var tree=new WinterTree {X=Width/2,Y=Height,Size=80,Support=scene.Banks[0]};scene.Trees.Add(tree);
        var friend=new Snowman{X=260,Y=Height,BaseRadius=18,MidRadius=11,HeadRadius=9};scene.Snowmen.Add(friend);
        scene.SetVisitorSize(VisitorSizeTarget.Yeti,150);
        scene.SendBlizzardYeti(-1);scene.SendBlizzardYeti(1);
        var runners=scene.Visitors.ToArray();double speed=0,lift=0;
        bool powder=false;int southpaw=0,righty=0;
        for(int frame=0;frame<1000 && scene.Visitors.Count>0;frame++) {
            scene.Step(1.0/60,0,0);
            foreach(var v in scene.Visitors) {
                if(!v.Wild || v.Scale!=1.5 || v.Friend!=null || v.Timber!=null || v.Met)
                    throw new InvalidOperationException("A blizzard runner stopped for a visitor interaction.");
                if(!v.Walk.Far.Planted && !v.Walk.Near.Planted)throw new InvalidOperationException("Runner lost its planted foot.");
                speed=Math.Max(speed,Math.Abs(v.Walk.Velocity));lift=Math.Max(lift,Math.Max(v.Walk.Far.Clearance,v.Walk.Near.Clearance)/v.Scale);
                if(v.Walk.Velocity>80)righty++; if(v.Walk.Velocity< -80)southpaw++;
            }
            powder|=scene.Flakes.Any(f=>f.Powder);
        }
        Check(runners.Length==2 && righty>30 && southpaw>30 && speed>95 && lift>7 && powder && scene.Visitors.Count==0 &&
              scene.Trees.Contains(tree) && scene.Snowmen.Contains(friend),"two size-adjusted blizzard Yetis run through with grounded strides and powder footfalls, leaving the tree and snowman intact");
    }

    private static void YetiVisit()
    {
        var scene=Scene(1,100);
        var ground=scene.Banks.First(b=>b.IsFloor);
        scene.SetLedges(new[]{new Ledge("shelf",30,150,260)});
        var ledge=scene.Banks.First(b=>!b.IsFloor);
        var timber=new WinterTree{X=230,Y=Height,Size=80,Support=ground};scene.Trees.Add(timber);
        var second=new WinterTree{X=490,Y=Height,Size=80,Support=ground};scene.Trees.Add(second);
        var shelf=new WinterTree{X=90,Y=150,Size=55,Support=ledge,Anchor=(90-ledge.X)/ledge.Width};scene.Trees.Add(shelf);
        var ornament=new PlacedDecoration{Kind=DecorationKind.Bells,Tree=timber,LocalX=.18,LocalY=-.3};
        scene.Decorations.Add(ornament);
        scene.SendVisitors(VisitorKind.Yeti);
        var yeti=scene.Visitors.Single(v=>v.Kind==VisitorKind.Yeti);
        bool sawFirst=false,sawSecond=false;
        for(int i=0;i<1200 && scene.Visitors.Contains(yeti);i++) {
            scene.Step(.035,0,0);
            if(yeti.Chops==1 && scene.Trees.Contains(timber))sawFirst=true;
            if(yeti.Chops==2 && scene.Trees.Contains(timber))sawSecond=true;
        }
        Check(sawFirst && sawSecond && yeti.CarryingLog && !scene.Visitors.Contains(yeti),"Yeti approaches, makes three timed woodcutting strokes and carries a log away");
        Check(!scene.Trees.Contains(timber) && !scene.Decorations.Contains(ornament) &&
              scene.Trees.Contains(second) && scene.Trees.Contains(shelf),"Yeti clears only the nearest floor tree and its attached ornaments");
        scene=Scene(1,100);
        var man=new Snowman{X=235,Y=Height,BaseRadius=16,MidRadius=12,HeadRadius=9};scene.Snowmen.Add(man);
        scene.SendVisitors(VisitorKind.Yeti);yeti=scene.Visitors.Single();
        for(int i=0;i<500 && !yeti.Met;i++)scene.Step(.035,0,0);
        Check(yeti.Met && yeti.Friend==man && !yeti.CarryingLog && scene.Snowmen.Contains(man),"Yeti greets a snowman when there is no floor tree");
        scene=Scene(1,100);
        scene.SetLedges(new[]{new Ledge("sill",140,130,280)});scene.Clear();
        man=new Snowman{X=270,Y=130,BaseRadius=15,MidRadius=13,HeadRadius=10};
        scene.Snowmen.Add(man);scene.SendVisitors(VisitorKind.Yeti);yeti=scene.Visitors.Single();
        double minSole=Height;
        for(int i=0;i<800 && !yeti.Met;i++) {
            scene.Step(1.0/60,0,0);minSole=Math.Min(minSole,Math.Max(yeti.Walk.Near.Y,yeti.Walk.Far.Y));
        }
        Check(yeti.Met && yeti.Friend==man && minSole>Height-3 && man.Y<150,"Yeti waves to a window snowman from the ground without walking through empty air");
    }

    internal static void Run()
    {
        SnowPhysics();
        foreach(int size in new[]{50,100,250}) {
            GroundedWalk(1,size);GroundedWalk(-1,size);
        }
        YetiVisit();
        RunningYeti();
        foreach (int direction in new[]{1,-1}) {
            foreach (int scale in new[]{50,100,250}) Terrain(direction,scale);
            Objects(direction);
        }
    }
}
