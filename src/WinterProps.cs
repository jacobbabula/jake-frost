using System;
using System.Collections.Generic;
using System.Windows;

namespace Frostpane
{
    [Flags]
    internal enum TreeTrim { None=0, Baubles=1, Lights=2, Twinkle=4, All=Baubles|Lights|Twinkle }

    internal sealed class WinterTree
    {
        public double X, Y, Size, Angle;
        public int Style;
        internal TreeTrim Trim=TreeTrim.All;
        internal int Palette=-1;
        internal bool Hidden;
        internal SnowBank Support;
        internal double Anchor, FallSpeed, GrowLeft;
        internal double DisplaySize {
            get { double rem=Math.Min(1,Math.Max(0,GrowLeft/.55)); return Size*(1-.72*rem*rem*rem); }
        }
    }

    internal struct LightPin
    {
        internal SnowBank Support;
        internal double Anchor;
    }

    internal sealed class LightString
    {
        internal const double MinimumBulbScale=.5, MaximumBulbScale=5;
        public double X1, Y1, X2, Y2;
        // A negative bend retains the gentle preset as the endpoints move.
        internal double Bend = -1, BulbScale = 1;
        internal int Palette = -1;
        internal LightPin Left, Right;
        internal bool Hidden;
        internal double Length { get { double dx=X2-X1,dy=Y2-Y1;return Math.Sqrt(dx*dx+dy*dy); } }
        internal double Sag { get { return Bend<0 ? Math.Min(34,Length*.135) : Bend; } }
        internal double CurveY(double t) { return Y1+(Y2-Y1)*t+4*Sag*t*(1-t); }
    }

    internal sealed class WinterSled
    {
        public double X, Y, Angle, Facing = 1;
        internal double ManualTilt;
        internal double DisplayAngle { get { return Angle*180/Math.PI+ManualTilt; } }
        // Outer points of the runner, seat and upturned nose in sprite coordinates.
        private static readonly double[] Hull={-21,0,-18,1.5,14,1.5,22,-6,26,-10,25,-13,17,-13,-16,-13,-18,-11};
        internal bool BladeSlice(double top,double bottom,out double left,out double right)
        {
            left=double.PositiveInfinity;right=double.NegativeInfinity;
            double a=DisplayAngle*Math.PI/180,c=Math.Cos(a),s=Math.Sin(a),baseY=DisplayY;
            double ax=0,ay=0;
            for(int i=0;i<=Hull.Length;i+=2) {
                double u=Facing*Hull[i%Hull.Length],v=Hull[(i+1)%Hull.Length];
                double bx=X+c*u-s*v,by=baseY+s*u+c*v;
                if(i!=0 && Math.Max(ay,by)>=top && Math.Min(ay,by)<=bottom) {
                    double t0=0,t1=1;
                    if(Math.Abs(by-ay)>.00001) {
                        t0=Math.Max(0,Math.Min((top-ay)/(by-ay),(bottom-ay)/(by-ay)));
                        t1=Math.Min(1,Math.Max((top-ay)/(by-ay),(bottom-ay)/(by-ay)));
                    }
                    double x0=ax+(bx-ax)*t0,x1=ax+(bx-ax)*t1;
                    left=Math.Min(left,Math.Min(x0,x1));right=Math.Max(right,Math.Max(x0,x1));
                }
                ax=bx;ay=by;
            }
            return left<=right;
        }
        internal double DisplayY {
            get {
                if(Support==null || ManualTilt==0) return Y;
                double radians=ManualTilt*Math.PI/180;
                double dx=Math.Sin(radians)*(Facing<0?-1:1),dy=Math.Cos(radians),bottom=double.NegativeInfinity;
                for(int i=0;i<Hull.Length;i+=2) bottom=Math.Max(bottom,Hull[i]*dx+Hull[i+1]*dy);
                return Y-(bottom-1.5)/Math.Max(.2,Math.Cos(Angle));
            }
        }
        internal double Vx, Vy, LastSupportX;
        internal SnowBank Support;
    }

