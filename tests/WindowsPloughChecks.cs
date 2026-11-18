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
        for (int i=0;i<1100 && scene.Plough!=null;i++) scene.Step(1.0/60,0,0);
        Check(scene.Plough==null,"vehicle completes its pass with loose objects on the ground");
        Check(scene.Balls.Contains(ball) && dir*(ball.X-x(170))>12,"loose snowball moves in blade direction");
        Check(scene.Snowmen.Contains(figure) && dir*(figure.X-x(255))>12,"built snowman is pushed and survives");
        Check(scene.Sleds.Contains(sled) && dir*(sled.X-x(330))>12,"sled is pushed and survives");
        Check(scene.Trees.Contains(tree) && dir*(tree.X-x(402))>12 && ornament.Tree==tree &&
              Math.Abs(ornament.X-tree.X)<tree.Size,"tree moves with its attached bauble");
        Check(scene.Decorations.Contains(gift) && dir*(gift.X-x(480))>12,"a loose decoration moves ahead of the blade");
        Check(dir*(strand.X1-Math.Min(x(565),x(605)))>8 && dir*(strand.X2-Math.Max(x(565),x(605)))>8,"a low free light strand moves with the blade");
        Check(scene.DailyPresent!=null && dir*(scene.DailyPresent.X-x(700))>8,"Santa's unopened present is pushed intact");
        Check(Math.Abs(overhead.X-x(380))<0.1 && Math.Abs(overheadWire.X1-Math.Min(x(280),x(345)))<0.1 &&
              Math.Abs(overheadWire.X2-Math.Max(x(280),x(345)))<0.1,"a ledge tree and overhead lights stay in place");
        Check(new[]{ball.X,figure.X,sled.X,tree.X,gift.X,scene.DailyPresent.X}.All(p=>p>=0 && p<=Width),"pushed pieces remain accessible at the edge");
    }

    internal static void Run()
    {
        foreach (int direction in new[]{1,-1}) {
            foreach (int scale in new[]{50,100,250}) Terrain(direction,scale);
            Objects(direction);
        }
    }
}
