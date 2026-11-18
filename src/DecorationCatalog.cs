using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Windows;
using System.Windows.Media;

namespace Frostpane
{
    internal enum DecorationKind { Tree, Lights, Candle, RedBauble, GoldBauble, Star, Wreath, Stocking, CandyCane,
        Gift, Bells, Gingerbread, Holly, SantaHat, SnowGlobe, Cocoa, Boat }

    internal sealed class PlacedDecoration
    {
        internal DecorationKind Kind;
        internal double X,Y, LocalX,LocalY;
        internal WinterTree Tree;
        internal LightPin Mount;
        internal bool Hidden;
        internal double Magnification=1;
        internal double Angle;
        internal double WorldAngle { get { return Angle+(Tree==null?0:Tree.Angle); } }
        internal double Scale { get { return Magnification*(Tree == null ? 1 : Math.Max(.27, Math.Min(.91,Tree.Size/173))); } }
    }

    internal sealed partial class SnowScene
    {
        internal readonly List<PlacedDecoration> Decorations=new List<PlacedDecoration>();
        internal DecorationKind SelectedDecoration=DecorationKind.Tree;
        internal bool ShowDecorationHandles;
        private PlacedDecoration draggedDecoration;
        private LightString selectedStrand;
        private WinterTree selectedTree;
        private PlacedDecoration selectedItem;
        private WinterSled selectedSled;
        private enum EditGrip { None, Size, Rotate, Bend }
        private EditGrip editGrip;
        private double startSize,startDistance,scaleCenterX,scaleCenterY;
        private double startAngle,startBearing;
        private bool dragLightPin, dragLeftPin, suppressLightUp;

        private static bool StandsOnSnow(DecorationKind k)
        {
            return k==DecorationKind.Candle || k==DecorationKind.Gift || k==DecorationKind.SnowGlobe ||
                k==DecorationKind.Cocoa || k==DecorationKind.Boat || k==DecorationKind.Gingerbread;
        }

        private PlacedDecoration DecorationAt(double x,double y)
        {
            for(int i=Decorations.Count-1;i>=0;i--) {
                var d=Decorations[i];
                if(d.Hidden) continue;
                Point local=TurnOffset(x-d.X,y-d.Y,-d.WorldAngle);
                if(Math.Abs(local.X)<=19*d.Scale+2 && Math.Abs(local.Y)<=20*d.Scale+2) return d;
            }
            return null;
        }

        private void ClearPropSelection()
        {
            selectedItem=null;selectedTree=null;selectedStrand=null;selectedSled=null;
        }

        private void GrabDecoration(double x,double y,PlacedDecoration existing)
        {
            draggedDecoration=existing??DecorationAt(x,y);
            if(existing==null && draggedDecoration!=null && draggedDecoration.Kind!=SelectedDecoration) draggedDecoration=null;
            if(draggedDecoration==null) {
                if(Decorations.Count>=160) return;
                draggedDecoration=new PlacedDecoration{Kind=SelectedDecoration,X=x,Y=y};
                Decorations.Add(draggedDecoration); creatingProp=true;
            }
            propOffsetX=draggedDecoration.X-x; propOffsetY=draggedDecoration.Y-y;
            ClearPropSelection();selectedItem=draggedDecoration;
        }

        private void ReleaseDecoration(PlacedDecoration d)
        {
            double worldAngle=d.WorldAngle;
            d.Tree=TreeAt(d.X,d.Y); d.Mount=new LightPin();
            d.Angle=SignedAngle(worldAngle-(d.Tree==null?0:d.Tree.Angle));
            if(d.Tree!=null) {
                Point local=TurnOffset(d.X-d.Tree.X,d.Y-d.Tree.Y,-d.Tree.Angle);
                d.LocalX=Limit(local.X/d.Tree.Size,-.35,.35);
                d.LocalY=Limit(local.Y/d.Tree.Size,-1.02,-.08);
                SetTreePosition(d); return;
            }
            SnowBank support=SupportForDecoration(d);
            if(support!=null) {
                d.Mount=new LightPin{Support=support,Anchor=Limit((d.X-support.X)/support.Width,0,1)};
                RestDecoration(d,support);
            }
        }