    internal sealed partial class SnowScene
    {
        public readonly List<WinterTree> Trees = new List<WinterTree>();
        public readonly List<LightString> Lights = new List<LightString>();
        public readonly List<WinterSled> Sleds = new List<WinterSled>();
        public int LightPalette;
        internal double NewBulbScale=1;
        internal bool TwinkleLights=true;
        internal TreeTrim NewTreeTrim=TreeTrim.All;
        internal int NewTreePalette=1;
        internal Func<string,bool> IsMountWindowAlive;
        private enum MountState { Visible, Covered, Closed }
        private struct WindowLife {internal double Checked;internal bool Alive;}
        private readonly Dictionary<string,WindowLife> mountLife=new Dictionary<string,WindowLife>(StringComparer.Ordinal);

        private WinterTree draggedTree;
        private LightString draggedLights;
        private WinterSled draggedSled;
        private PlayTool propTool;
        private bool draggingProps, creatingProp, propMoved;
        private double startPropX, startPropY, propOffsetX, propOffsetY;
        private double strandDx, strandDy, lastPropX, lastPropY, lastPropTime, flickX, flickY;

        private static double SnowSurfaceY(SnowBank bank, double x)
        {
            return bank.Y - bank.HeightAt(x);
        }

        // Select the first surface beneath a released decoration, allowing a
        // slight overlap so a drop on the window's title bar catches its edge.
        private SnowBank PropSurfaceBelow(double x, double y, double tolerance)
        {
            SnowBank nearest = null;
            double top = double.MaxValue;
            foreach (SnowBank bank in Banks)
            {
                if (x < bank.X || x > bank.X + bank.Width) continue;
                double candidate = SnowSurfaceY(bank, x);
                if (candidate < y - tolerance || candidate >= top) continue;
                top = candidate;
                nearest = bank;
            }
            return nearest;
        }

        private WinterTree TreeAt(double x, double y)
        {
            for (int i = Trees.Count - 1; i >= 0; i--)
            {
                WinterTree tree = Trees[i];
                if(tree.Hidden) continue;
                Point local=TurnOffset(x-tree.X,y-tree.Y,-tree.Angle);
                double fromTip = local.Y + tree.Size;
                double halfSpan = 8 + .32 * Limit(fromTip, 0, tree.Size);
                if (fromTip >= -8 && local.Y < 8 && Math.Abs(local.X) <= halfSpan) return tree;
            }
            return null;
        }

        private WinterSled SledAt(double x, double y)
        {
            for (int i = Sleds.Count - 1; i >= 0; i--)
            {
                WinterSled sled = Sleds[i];
                double dx = x - sled.X, dy = y - sled.DisplayY;
                double radians=sled.DisplayAngle*Math.PI/180;
                double ca = Math.Cos(radians), sa = Math.Sin(radians);
                double along = dx * ca + dy * sa, up = -dx * sa + dy * ca;
                if (Math.Abs(along) <= 27 && up >= -21 && up <= 7) return sled;
            }
            return null;
        }

        private LightString StringAt(double x, double y)
        {
            for (int i = Lights.Count - 1; i >= 0; i--)
            {
                LightString strand = Lights[i];
                if(strand.Hidden) continue;
                double dx=strand.X2-strand.X1,dy=strand.Y2-strand.Y1,sag=strand.Sag;
                double radius=7+strand.BulbScale*3;
                if(x<Math.Min(strand.X1,strand.X2)-radius || x>Math.Max(strand.X1,strand.X2)+radius ||
                    y<Math.Min(strand.Y1,strand.Y2)-radius || y>Math.Max(strand.Y1,strand.Y2)+sag+18*strand.BulbScale) continue;
                // The piecewise distance works for vertical wires and free ends dragged past each other.
                int parts=Math.Max(2,Math.Min(24,(int)Math.Ceiling(Math.Sqrt(sag+1)*1.4)));
                double px=strand.X1,py=strand.Y1;
                for(int j=1;j<=parts;j++) {
                    double t=(double)j/parts,nx=strand.X1+dx*t,ny=strand.Y1+dy*t+4*sag*t*(1-t);
                    double vx=nx-px,vy=ny-py;
                    double segmentLength=Math.Max(.001,vx*vx+vy*vy);
                    for(int band=0;band<3;band++) {
                        // Cover the wire, sockets and glass even at the largest bulb size.
                        double localY=y-band*6.5*strand.BulbScale;
                        double u=Limit(((x-px)*vx+(localY-py)*vy)/segmentLength,0,1);
                        if(LightHit(x,localY,px+u*vx,py+u*vy,radius)) return strand;
                    }
                    px=nx;py=ny;
                }
            }
            return null;
        }

