using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Frostpane
{
    internal sealed partial class SnowScene
    {
        private const string LayoutTag = "FrostpaneDecor/1";
        private const int MaxLayoutLength = 65536;
        private string layoutBeforeDrag;

        private static string LayoutNumber(double value)
        {
            return value.ToString("0.#####", CultureInfo.InvariantCulture);
        }

        // Fractions drive world positions. Rounding a mount by five decimals
        // can move the recovered fallback position on a long window edge.
        private static string LayoutFactor(double value)
        {
            return value.ToString("R",CultureInfo.InvariantCulture);
        }

        private static bool ReadLayoutNumber(string text, out double value)
        {
            value = 0;
            return text.Length < 32 && double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value)
                && Math.Abs(value) <= 1000000;
        }

        private static void WriteMount(StringBuilder text, SnowBank bank, double anchor)
        {
            if (bank == null) { text.Append("\t-\t0\t0\t0\t0"); return; }
            // Ledge IDs can contain delimiters.
            string id = Convert.ToBase64String(Encoding.UTF8.GetBytes(bank.Id));
            text.Append('\t').Append(id).Append('\t').Append(LayoutFactor(anchor))
                .Append('\t').Append(LayoutNumber(bank.X)).Append('\t').Append(LayoutNumber(bank.Y))
                .Append('\t').Append(LayoutNumber(bank.Width));
        }

        public string ExportDecorations()
        {
            if (layoutBeforeDrag != null && draggingProps) return layoutBeforeDrag;
            if (width < 1 || height < 1 || (Trees.Count == 0 && Lights.Count == 0 && Decorations.Count==0 && Snowmen.Count==0)) return "";
            var text = new StringBuilder();
            text.Append(LayoutTag).Append('\t').Append(LayoutNumber(width)).Append('\t').Append(LayoutNumber(height));
            foreach (WinterTree tree in Trees)
            {
                // A resting tree's placement stays stable as flakes accumulate under it.
                double baseY = tree.Support == null ? tree.Y : tree.Support.Y;
                text.Append("\nT\t").Append(LayoutNumber(tree.X)).Append('\t').Append(LayoutNumber(baseY))
                    .Append('\t').Append(LayoutNumber(tree.Size)).Append('\t').Append(tree.Style.ToString(CultureInfo.InvariantCulture));
                WriteMount(text, tree.Support, tree.Anchor);
                if(tree.Angle!=0) text.Append('\t').Append(LayoutFactor(tree.Angle));
            }
            foreach (LightString strand in Lights)
            {
                text.Append("\nL\t").Append(LayoutNumber(strand.X1)).Append('\t').Append(LayoutNumber(strand.Y1));
                WriteMount(text, strand.Left.Support, strand.Left.Anchor);
                text.Append('\t').Append(LayoutNumber(strand.X2)).Append('\t').Append(LayoutNumber(strand.Y2));
                WriteMount(text, strand.Right.Support, strand.Right.Anchor);
                text.Append('\t').Append(LayoutNumber(strand.Bend)).Append('\t').Append(LayoutNumber(strand.BulbScale))
                    .Append('\t').Append(strand.Palette.ToString(CultureInfo.InvariantCulture));
            }
            ExportCatalog(text);
            foreach(Snowman man in Snowmen) {
                SnowBank support=man.Held ? null : PropSurfaceBelow(man.X,man.Y,2.5);
                if(support!=null && Math.Abs(SnowSurfaceY(support,man.X)-man.Y)>2.5) support=null;
                text.Append("\nS\t").Append(LayoutNumber(man.X)).Append('\t').Append(LayoutNumber(support==null?man.Y:support.Y))
                    .Append('\t').Append(LayoutNumber(man.BaseRadius)).Append('\t').Append(LayoutNumber(man.MidRadius))
                    .Append('\t').Append(LayoutNumber(man.HeadRadius)).Append('\t').Append(man.Style.ToString(CultureInfo.InvariantCulture))
                    .Append('\t').Append(man.Facing<0?"-1":"1");
                WriteMount(text,support,support==null?0:Limit((man.X-support.X)/support.Width,0,1));
            }
            return text.ToString();
        }

        private bool ReadMount(string[] row, int start, double sx, double sy, out LightPin mount)
        {
            mount = new LightPin();
            string encoded = row[start];
            if (encoded == "-") return true;
            if (encoded.Length == 0 || encoded.Length > 256) return false;
            double anchor, x, y, span;
            if (!ReadLayoutNumber(row[start+1], out anchor) || anchor < 0 || anchor > 1 ||
                !ReadLayoutNumber(row[start+2], out x) || !ReadLayoutNumber(row[start+3], out y) ||
                !ReadLayoutNumber(row[start+4], out span) || span <= 0) return false;
            string id;
            try { id = Encoding.UTF8.GetString(Convert.FromBase64String(encoded)); }
            catch (FormatException) { return false; }
            if (id == "floor") { mount.Support = floor; mount.Anchor = anchor; return true; }
            double oldX = x*sx, oldY = y*sy, oldWidth = span*sx;
            SnowBank bank;
            if (windows.TryGetValue(id, out bank))
            {
                double sizeChange = bank.Width / oldWidth;
                bool shifted = Math.Abs(bank.X - oldX) > width*.35 || Math.Abs(bank.Y - oldY) > height*.40;
                if ((sizeChange < .16 || sizeChange > 6) && shifted) return true;
                mount.Support = bank; mount.Anchor = anchor;
            }
            else
            {
                // Another window may have split a formerly visible edge into different segments.
                int slash = id.IndexOf('/');
                if (slash < 1) return true;
                string owner = id.Substring(0, slash+1);
                double targetX = oldX + oldWidth * anchor;
                foreach (SnowBank part in Banks)
                {
                    if (!part.Id.StartsWith(owner, StringComparison.Ordinal) || Math.Abs(part.Y - oldY) > 32 ||
                        targetX < part.X - 3 || targetX > part.X + part.Width + 3) continue;
                    mount.Support = part;
                    mount.Anchor = Limit((targetX - part.X) / part.Width, 0, 1);
                    break;
                }
                if(mount.Support==null && WindowRemainsOpen(id)) {
                    mount.Support=new SnowBank{Id=id,X=oldX,Y=oldY,Width=oldWidth,Heights=new double[2]};
                    mount.Anchor=anchor;
                }
            }
            return true;
        }

        public void ImportDecorations(string data)
        {
            if (floor == null || width < 1 || height < 1 || data == null || data.Length > MaxLayoutLength) return;
            if (data.Length == 0) { ReplaceDecorations(new List<WinterTree>(),new List<LightString>(),new List<PlacedDecoration>(),new List<Snowman>()); return; }
            string[] lines = data.Split(new char[] {'\n'}, 313);
            string[] header = lines[0].TrimEnd('\r').Split('\t');
            double oldWidth, oldHeight;
            if (header.Length != 3 || header[0] != LayoutTag ||
                !ReadLayoutNumber(header[1], out oldWidth) || !ReadLayoutNumber(header[2], out oldHeight) ||
                oldWidth < 1 || oldWidth > 100000 || oldHeight < 1 || oldHeight > 100000) return;
            double sx = width / oldWidth, sy = height / oldHeight;
            var trees = new List<WinterTree>();
            var lights = new List<LightString>();
            var catalog = new List<PlacedDecoration>();
            var figures = new List<Snowman>();
            for (int i = 1; i < lines.Length; i++)
            {
                if (lines[i].Length > 1024) continue;
                string[] row = lines[i].TrimEnd('\r').Split('\t');
                if(row[0]=="D") {ReadCatalogRow(row,sx,sy,trees,catalog);continue;}
                double x, y;
                if (row.Length < 3 || !ReadLayoutNumber(row[1], out x) || !ReadLayoutNumber(row[2], out y)) continue;
                x = Limit(x * sx, 0, width); y = Limit(y * sy, 0, height);
                LightPin mount;
                if(row[0]=="S" && row.Length==13 && figures.Count<70) {
                    double b,m,h,f; int style;
                    if(!ReadLayoutNumber(row[3],out b) || !ReadLayoutNumber(row[4],out m) || !ReadLayoutNumber(row[5],out h) ||
                        !int.TryParse(row[6],out style) || !ReadLayoutNumber(row[7],out f) || !ReadMount(row,8,sx,sy,out mount)) continue;
                    if(mount.Support!=null) {
                        if(!mount.Support.IsFloor) x=mount.Support.X+mount.Anchor*mount.Support.Width;
                        y=SnowSurfaceY(mount.Support,x);
                    }
                    figures.Add(new Snowman{X=x,Y=y,BaseRadius=Limit(b,8,50),MidRadius=Limit(m,5,50),
                        HeadRadius=Limit(h,4,50),Style=(int)Limit(style,0,2),Facing=f<0?-1:1});
                }
                else if (row[0] == "T" && (row.Length == 10 || row.Length == 11) && trees.Count < 40)
                {
                    double size,angle=0; int style;
                    if(row.Length==11 && !ReadLayoutNumber(row[10],out angle)) continue;
                    if (!ReadLayoutNumber(row[3], out size) || !int.TryParse(row[4], NumberStyles.Integer,
                        CultureInfo.InvariantCulture, out style) || !ReadMount(row, 5, sx, sy, out mount)) continue;
                    var tree = new WinterTree { X=x, Y=y, Size=Limit(size, 35, 160), Style=(int)Limit(style, 0, 11),
                        Support=mount.Support, Anchor=mount.Anchor, Angle=SignedAngle(angle) };
                    if (tree.Support != null)
                    {
                        tree.Hidden=!Banks.Contains(tree.Support);
                        if (!tree.Support.IsFloor) tree.X = tree.Support.X + tree.Support.Width * tree.Anchor;
                        RestTree(tree,tree.Support);
                    }
                    trees.Add(tree);
                }
                else if (row[0] == "L" && (row.Length == 15 || row.Length == 18) && lights.Count < 40)
                {
                    double x2, y2;
                    LightPin right;
                    if (!ReadMount(row, 3, sx, sy, out mount) || !ReadLayoutNumber(row[8], out x2) ||
                        !ReadLayoutNumber(row[9], out y2) || !ReadMount(row, 10, sx, sy, out right)) continue;
                    var strand = new LightString { X1=x, Y1=y, X2=Limit(x2*sx,0,width), Y2=Limit(y2*sy,0,height),
                        Left=mount, Right=right };
                    if(row.Length==18) {
                        double bend,scale;int palette;
                        if(!ReadLayoutNumber(row[15],out bend) || !ReadLayoutNumber(row[16],out scale) ||
                            !int.TryParse(row[17],NumberStyles.Integer,CultureInfo.InvariantCulture,out palette)) continue;
                        strand.Bend=bend<0?-1:Limit(bend*sy,0,512);strand.BulbScale=Limit(scale,.55,2.8);
                        strand.Palette=(int)Limit(palette<0?LightPalette:palette,0,2);
                    } else {
                        strand.Bend=Math.Min(22,Math.Abs(strand.X2-strand.X1)*.10);
                        strand.Palette=(int)Limit(LightPalette,0,2);
                    }
                    PositionPin(mount, ref strand.X1, ref strand.Y1);
                    PositionPin(right, ref strand.X2, ref strand.Y2);
                    strand.Hidden=(mount.Support!=null && !Banks.Contains(mount.Support)) || (right.Support!=null && !Banks.Contains(right.Support));
                    OrderPins(strand);
                    lights.Add(strand);
                }
            }
            if (trees.Count + lights.Count + catalog.Count + figures.Count > 0) ReplaceDecorations(trees, lights,catalog,figures);
        }

        private void ReplaceDecorations(List<WinterTree> trees, List<LightString> lights,List<PlacedDecoration> catalog,List<Snowman> figures)
        {
            if (draggingProps) PropsCancel();
            Trees.Clear(); Trees.AddRange(trees);
            Lights.Clear(); Lights.AddRange(lights);
            Decorations.Clear(); Decorations.AddRange(catalog); ClearPropSelection();
            if(heldMan!=null) {heldMan.Held=false;heldMan=null;}
            Snowmen.Clear();Snowmen.AddRange(figures);
        }
    }
}