        private static void SetTreePosition(PlacedDecoration d)
        {
            Point offset=TurnOffset(d.Tree.Size*d.LocalX,d.Tree.Size*d.LocalY,d.Tree.Angle);
            d.X=d.Tree.X+offset.X; d.Y=d.Tree.Y+offset.Y;
        }

        private static Point TurnOffset(double x,double y,double degrees)
        {
            if(degrees==0) return new Point(x,y);
            double radians=degrees*Math.PI/180, c=Math.Cos(radians),s=Math.Sin(radians);
            return new Point(c*x-s*y,s*x+c*y);
        }

        private static double SignedAngle(double angle)
        {
            angle%=360;
            if(angle>180) return angle-360;
            return angle<=-180 ? angle+360 : angle;
        }

        private void RepositionDecorations()
        {
            for(int i=Decorations.Count-1;i>=0;i--) {
                var d=Decorations[i];
                if(d==draggedDecoration || IsLeaving(d)) continue;
                if(d.Tree!=null) {
                    if(!Trees.Contains(d.Tree)) { Decorations.RemoveAt(i); continue; }
                    d.Hidden=d.Tree.Hidden;
                    SetTreePosition(d); continue;
                }
                MountState state=ResolveMount(ref d.Mount.Support,ref d.Mount.Anchor);
                d.Hidden=state==MountState.Covered;
                if(d.Hidden) continue;
                SnowBank bank=d.Mount.Support;
                if(state==MountState.Closed) {
                    d.Mount=new LightPin();
                    if(StandsOnSnow(d.Kind)) ReleaseDecoration(d);
                    bank=d.Mount.Support;
                }
                if(bank!=null) {
                    if(!bank.IsFloor) d.X=bank.X+d.Mount.Anchor*bank.Width;
                    RestDecoration(d,bank);
                }
                d.X=Limit(d.X,0,width); d.Y=Limit(d.Y,0,height);
            }
        }

        private static bool SpriteKind(int index)
        {
            return index>=(int)DecorationKind.Candle && index<=(int)DecorationKind.Boat;
        }

        internal string ExportTreeDress(WinterTree tree)
        {
            if(tree==null) return "";
            var parts=new List<string>();
            var sizes=new List<string>();
            var angles=new List<string> {LayoutNumber(tree.Angle)};
            int lastAngle=tree.Angle==0 ? 0 : 1;
            foreach(var d in Decorations) {
                if(d.Tree!=tree) continue;
                angles.Add(LayoutNumber(d.Angle));
                if(d.Angle!=0) lastAngle=angles.Count;
                if(d.Magnification!=1) {
                    sizes.Add(parts.Count.ToString(CultureInfo.InvariantCulture));
                    sizes.Add(LayoutNumber(d.Magnification));
                }
                parts.Add(((int)d.Kind).ToString(CultureInfo.InvariantCulture)+","+
                    LayoutNumber(d.LocalX)+","+LayoutNumber(d.LocalY));
            }
            // Older receivers read the base ornaments and skip the optional appearance records.
            if(sizes.Count>0) parts.Add("scale,"+string.Join(",",sizes.ToArray()));
            if(lastAngle>0) parts.Add("angles,"+string.Join(",",angles.GetRange(0,lastAngle).ToArray()));
            if(tree.Palette>=0 || tree.Trim!=TreeTrim.All)
                parts.Add("trim,"+((int)tree.Trim).ToString(CultureInfo.InvariantCulture)+","+tree.Palette.ToString(CultureInfo.InvariantCulture));
            return string.Join(";",parts.ToArray());
        }

        private static void ReadTreeTrim(WinterTree tree,string flags,string palette)
        {
            int trim,colors;
            if(!int.TryParse(flags,out trim) || trim<0 || trim>(int)TreeTrim.All ||
                !int.TryParse(palette,out colors) || colors< -1 || colors>2) return;
            tree.Trim=(TreeTrim)trim;tree.Palette=colors;
        }