        internal void RemoveTree(WinterTree tree)
        {
            if(tree==null || !Trees.Remove(tree)) return;
            Decorations.RemoveAll(delegate(PlacedDecoration d){return d.Tree==tree;});
            if(selectedTree==tree || (selectedItem!=null && selectedItem.Tree==tree)) ClearPropSelection();
            if(selectedGiftTree==tree) selectedGiftTree=null;
        }

        private void EraseProp(double x, double y)
        {
            var decoration=DecorationAt(x,y);
            if(decoration!=null) {Decorations.Remove(decoration);return;}
            WinterSled sled = SledAt(x, y);
            if (sled != null) { Sleds.Remove(sled); return; }
            WinterTree tree = TreeAt(x, y);
            if (tree != null) { RemoveTree(tree); return; }
            LightString strand = StringAt(x, y);
            if (strand != null) Lights.Remove(strand);
        }

        partial void PropsDown(PlayTool tool, double x, double y)
        {
            PropsCancel();
            if (floor == null) return;
            if(tool==PlayTool.StyleTree) {
                var tree=TreeAt(x,y);
                if(tree!=null) {tree.Palette=NewTreePalette;tree.Trim=NewTreeTrim;}
                return;
            }
            if(tool==PlayTool.Decorate && SelectedDecoration==DecorationKind.Tree) tool=PlayTool.Tree;
            if(tool==PlayTool.Decorate && SelectedDecoration==DecorationKind.Lights) tool=PlayTool.Lights;
            propTool = tool;
            if (tool == PlayTool.Tree || tool == PlayTool.Lights || tool == PlayTool.Erase || tool==PlayTool.Decorate || tool==PlayTool.Arrange)
                layoutBeforeDrag = ExportDecorations();
            draggingProps = true;
            creatingProp = propMoved = false;
            startPropX = lastPropX = x;
            startPropY = lastPropY = y;
            lastPropTime = Time;
            propOffsetX = propOffsetY = flickX = flickY = 0;
            if(GrabTransformControl(tool,x,y)) return;
            if((tool==PlayTool.Lights || tool==PlayTool.Arrange) && GrabLightControl(x,y)) return;
            if(tool==PlayTool.Arrange) {
                var existing=DecorationAt(x,y);
                if(existing!=null) {GrabDecoration(x,y,existing);return;}
                if(StringAt(x,y)!=null) tool=PlayTool.Lights;
                else if(SledAt(x,y)!=null) {
                    ClearPropSelection();selectedSled=SledAt(x,y);return;
                }
                else if(TreeAt(x,y)!=null) tool=PlayTool.Tree;
                else { ClearPropSelection();return; }
                propTool=tool;
            }
            if(tool==PlayTool.Decorate) {GrabDecoration(x,y,null);return;}
            if (tool == PlayTool.Erase) { EraseProp(x, y); return; }
            if (tool == PlayTool.Tree)
            {
                draggedTree = TreeAt(x, y);
                if (draggedTree == null)
                {
                    if (Trees.Count >= 40) return;
                    creatingProp = true;
                    draggedTree = new WinterTree { X=x,Y=y,Size=Between(55,81),Style=random.Next(12),GrowLeft=.55,
                        Trim=NewTreeTrim,Palette=NewTreePalette };
                    Trees.Add(draggedTree);
                }
                propOffsetX = draggedTree.X - x;
                propOffsetY = draggedTree.Y - y;
                ClearPropSelection();selectedTree=draggedTree;
                draggedTree.Support = null;
                draggedTree.FallSpeed = 0;
            }
            else if (tool == PlayTool.Lights)
            {
                draggedLights = StringAt(x, y);
                if (draggedLights == null)
                {
                    if (Lights.Count >= 40) return;
                    creatingProp = true;
                    draggedLights = new LightString { Palette=(int)Limit(LightPalette,0,2), BulbScale=NewBulbScale };
                    DefaultStrand(draggedLights, x, y);
                    Lights.Add(draggedLights);
                }
                else
                {
                    propOffsetX = draggedLights.X1 - x;
                    propOffsetY = draggedLights.Y1 - y;
                    strandDx = draggedLights.X2 - draggedLights.X1;
                    strandDy = draggedLights.Y2 - draggedLights.Y1;
                }
                ClearPropSelection();selectedStrand=draggedLights;
            }
            else if (tool == PlayTool.Sled)
            {
                draggedSled = SledAt(x, y);
                if (draggedSled == null)
                {
                    if (Sleds.Count >= 24) return;
                    creatingProp = true;
                    draggedSled = new WinterSled { X = x, Y = y };
                    Sleds.Add(draggedSled);
                }
                propOffsetX = draggedSled.X - x;
                propOffsetY = draggedSled.Y - y;
                ClearPropSelection();selectedSled=draggedSled;
                draggedSled.Support = null;
            }
        }

