using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;

namespace Frostpane
{
    // The original vector art includes transparent padding. Build the contact profile
    // from painted paths, in the same coordinate system and orientation as the renderer.
    internal sealed class DecorationFootprint
    {
        private const double Resolution = .45;
        private static readonly Dictionary<DecorationKind,List<Point[]>> outlines=new Dictionary<DecorationKind,List<Point[]>>();
        private static readonly ConditionalWeakTable<object,DecorationFootprint> poses=new ConditionalWeakTable<object,DecorationFootprint>();
        private double angle=double.NaN;
        private DecorationKind kind;
        private Point[] bottom;
        private double[] tops;
        private double bottomY;
        private SnowBank lastBank;
        private int lastRevision;
        private double lastX,lastScale,lastBankX,lastBankY,lastY;

        internal static DecorationFootprint For(object item,DecorationKind kind,double angle)
        {
            var pose=poses.GetOrCreateValue(item);
            if(pose.kind!=kind || pose.angle!=angle) pose.Build(kind,angle);
            return pose;
        }

        private static bool Solid(Brush brush)
        {
            if(brush==null || brush.Opacity<.45) return false;
            var solid=brush as SolidColorBrush;
            return solid==null || solid.Color.A*brush.Opacity>=115;
        }

        private static void AddGeometry(List<Point[]> contours,Geometry geometry,Matrix transform)
        {
            PathGeometry path=geometry.GetFlattenedPathGeometry(.07,ToleranceType.Absolute);
            Matrix m=path.Transform==null?Matrix.Identity:path.Transform.Value; m.Append(transform);
            foreach(PathFigure figure in path.Figures) {
                var points=new List<Point>(); points.Add(m.Transform(figure.StartPoint));
                foreach(PathSegment segment in figure.Segments) {
                    var poly=segment as PolyLineSegment;
                    if(poly!=null) foreach(Point p in poly.Points) points.Add(m.Transform(p));
                    else points.Add(m.Transform(((LineSegment)segment).Point));
                }
                if(points.Count>1) contours.Add(points.ToArray());
            }
        }

        private static void Collect(List<Point[]> contours,Drawing drawing,Matrix transform)
        {
            var group=drawing as DrawingGroup;
            if(group!=null) {
                Matrix local=group.Transform==null?Matrix.Identity:group.Transform.Value; local.Append(transform);
                foreach(Drawing child in group.Children) Collect(contours,child,local);
                return;
            }
            var shape=drawing as GeometryDrawing;
            if(shape==null) return;
            if(Solid(shape.Brush)) AddGeometry(contours,shape.Geometry,transform);
            if(shape.Pen!=null && Solid(shape.Pen.Brush))
                AddGeometry(contours,shape.Geometry.GetWidenedPathGeometry(shape.Pen,.07,ToleranceType.Absolute),transform);
        }

        private void Build(DecorationKind newKind,double newAngle)
        {
            List<Point[]> contours;
            if(!outlines.TryGetValue(newKind,out contours)) {
                contours=new List<Point[]>();
                if(newKind==DecorationKind.Tree) Collect(contours,SnowArtwork.TreeBodyDrawing(),Matrix.Identity);
                else {
                    var centered=Matrix.Identity;centered.Translate(-22,-22);
                    Collect(contours,DecorationArt.Icon(newKind).Drawing,centered);
                }
                outlines.Add(newKind,contours);
            }
            var rotation=Matrix.Identity; rotation.Rotate(newAngle);
            // Each narrow column stores its lowest piece of paint. Keep all extreme
            // vertices as candidates while sampling the straight segments between them.
            var columns=new Dictionary<int,Point>();
            var ceilings=new Dictionary<int,double>();
            bottomY=double.NegativeInfinity;
            foreach(Point[] contour in contours) {
                Point previous=rotation.Transform(contour[contour.Length-1]);
                foreach(Point local in contour) {
                    Point next=rotation.Transform(local);
                    int n=Math.Max(1,(int)Math.Ceiling(Math.Abs(next.X-previous.X)/Resolution));
                    for(int i=1;i<=n;i++) {
                        Point p=previous+(next-previous)*((double)i/n);
                        int index=(int)Math.Round(p.X/Resolution);
                        Point old;
                        if(!columns.TryGetValue(index,out old) || p.Y>old.Y) columns[index]=p;
                        double high;
                        if(!ceilings.TryGetValue(index,out high) || p.Y<high) ceilings[index]=p.Y;
                        bottomY=Math.Max(bottomY,p.Y);
                    }
                    previous=next;
                }
            }
            bottom=new Point[columns.Count];tops=new double[columns.Count];
            int column=0;
            foreach(var pair in columns) {
                bottom[column]=pair.Value;tops[column]=ceilings[pair.Key];column++;
            }
            angle=newAngle;kind=newKind;lastBank=null;
        }