        internal void ImportTreeDress(WinterTree tree,string data)
        {
            if(tree==null || !Trees.Contains(tree) || data==null || data.Length>8192) return;
            Decorations.RemoveAll(delegate(PlacedDecoration d){return d.Tree==tree;});
            var decoded=new List<PlacedDecoration>();
            tree.Angle=0;tree.Trim=TreeTrim.All;tree.Palette=-1;
            foreach(string item in data.Split(';')) {
                string[] a=item.Split(',');
                if(a[0]=="trim" && a.Length==3) {ReadTreeTrim(tree,a[1],a[2]);continue;}
                if(a[0]=="angles") {
                    double angle;
                    if(a.Length>=2 && ReadLayoutNumber(a[1],out angle)) tree.Angle=SignedAngle(angle);
                    for(int i=0;i<decoded.Count && i+2<a.Length;i++) {
                        if(ReadLayoutNumber(a[i+2],out angle)) decoded[i].Angle=SignedAngle(angle);
                    }
                    continue;
                }
                if(a[0]=="scale") {
                    for(int i=1;i+1<a.Length;i+=2) {
                        int index;double scale;
                        if(int.TryParse(a[i],NumberStyles.Integer,CultureInfo.InvariantCulture,out index) && index>=0 &&
                            index<decoded.Count && ReadLayoutNumber(a[i+1],out scale)) decoded[index].Magnification=Limit(scale,.35,4);
                    }
                    continue;
                }
                int ix; double rx,ry;
                if(Decorations.Count>=160 || a.Length!=3 || !int.TryParse(a[0],NumberStyles.Integer,CultureInfo.InvariantCulture,out ix) ||
                    !SpriteKind(ix) || !ReadLayoutNumber(a[1],out rx) || !ReadLayoutNumber(a[2],out ry)) continue;
                var d=new PlacedDecoration{Kind=(DecorationKind)ix,Tree=tree,
                    LocalX=Limit(rx,-.35,.35),LocalY=Limit(ry,-1.02,-.08)};
                SetTreePosition(d); Decorations.Add(d);decoded.Add(d);
            }
            if(tree.Support!=null) RestTree(tree,tree.Support);
            foreach(var d in decoded) SetTreePosition(d);
        }

        private void ExportCatalog(StringBuilder text,List<WinterTree> savedTrees)
        {
            foreach(var d in Decorations) {
                if(IsLeaving(d) || (d.Tree!=null && IsLeaving(d.Tree))) continue;
                double y=d.Mount.Support==null ? d.Y : d.Mount.Support.Y-Footprint(d).BottomOffset(d.Scale);
                // Mounted world coordinates are recoverable if a window has closed.
                text.Append("\nD\t").Append(((int)d.Kind).ToString(CultureInfo.InvariantCulture))
                    .Append('\t').Append(LayoutNumber(d.X)).Append('\t').Append(LayoutNumber(y))
                    .Append('\t').Append(savedTrees.IndexOf(d.Tree).ToString(CultureInfo.InvariantCulture))
                    .Append('\t').Append(LayoutFactor(d.LocalX)).Append('\t').Append(LayoutFactor(d.LocalY));
                WriteMount(text,d.Mount.Support,d.Mount.Anchor);
                text.Append('\t').Append(LayoutFactor(d.Magnification));
                if(d.Angle!=0) text.Append('\t').Append(LayoutFactor(d.Angle));
            }
        }

        private void ReadCatalogRow(string[] row,double sx,double sy,List<WinterTree> trees,List<PlacedDecoration> items)
        {
            if(row.Length<12 || row.Length>14 || items.Count>=160) return;
            int kind,treeIx; double x,y,rx,ry; LightPin pin;
            double size=1,angle=0;
            if(row.Length>=13 && !ReadLayoutNumber(row[12],out size)) return;
            if(row.Length==14 && !ReadLayoutNumber(row[13],out angle)) return;
            if(!int.TryParse(row[1],out kind) || !SpriteKind(kind) || !ReadLayoutNumber(row[2],out x) ||
                !ReadLayoutNumber(row[3],out y) || !int.TryParse(row[4],out treeIx) ||
                !ReadLayoutNumber(row[5],out rx) || !ReadLayoutNumber(row[6],out ry) || !ReadMount(row,7,sx,sy,out pin)) return;
            var d=new PlacedDecoration{Kind=(DecorationKind)kind,X=Limit(x*sx,0,width),Y=Limit(y*sy,0,height),
                Mount=pin,Angle=SignedAngle(angle),Magnification=Limit(size,.35,4),LocalX=Limit(rx,-.35,.35),LocalY=Limit(ry,-1.02,-.08)};
            if(treeIx>=0 && treeIx<trees.Count) {d.Tree=trees[treeIx];d.Hidden=d.Tree.Hidden;SetTreePosition(d);}
            else {d.LocalX=0; d.LocalY=0;}
            if(d.Mount.Support!=null && !Banks.Contains(d.Mount.Support)) d.Hidden=true;
            if(d.Tree==null && !d.Hidden && d.Mount.Support!=null) {
                if(!d.Mount.Support.IsFloor) d.X=d.Mount.Support.X+d.Mount.Support.Width*d.Mount.Anchor;
                RestDecoration(d,d.Mount.Support);
            }
            items.Add(d);
        }