        partial void PropsMove(double x, double y)
        {
            if (!draggingProps) return;
            if (Math.Abs(x - startPropX) + Math.Abs(y - startPropY) > 4) propMoved = true;
            if(editGrip!=EditGrip.None) { if(propMoved) MoveEditGrip(x,y);return; }
            if(draggedDecoration!=null) {
                draggedDecoration.X=Limit(x+propOffsetX,0,width);
                draggedDecoration.Y=Limit(y+propOffsetY,0,height);
            }
            if (propTool == PlayTool.Erase)
            {
                double travel = Math.Max(Math.Abs(x - lastPropX), Math.Abs(y - lastPropY));
                int steps = Math.Min(48, (int)Math.Ceiling(travel / 8));
                for (int i = 1; i <= steps; i++)
                    EraseProp(lastPropX + (x - lastPropX) * i / steps, lastPropY + (y - lastPropY) * i / steps);
            }
            if (draggedTree != null)
            {
                draggedTree.X = Limit(x + propOffsetX, 0, width);
                draggedTree.Y = Limit(y + propOffsetY, 0, height);
            }
            if (draggedLights != null && propMoved)
            {
                if (dragLightPin) MoveLightControl(x,y);
                else if (creatingProp) SetStrand(draggedLights, startPropX, startPropY, x, y);
                else
                {
                    double lx = Limit(x + propOffsetX, 0, Math.Max(0, width - strandDx));
                    double ly = Limit(y + propOffsetY, Math.Max(0, -strandDy), Math.Min(height, height - strandDy));
                    SetStrand(draggedLights, lx, ly, lx + strandDx, ly + strandDy);
                }
            }
            if (draggedSled != null)
            {
                double dx = x - lastPropX, dy = y - lastPropY;
                if (Math.Abs(dx) + Math.Abs(dy) > .05)
                {
                    double sample = Limit(Time - lastPropTime, 1.0 / 90, .15);
                    double weight = 1 - Math.Exp(-sample * 26);
                    flickX += (Limit(dx / sample, -1000, 1000) - flickX) * weight;
                    flickY += (Limit(dy / sample, -900, 900) - flickY) * weight;
                    lastPropTime = Time;
                    if (Math.Abs(dx) > .5) draggedSled.Facing = Math.Sign(dx);
                }
                draggedSled.X = Limit(x + propOffsetX, 0, width);
                draggedSled.Y = Limit(y + propOffsetY, 0, height);
                if (propMoved) draggedSled.Angle = 0;
            }
            lastPropX = x;
            lastPropY = y;
        }

        partial void PropsUp(double x, double y)
        {
            if (!draggingProps) return;
            PropsMove(x, y);
            if(suppressLightUp || editGrip!=EditGrip.None) {EndPropDrag();return;}
            if(draggedDecoration!=null && (creatingProp || propMoved)) ReleaseDecoration(draggedDecoration);
            if (draggedTree != null) PlantTree(draggedTree);
            if(dragLightPin && propMoved) LandLightControl();
            else if (draggedLights != null && (creatingProp || propMoved))
            {
                if (draggedLights.Length < 18)
                    DefaultStrand(draggedLights, (draggedLights.X1 + draggedLights.X2) / 2, y);
                PinStrand(draggedLights);
            }
            if (draggedSled != null)
            {
                WinterSled sled = draggedSled;
                SnowBank nearby = PropSurfaceBelow(sled.X, sled.Y, 22);
                if (nearby == null && sled.Y >= SnowSurfaceY(floor, sled.X)) nearby = floor;
                if (nearby != null && sled.Y >= SnowSurfaceY(nearby, sled.X) - 20)
                {
                    SetRunnerSupport(sled, nearby);
                    sled.Y = SnowSurfaceY(nearby, sled.X);
                }
                if (propMoved)
                {
                    double decay = Math.Exp(-Math.Max(0, Time - lastPropTime - .055) * 14);
                    sled.Vx = Limit(flickX * decay, -550, 550);
                    sled.Vy = Limit(flickY * decay, -340, 400);
                    if (sled.Vy < -80) sled.Support = null;
                }
                else if (!creatingProp)
                {
                    double side = startPropX - sled.X;
                    double aim = Math.Abs(side) < 5 ? sled.Facing : -Math.Sign(side);
                    sled.Vx = Limit(sled.Vx + aim * 165, -460, 460);
                }
            }
            EndPropDrag();
        }