        internal double RestY(SnowBank bank,double x,double scale)
        {
            if(bank==lastBank && bank.Revision==lastRevision && x==lastX && scale==lastScale &&
                lastBankX==bank.X && lastBankY==bank.Y) return lastY;
            double y=double.PositiveInfinity;
            foreach(Point point in bottom) {
                double sample=x+point.X*scale;
                if(sample>=bank.X && sample<=bank.X+bank.Width)
                    y=Math.Min(y,bank.Y-bank.PaintedHeightAt(sample)-point.Y*scale);
            }
            if(double.IsPositiveInfinity(y)) y=bank.Y-bank.PaintedHeightAt(x)-bottomY*scale;
            lastY=y;lastBank=bank;lastRevision=bank.Revision;lastScale=scale;lastX=x;
            lastBankX=bank.X;lastBankY=bank.Y;
            return y;
        }

        internal double BottomOffset(double scale) { return bottomY*scale; }

        internal bool Slice(double top,double baseY,out double left,out double right)
        {
            left=double.PositiveInfinity;right=double.NegativeInfinity;
            for(int i=0;i<bottom.Length;i++) {
                if(bottom[i].Y<top || tops[i]>baseY)continue;
                left=Math.Min(left,bottom[i].X);right=Math.Max(right,bottom[i].X);
            }
            return right>=left;
        }
    }

    internal sealed partial class SnowScene
    {
        private static DecorationFootprint Footprint(PlacedDecoration d)
        {
            return DecorationFootprint.For(d,d.Kind,d.WorldAngle);
        }

        internal static void RestDecoration(PlacedDecoration d,SnowBank support)
        {
            d.Y=Footprint(d).RestY(support,d.X,d.Scale);
        }

        internal static void RestTree(WinterTree tree,SnowBank support)
        {
            // An upright tree is already rooted at its trunk foot. For a tilted tree
            // the boughs, star or trunk may touch before that pivot reaches the snow.
            tree.Y=tree.Angle==0 ? SnowSurfaceY(support,tree.X) :
                DecorationFootprint.For(tree,DecorationKind.Tree,tree.Angle).RestY(support,tree.X,tree.DisplaySize/96);
        }

        private SnowBank SupportForDecoration(PlacedDecoration d)
        {
            var footprint=Footprint(d);
            SnowBank nearest=null,below=null;
            double nearDistance=double.PositiveInfinity,dropDistance=double.PositiveInfinity;
            foreach(SnowBank bank in Banks) {
                if(d.X<bank.X || d.X>bank.X+bank.Width) continue;
                double distance=footprint.RestY(bank,d.X,d.Scale)-d.Y;
                // A release inside a drift (or at the bottom of the screen) sets the
                // ornament down on its surface, including hanging decorations.
                bool touching=distance<0 && (bank.IsFloor || d.Y<=bank.Y+5);
                if((Math.Abs(distance)<=35 || touching) && Math.Abs(distance)<nearDistance) {
                    nearDistance=Math.Abs(distance);nearest=bank;
                }
                if(distance>=0 && distance<dropDistance) {dropDistance=distance;below=bank;}
            }
            return nearest ?? (StandsOnSnow(d.Kind) ? below??floor : null);
        }
    }
}