        private static bool LightHit(double x,double y,double px,double py,double radius)
        {
            double dx=x-px,dy=y-py; return dx*dx+dy*dy<=radius*radius;
        }
        internal LightString EditedLights {get{return selectedStrand!=null && !selectedStrand.Hidden && Lights.Contains(selectedStrand)?selectedStrand:null;}}
        internal bool LightControlsVisible {get{return ShowDecorationHandles && (Tool==PlayTool.Lights || Tool==PlayTool.Arrange ||
            (Tool==PlayTool.Decorate && SelectedDecoration==DecorationKind.Lights));}}

        internal Point StrandButton(LightString s,int index)
        {
            double middleX=(s.X1+s.X2)*.5,middleY=(s.Y1+s.Y2)*.5;
            // Beside steep cables, keep editing buttons clear of the bend grip.
            double left=Math.Abs(s.X2-s.X1)<55 ? (middleX+95<width?middleX+23:middleX-86) : middleX-31.5;
            left=Limit(left,10,Math.Max(10,width-73));
            double y=middleY-20>=10 ? middleY-20 : s.CurveY(.5)+21;
            return new Point(left+21*index,Limit(y,10,Math.Max(10,height-10)));
        }

        private bool SelectedFrame(out Rect frame,out Point pivot,out double angle)
        {
            frame=Rect.Empty;pivot=new Point();angle=0;
            if(!ShowDecorationHandles) return false;
            if(selectedTree!=null && !selectedTree.Hidden && Trees.Contains(selectedTree) &&
                (Tool==PlayTool.Arrange || Tool==PlayTool.Tree || (Tool==PlayTool.Decorate && SelectedDecoration==DecorationKind.Tree))) {
                double size=selectedTree.Size;
                frame=new Rect(selectedTree.X-size*.37,selectedTree.Y-size-3,size*.74,size+3);
                pivot=new Point(selectedTree.X,selectedTree.Y);angle=selectedTree.Angle;
            }
            else if(selectedItem!=null && !selectedItem.Hidden && Decorations.Contains(selectedItem) &&
                (Tool==PlayTool.Arrange || (Tool==PlayTool.Decorate && SelectedDecoration==selectedItem.Kind))) {
                double radius=Math.Max(11,20*selectedItem.Scale);
                frame=new Rect(selectedItem.X-radius,selectedItem.Y-radius,radius*2,radius*2);
                pivot=new Point(selectedItem.X,selectedItem.Y);angle=selectedItem.WorldAngle;
            }
            else if(selectedSled!=null && Sleds.Contains(selectedSled) && (Tool==PlayTool.Arrange || Tool==PlayTool.Sled)) {
                pivot=new Point(selectedSled.X,selectedSled.DisplayY);
                frame=new Rect(pivot.X-26,pivot.Y-18,52,23);
                angle=selectedSled.DisplayAngle;
            }
            else return false;
            if(angle!=0) {
                var transform=Matrix.Identity;transform.RotateAt(angle,pivot.X,pivot.Y);
                frame=Rect.Transform(frame,transform);
            }
            return true;
        }

        internal bool SizeHandle(out Rect frame,out Point handle)
        {
            Point pivot;double angle;handle=new Point();
            if(!SelectedFrame(out frame,out pivot,out angle) || selectedSled!=null) return false;
            handle=new Point(Limit(frame.Right,9,Math.Max(9,width-9)),Limit(frame.Top,9,Math.Max(9,height-9)));
            return true;
        }