        partial void PropsCancel()
        {
            if (!draggingProps) return;
            if(editGrip!=EditGrip.None) {EndPropDrag();return;}
            if (creatingProp)
            {
                if (draggedTree != null) Trees.Remove(draggedTree);
                if (draggedLights != null) Lights.Remove(draggedLights);
                if (draggedSled != null) Sleds.Remove(draggedSled);
                if (draggedDecoration!=null) Decorations.Remove(draggedDecoration);
            }
            else
            {
                if (draggedTree != null) PlantTree(draggedTree);
                if(draggedDecoration!=null && propMoved) ReleaseDecoration(draggedDecoration);
                if(dragLightPin && propMoved) LandLightControl();
                else if (draggedLights != null && propMoved) PinStrand(draggedLights);
                if (draggedSled != null) draggedSled.Vx = draggedSled.Vy = 0;
            }
            EndPropDrag();
        }

        private void EndPropDrag()
        {
            draggedTree = null; draggedLights = null; draggedSled = null;
            draggedDecoration=null; dragLightPin=dragLeftPin=suppressLightUp=false;
            editGrip=EditGrip.None;
            layoutBeforeDrag = null;
            creatingProp = propMoved = draggingProps = false;
        }

        private void PlantTree(WinterTree tree)
        {
            SnowBank support = PropSurfaceBelow(tree.X, tree.Y, 24) ?? floor;
            AttachTree(tree, support);
        }

        private void AttachTree(WinterTree tree, SnowBank support)
        {
            tree.Support = support;
            tree.Anchor = Limit((tree.X - support.X) / support.Width, 0, 1);
            RestTree(tree,support);
            tree.FallSpeed = 0;
        }

        private SnowBank MountNear(double x, double y, double reach=35)
        {
            SnowBank best = null;
            double min = reach;
            foreach (SnowBank bank in Banks)
            {
                if (bank.IsFloor || x < bank.X - 6 || x > bank.X + bank.Width + 6) continue;
                double distance = Math.Min(Math.Abs(y - bank.Y), Math.Abs(y - SnowSurfaceY(bank, x)));
                if (distance < min) { min = distance; best = bank; }
            }
            return best;
        }

        private void DefaultStrand(LightString strand, double x, double y)
        {
            SnowBank ledge = MountNear(x, y);
            double left = ledge == null ? 1 : ledge.X + 1;
            double right = ledge == null ? Math.Max(1, width - 1) : ledge.X + ledge.Width - 1;
            double span = Math.Min(Math.Max(0, right - left), 160);
            double x1 = Limit(x - span / 2, left, right - span);
            double pinY=ledge==null?y:ledge.Y+2;
            SetStrand(strand, x1, pinY, x1 + span, pinY);
        }

        private void SetStrand(LightString strand, double ax, double ay, double bx, double by)
        {
            bool reverse = ax > bx;
            strand.X1 = Limit(reverse ? bx : ax, 0, width);
            strand.Y1 = Limit(reverse ? by : ay, 0, height);
            strand.X2 = Limit(reverse ? ax : bx, 0, width);
            strand.Y2 = Limit(reverse ? ay : by, 0, height);
            strand.Left = new LightPin(); strand.Right = new LightPin();
        }

        private LightPin Pin(double x, double y)
        {
            SnowBank bank = MountNear(x, y,12);
            return new LightPin { Support = bank, Anchor = bank == null ? 0 : Limit((x - bank.X) / bank.Width, 0, 1) };
        }

        private void PinStrand(LightString strand)
        {
            strand.Left = Pin(strand.X1, strand.Y1);
            strand.Right = Pin(strand.X2, strand.Y2);
            PositionPin(strand.Left, ref strand.X1, ref strand.Y1);
            PositionPin(strand.Right, ref strand.X2, ref strand.Y2);
        }

        private bool PositionPin(LightPin pin, ref double x, ref double y)
        {
            if (pin.Support != null)
            {
                if (!Banks.Contains(pin.Support)) return false;
                x = pin.Support.X + pin.Anchor * pin.Support.Width;
                y = pin.Support.Y + 2;
            }
            x = Limit(x, 0, width); y = Limit(y, 0, height);
            return true;
        }

        private bool WindowRemainsOpen(string id)
        {
            if(IsMountWindowAlive==null || string.IsNullOrEmpty(id)) return false;
            int slash=id.IndexOf('/');
            if(slash<1) return false;
            string owner=id.Substring(0,slash);
            WindowLife status;
            if(!mountLife.TryGetValue(owner,out status) || Time-status.Checked>=.75)
            {
                if(mountLife.Count>=192) mountLife.Clear();
                status=new WindowLife{Alive=IsMountWindowAlive(id),Checked=Time};
                mountLife[owner]=status;
            }
            return status.Alive;
        }

        // Keep the last visible bank as an anchor while Windows reports that the
        // owning window still exists. Missing ledges alone also mean occlusion.
        private MountState ResolveMount(ref SnowBank support,ref double anchor)
        {
            if(support==null || support.IsFloor || Banks.Contains(support)) return MountState.Visible;
            SnowBank live;
            if(windows.TryGetValue(support.Id,out live)) {support=live;return MountState.Visible;}
            int slash=support.Id.IndexOf('/');
            if(slash>=1)
            {
                double x=support.X+support.Width*anchor;
                string prefix=support.Id.Substring(0,slash+1);
                foreach(SnowBank part in Banks) {
                    if(!part.Id.StartsWith(prefix,StringComparison.Ordinal) || Math.Abs(support.Y-part.Y)>32 ||
                        x<part.X-2 || x>part.X+part.Width+2) continue;
                    anchor=Limit((x-part.X)/part.Width,0,1); support=part; return MountState.Visible;
                }
            }
            return WindowRemainsOpen(support.Id)?MountState.Covered:MountState.Closed;
        }

        private static void OrderPins(LightString strand)
        {
            if (strand.X1 <= strand.X2) return;
            double x = strand.X1, y = strand.Y1;
            LightPin pin = strand.Left;
            strand.X1 = strand.X2; strand.Y1 = strand.Y2; strand.Left = strand.Right;
            strand.X2 = x; strand.Y2 = y; strand.Right = pin;
        }

        private static void SetRunnerSupport(WinterSled sled, SnowBank bank)
        {
            sled.Support = bank;
            sled.LastSupportX = bank.X;
        }

        private static double Grade(SnowBank bank, double x)
        {
            double left = Math.Max(bank.X, x - 12), right = Math.Min(bank.X + bank.Width, x + 12);
            if (right <= left + .01) return 0;
            return (SnowSurfaceY(bank, right) - SnowSurfaceY(bank, left)) / (right - left);
        }