        internal bool RotationHandle(out Point grip,out Point anchor)
        {
            Rect frame;Point pivot;double angle;
            grip=anchor=new Point();
            if(!SelectedFrame(out frame,out pivot,out angle)) return false;
            if(frame.Top>=27) {
                anchor=new Point(frame.Left+frame.Width*.5,frame.Top);
                grip=new Point(anchor.X,anchor.Y-18);
            } else {
                bool left=frame.Left>=27;
                anchor=new Point(left?frame.Left:frame.Right,frame.Top+frame.Height*.5);
                grip=new Point(anchor.X+(left?-18:18),anchor.Y);
            }
            grip=new Point(Limit(grip.X,9,Math.Max(9,width-9)),Limit(grip.Y,9,Math.Max(9,height-9)));
            return true;
        }

        private bool GrabTransformControl(PlayTool tool,double x,double y)
        {
            if(tool!=PlayTool.Arrange && tool!=PlayTool.Tree && tool!=PlayTool.Decorate && tool!=PlayTool.Sled) return false;
            Rect frame;Point grip,pivot;double angle;
            if(!SelectedFrame(out frame,out pivot,out angle)) return false;
            scaleCenterX=pivot.X;scaleCenterY=pivot.Y;
            Point anchor;
            if(RotationHandle(out grip,out anchor) && LightHit(x,y,grip.X,grip.Y,9)) {
                editGrip=EditGrip.Rotate;
                startAngle=angle;
                startBearing=Math.Atan2(y-pivot.Y,x-pivot.X);
                return true;
            }
            if(!SizeHandle(out frame,out grip) || !LightHit(x,y,grip.X,grip.Y,9)) return false;
            editGrip=EditGrip.Size;
            startSize=selectedTree!=null?selectedTree.Size:selectedItem.Magnification;
            startDistance=Math.Max(1,(new Point(x,y)-new Point(scaleCenterX,scaleCenterY)).Length);
            return true;
        }

        private void SetSelectedSize(double size)
        {
            if(selectedTree!=null) {
                selectedTree.Size=Limit(size,35,160);
                if(selectedTree.Support!=null) RestTree(selectedTree,selectedTree.Support);
                foreach(var item in Decorations) if(item.Tree==selectedTree) SetTreePosition(item);
            } else if(selectedItem!=null) {
                selectedItem.Magnification=Limit(size,.35,4);
                SnowBank support=selectedItem.Mount.Support;
                if(support!=null) RestDecoration(selectedItem,support);
            }
        }

        private void MoveEditGrip(double x,double y)
        {
            if(editGrip==EditGrip.Bend && selectedStrand!=null) {
                double baseline=(selectedStrand.Y1+selectedStrand.Y2)*.5;
                selectedStrand.Bend=Limit(y-baseline,0,Math.Min(512,Math.Max(0,height-baseline)));
            } else if(editGrip==EditGrip.Size) {
                double distance=(new Point(x,y)-new Point(scaleCenterX,scaleCenterY)).Length;
                SetSelectedSize(startSize*distance/startDistance);
            } else if(editGrip==EditGrip.Rotate) {
                double dx=x-scaleCenterX,dy=y-scaleCenterY;
                if(dx*dx+dy*dy<9) return;
                SetSelectedAngle(startAngle+(Math.Atan2(dy,dx)-startBearing)*180/Math.PI);
            }
        }

        private void SetSelectedAngle(double worldAngle)
        {
            if(selectedTree!=null) {
                selectedTree.Angle=SignedAngle(worldAngle);
                if(selectedTree.Support!=null) RestTree(selectedTree,selectedTree.Support);
                foreach(var d in Decorations) if(d.Tree==selectedTree) SetTreePosition(d);
            } else if(selectedItem!=null) {
                selectedItem.Angle=SignedAngle(worldAngle-(selectedItem.Tree==null?0:selectedItem.Tree.Angle));
                if(selectedItem.Mount.Support!=null) RestDecoration(selectedItem,selectedItem.Mount.Support);
            } else if(selectedSled!=null) selectedSled.ManualTilt=SignedAngle(worldAngle-selectedSled.Angle*180/Math.PI);
        }