        private void StepSled(WinterSled sled, double dt)
        {
            if (sled.Support != null && !Banks.Contains(sled.Support)) sled.Support = null;
            if (sled.Support != null)
            {
                SnowBank bank = sled.Support;
                sled.X += bank.X - sled.LastSupportX;
                sled.LastSupportX = bank.X;
                double slope = Grade(bank, sled.X);
                double acceleration = 515 * slope / (1 + slope * slope);
                double velocity = (sled.Vx + acceleration * dt) * Math.Exp(-.34 * dt);
                sled.Vx = Math.Sign(velocity) * Math.Max(0, Math.Abs(velocity) - 9 * dt);
                sled.Vx = Limit(sled.Vx, -560, 560);
                double nextX = sled.X + sled.Vx * dt;
                sled.Angle += (Math.Atan(slope) - sled.Angle) * Math.Min(1, dt * 15);
                if (nextX >= bank.X && nextX <= bank.X + bank.Width)
                {
                    sled.X = nextX;
                    sled.Y = SnowSurfaceY(bank, nextX);
                    sled.Vy = 0;
                }
                else
                {
                    sled.Y = SnowSurfaceY(bank, Limit(sled.X, bank.X, bank.X + bank.Width));
                    sled.Vy = sled.Vx * slope;
                    sled.Support = null;
                }
            }
            if (sled.Support == null)
            {
                double previous = sled.Y;
                sled.Vy = Math.Min(670, sled.Vy + 515 * dt);
                sled.X += sled.Vx * dt;
                sled.Y += sled.Vy * dt;
                sled.Angle *= Math.Exp(-dt * 2);
                SnowBank caught = PropSurfaceBelow(sled.X, previous, 1.5);
                if (caught != null && sled.Vy >= 0 && sled.Y >= SnowSurfaceY(caught, sled.X))
                {
                    sled.Y = SnowSurfaceY(caught, sled.X);
                    SetRunnerSupport(sled, caught);
                    sled.Vy = 0;
                }
                else if (sled.Y >= height)
                {
                    SetRunnerSupport(sled, floor);
                    sled.Y = SnowSurfaceY(floor, sled.X);
                    sled.Vy = 0;
                }
            }
            double inset = Math.Min(20, width * .5);
            if (sled.X <= inset || sled.X >= width - inset)
            {
                if ((sled.X <= inset && sled.Vx < 0) || (sled.X >= width - inset && sled.Vx > 0)) sled.Vx *= -.28;
                sled.X = Limit(sled.X, inset, width - inset);
            }
            if (Math.Abs(sled.Vx) > 3) sled.Facing = Math.Sign(sled.Vx);
        }

        partial void PropsStep(double dt)
        {
            if (floor == null) return;
            foreach (WinterTree tree in Trees)
            {
                tree.GrowLeft=Math.Max(0,tree.GrowLeft-dt);
                if (tree == draggedTree || IsLeaving(tree)) continue;
                MountState state=ResolveMount(ref tree.Support,ref tree.Anchor);
                tree.Hidden=state==MountState.Covered;
                if(tree.Hidden) continue;
                if(state==MountState.Closed) tree.Support=null;
                if (tree.Support != null)
                {
                    if (!tree.Support.IsFloor) tree.X = tree.Support.X + tree.Anchor * tree.Support.Width;
                    tree.X = Limit(tree.X, 0, width);
                    RestTree(tree,tree.Support);
                }
                else
                {
                    double previous = tree.Y;
                    tree.FallSpeed = Math.Min(550, tree.FallSpeed + 410 * dt);
                    tree.Y += tree.FallSpeed * dt;
                    SnowBank below = PropSurfaceBelow(tree.X, previous, 1.5) ?? floor;
                    if (tree.Y >= SnowSurfaceY(below, tree.X)) AttachTree(tree, below);
                }
            }
            for (int i = Lights.Count - 1; i >= 0; i--)
            {
                LightString strand = Lights[i];
                if (strand == draggedLights || IsLeaving(strand)) continue;
                MountState left=ResolveMount(ref strand.Left.Support,ref strand.Left.Anchor);
                MountState right=ResolveMount(ref strand.Right.Support,ref strand.Right.Anchor);
                if(left==MountState.Closed || right==MountState.Closed) {Lights.RemoveAt(i);continue;}
                if(left==MountState.Visible) PositionPin(strand.Left, ref strand.X1, ref strand.Y1);
                if(right==MountState.Visible) PositionPin(strand.Right, ref strand.X2, ref strand.Y2);
                strand.Hidden=left==MountState.Covered || right==MountState.Covered;
                if(strand.Hidden) continue;
                OrderPins(strand);
            }
            foreach (WinterSled sled in Sleds) if (sled != draggedSled) StepSled(sled, dt);
            RepositionDecorations();
        }

        partial void PropsResize()
        {
            foreach (WinterTree tree in Trees) tree.X = Limit(tree.X, 0, width);
            foreach (WinterSled sled in Sleds)
            {
                sled.X = Limit(sled.X, 0, width);
                sled.Y = Limit(sled.Y, 0, height);
            }
            PropsStep(0);
        }

        partial void PropsClear()
        {
            EndPropDrag();
            Trees.Clear(); Lights.Clear(); Sleds.Clear(); Decorations.Clear(); ClearPropSelection();mountLife.Clear();
        }
    }
}