        internal bool AdjustPropAngleAt(double x,double y,int steps)
        {
            if(steps==0 || draggingProps) return false;
            var item=DecorationAt(x,y);
            if(item==null && StringAt(x,y)!=null) return false;
            var sled=item==null?SledAt(x,y):null;
            var tree=item==null && sled==null?TreeAt(x,y):null;
            if(item==null && sled==null && tree==null) return false;
            ClearPropSelection();selectedItem=item;selectedTree=tree;selectedSled=sled;
            double angle=item!=null ? item.WorldAngle : sled!=null ? sled.DisplayAngle : tree.Angle;
            SetSelectedAngle(angle+15*steps);
            return true;
        }

        internal bool AdjustPropSizeAt(double x,double y,int steps)
        {
            if(steps==0 || draggingProps) return false;
            var item=DecorationAt(x,y);
            var strand=item==null?StringAt(x,y):null;
            var tree=item==null && strand==null?TreeAt(x,y):null;
            if(item==null && tree==null && strand==null) return false;
            double factor=Math.Pow(1.16,Limit(steps,-8,8));
            ClearPropSelection();
            selectedItem=item;selectedTree=tree;selectedStrand=strand;
            if(strand!=null) strand.BulbScale=Limit(strand.BulbScale*factor,LightString.MinimumBulbScale,LightString.MaximumBulbScale);
            else SetSelectedSize((tree!=null?tree.Size:item.Magnification)*factor);
            return true;
        }

        private bool GrabLightControl(double x,double y)
        {
            LightString selected=EditedLights;
            if(selected!=null && LightControlsVisible) {
                Point trash=StrandButton(selected,0),color=StrandButton(selected,1);
                if(LightHit(x,y,trash.X,trash.Y,8)) {
                    Lights.Remove(selected); ClearPropSelection(); suppressLightUp=true; return true;
                }
                if(LightHit(x,y,color.X,color.Y,8)) {
                    int palette=selected.Palette<0 ? LightPalette : selected.Palette;
                    selected.Palette=(palette+1)%3;
                    suppressLightUp=true;return true;
                }
                for(int i=2;i<4;i++) {
                    Point button=StrandButton(selected,i);
                    if(!LightHit(x,y,button.X,button.Y,9)) continue;
                    double size=selected.BulbScale*(i==3?1.25:.8);
                    selected.BulbScale=Limit(size,LightString.MinimumBulbScale,LightString.MaximumBulbScale);
                    suppressLightUp=true;return true;
                }
            }
            for(int i=Lights.Count-1;i>=0;i--) {
                var s=Lights[i];
                if(s.Hidden)continue;
                bool left=LightHit(x,y,s.X1,s.Y1,9);
                if(!left && !LightHit(x,y,s.X2,s.Y2,9)) continue;
                ClearPropSelection();draggedLights=selectedStrand=s; dragLightPin=true; dragLeftPin=left; return true;
            }
            if(selected!=null && LightControlsVisible && LightHit(x,y,(selected.X1+selected.X2)*.5,selected.CurveY(.5),8)) {
                editGrip=EditGrip.Bend;return true;
            }
            return false;
        }

        private void MoveLightControl(double x,double y)
        {
            var s=draggedLights;
            x=Limit(x,0,width); y=Limit(y,0,height);
            if(dragLeftPin) {s.X1=x;s.Y1=y;s.Left=new LightPin();}
            else {s.X2=x;s.Y2=y;s.Right=new LightPin();}
            if(s.X1>s.X2) {OrderPins(s);dragLeftPin=!dragLeftPin;}
        }

        private void LandLightControl()
        {
            var s=draggedLights;
            if(dragLeftPin) {s.Left=Pin(s.X1,s.Y1);PositionPin(s.Left,ref s.X1,ref s.Y1);}
            else {s.Right=Pin(s.X2,s.Y2);PositionPin(s.Right,ref s.X2,ref s.Y2);}
            OrderPins(s);
        }
    }

    internal static partial class SnowArtwork
    {
        private static readonly Geometry RotateArrow=MakeRotateArrow();
        private static Geometry MakeRotateArrow()
        {
            var arrow=Geometry.Parse("M 3.2,-1 A 3.6,3.6 0 1 0 3.05,2.1 M 3.2,-3.6 L 3.2,-.65 .35,-.8");
            arrow.Freeze();return arrow;
        }

        internal static void DrawDecorations(DrawingContext dc,SnowScene scene)
        {
            foreach(var d in scene.Decorations) {
                if(d.Hidden)continue;
                double size=44*d.Scale;
                if(d.WorldAngle!=0) dc.PushTransform(new RotateTransform(d.WorldAngle,d.X,d.Y));
                dc.DrawImage(DecorationArt.Icon(d.Kind),new Rect(d.X-size*.5,d.Y-size*.5,size,size));
                if(d.WorldAngle!=0) dc.Pop();
            }
            Rect frame;Point grip;
            if(scene.SizeHandle(out frame,out grip)) {
                dc.DrawRoundedRectangle(null,DecorationArt.Frame,frame,3,3);
                dc.DrawEllipse(DecorationArt.Grip,DecorationArt.Edge,grip,7,7);
                dc.DrawLine(DecorationArt.Cross,new Point(grip.X-3,grip.Y+3),new Point(grip.X+3,grip.Y-3));
                dc.DrawLine(DecorationArt.Cross,new Point(grip.X+.2,grip.Y-3),new Point(grip.X+3,grip.Y-3));
                dc.DrawLine(DecorationArt.Cross,new Point(grip.X+3,grip.Y-3),new Point(grip.X+3,grip.Y-.2));
            }
            Point anchor;
            if(scene.RotationHandle(out grip,out anchor)) {
                dc.DrawLine(DecorationArt.Frame,anchor,grip);
                dc.DrawEllipse(DecorationArt.Grip,DecorationArt.Edge,grip,7,7);
                dc.PushTransform(new TranslateTransform(grip.X,grip.Y));
                dc.DrawGeometry(null,DecorationArt.Cross,RotateArrow);dc.Pop();
            }
            if(!scene.LightControlsVisible) return;
            var current=scene.EditedLights;
            foreach(var s in scene.Lights) {
                if(s.Hidden)continue;
                dc.DrawEllipse(Brushes.White,DecorationArt.Handle,new Point(s.X1,s.Y1),4,4);
                dc.DrawEllipse(Brushes.White,DecorationArt.Handle,new Point(s.X2,s.Y2),4,4);
                if(s!=current) continue;
                Point bend=new Point((s.X1+s.X2)*.5,s.CurveY(.5));
                dc.DrawEllipse(DecorationArt.Grip,DecorationArt.Edge,bend,6.5,6.5);
                dc.DrawLine(DecorationArt.Cross,new Point(bend.X-2.7,bend.Y),new Point(bend.X,bend.Y+2.5));
                dc.DrawLine(DecorationArt.Cross,new Point(bend.X,bend.Y+2.5),new Point(bend.X+2.7,bend.Y));
                Point trash=scene.StrandButton(s,0),palette=scene.StrandButton(s,1);
                double x=trash.X,y=trash.Y;
                dc.DrawEllipse(DecorationArt.Remove,DecorationArt.Edge,trash,7,7);
                dc.DrawLine(DecorationArt.Cross,new Point(x-2.5,y-2.5),new Point(x+2.5,y+2.5));
                dc.DrawLine(DecorationArt.Cross,new Point(x-2.5,y+2.5),new Point(x+2.5,y-2.5));
                dc.DrawEllipse(DecorationArt.Grip,DecorationArt.Edge,palette,7,7);
                dc.DrawEllipse(Brushes.Gold,null,new Point(palette.X-2,palette.Y-1),2,2);
                dc.DrawEllipse(Brushes.DeepPink,null,new Point(palette.X+2,palette.Y-1),2,2);
                dc.DrawEllipse(Brushes.Turquoise,null,new Point(palette.X,palette.Y+2.1),2,2);
                for(int i=2;i<4;i++) {
                    Point button=scene.StrandButton(s,i);
                    dc.DrawEllipse(DecorationArt.Grip,DecorationArt.Edge,button,8,8);
                    dc.DrawLine(DecorationArt.Cross,new Point(button.X-3,button.Y),new Point(button.X+3,button.Y));
                    if(i==3) dc.DrawLine(DecorationArt.Cross,new Point(button.X,button.Y-3),new Point(button.X,button.Y+3));
                }
            }
        }
    }
}
