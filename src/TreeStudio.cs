using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Frostpane
{
    internal sealed partial class SnowScene
    {
        internal WinterTree DesignedTree;
        internal Action<WinterTree> TreePicked;

        internal WinterTree PlantForEditor(double x,double y)
        {
            if(floor==null || Trees.Count>=40)return null;
            var tree=new WinterTree{X=Limit(x,20,Math.Max(20,width-20)),Y=y,Size=104,
                Style=random.Next(12),Trim=NewTreeTrim,Palette=NewTreePalette};
            Trees.Add(tree);PlantTree(tree);return tree;
        }
        internal bool HangOrnament(WinterTree tree,DecorationKind kind)
        {
            if(tree==null || tree.Hidden || !Trees.Contains(tree) || Decorations.Count>=160 ||
               kind==DecorationKind.Tree || kind==DecorationKind.Lights)return false;
            int n=Decorations.Count(item=>item.Tree==tree);
            // Stagger the rows and switch sides on each branch.
            double down=.26+.55*((n*.38196601125)%1);
            double reach=(.055+.22*down)*(n%2==0?1:-1);
            var itemToHang=new PlacedDecoration{Kind=kind,Tree=tree,LocalX=reach,LocalY=down-1,Magnification=.72};
            SetTreePosition(itemToHang);Decorations.Add(itemToHang);return true;
        }
        internal bool RemoveLastOrnament(WinterTree tree)
        {
            if(tree==null || !Trees.Contains(tree))return false;
            int index=Decorations.FindLastIndex(d=>d.Tree==tree);
            if(index<0)return false;
            if(selectedItem==Decorations[index])ClearPropSelection();
            Decorations.RemoveAt(index);return true;
        }
    }

    internal sealed partial class FrostApp
    {
        private sealed class TreeChoice
        {
            internal Overlay Display;internal WinterTree Tree;
            internal string Label;
            public override string ToString(){return Label;}
        }
        private bool syncingTree;
        private Overlay treeDisplay;
        private WinterTree editingTree;
        private bool HasEditingTree {
            get{return treeDisplay!=null && overlays.Contains(treeDisplay) && !treeDisplay.Suspended && editingTree!=null &&
                !editingTree.Hidden && treeDisplay.Surface.Scene.Trees.Contains(editingTree);}
        }
        private void ConnectTreeDesigner()
        {
            Control<Button>("DecorateTreeButton").Click+=delegate{OpenTreeStudio(null,null);};
            var trees=Control<ComboBox>("TreeChoice");
            trees.DropDownOpened+=delegate{RefreshTreeChoices();};
            trees.SelectionChanged+=delegate {
                if(syncingTree)return;
                var pick=trees.SelectedItem as TreeChoice;if(pick==null)return;
                ChooseTree(pick.Display,pick.Tree);
            };
            var palette=Control<ComboBox>("TreePalette");
            palette.SelectionChanged+=delegate {
                if(syncingTree || palette.SelectedIndex<0)return;
                if(EditingTargetGone())return;
                if(HasEditingTree)editingTree.Palette=palette.SelectedIndex;
                else prefs.TreePalette=palette.SelectedIndex;
                FinishTreeChange();
            };
            BindTreeFlag("TreeBaubles",TreeTrim.Baubles);
            BindTreeFlag("TreeLights",TreeTrim.Lights);
            BindTreeFlag("TreeTwinkle",TreeTrim.Twinkle);
            var ornaments=Control<ComboBox>("TreeOrnament");
            foreach(DecorationKind kind in Enum.GetValues(typeof(DecorationKind)))
                if(kind!=DecorationKind.Tree && kind!=DecorationKind.Lights)
                    ornaments.Items.Add(new ComboBoxItem{Content=DecorationPicker.NameOf(kind),Tag=kind});
            ornaments.SelectedIndex=1;
            Control<Button>("HangTreeOrnament").Click+=delegate {
                if(EditingTargetGone() || !HasEditingTree)return;
                var choice=ornaments.SelectedItem as ComboBoxItem;
                if(choice==null)return;
                if(treeDisplay.Surface.Scene.HangOrnament(editingTree,(DecorationKind)choice.Tag))FinishTreeChange();
                else Control<TextBlock>("TreeEditorStatus").Text="The desktop decoration limit has been reached.";
            };
            Control<Button>("RemoveTreeOrnament").Click+=delegate {
                if(!EditingTargetGone() && HasEditingTree && treeDisplay.Surface.Scene.RemoveLastOrnament(editingTree))FinishTreeChange();
            };
            Control<Button>("PickTreeButton").Click+=delegate{ActivateTool(PlayTool.PickTree);};
            Control<Button>("PlantTreeButton").Click+=delegate{ActivateTool(PlayTool.Tree);};
            Control<Button>("RestyleTreeButton").Click+=delegate{
                if(HasEditingTree) {prefs.TreePalette=DesignPalette;prefs.TreeTrimOptions=DesignTrim;}
                ActivateTool(PlayTool.StyleTree);
            };
            Control<Expander>("TreeDesignBox").Expanded+=delegate{RefreshTreeChoices();};
            RefreshTreeChoices();
        }
        private void BindTreeFlag(string id,TreeTrim flag)
        {
            var box=Control<CheckBox>(id);
            RoutedEventHandler changed=delegate {
                if(syncingTree || EditingTargetGone())return;
                var value=box.IsChecked==true ? DesignTrim | flag : DesignTrim & ~flag;
                if(HasEditingTree)editingTree.Trim=value;
                else prefs.TreeTrimOptions=value;
                FinishTreeChange();
            };
            box.Checked+=changed;box.Unchecked+=changed;
        }
        private bool EditingTargetGone()
        {
            if(editingTree==null || HasEditingTree)return false;
            editingTree=null;treeDisplay=null;RefreshTreeChoices();
            Control<TextBlock>("TreeEditorStatus").Text="That tree moved off this desktop. Select another tree.";return true;
        }
        private int DesignPalette {get{return HasEditingTree?(editingTree.Palette<0?prefs.Palette:editingTree.Palette):prefs.TreePalette;}}
        private TreeTrim DesignTrim {get{return HasEditingTree?editingTree.Trim:prefs.TreeTrimOptions;}}
        private void FinishTreeChange()
        {
            if(HasEditingTree){treeDisplay.Surface.InvalidateVisual();SaveDecorations(treeDisplay);}
            else {ApplyPreferences();SaveSoon();}
            UpdateTreePreview();
        }
        private void ChooseTree(Overlay display,WinterTree tree)
        {
            treeDisplay=display;editingTree=tree;
            if(HasEditingTree){
                display.Surface.Scene.DesignedTree=tree;
                prefs.LastTreeMonitor=display.MonitorInfo.Id;SaveSoon();SaveDecorations(display);
            }
            UpdateTreePreview();
        }
        private void RefreshTreeChoices()
        {
            var list=Control<ComboBox>("TreeChoice");syncingTree=true;
            try {
                list.Items.Clear();list.Items.Add(new TreeChoice{Label="Defaults for new trees"});
                foreach(var display in overlays) {
                    if(display.Suspended)continue;
                    var scene=display.Surface.Scene;
                    for(int i=0;i<scene.Trees.Count;i++) {
                        var tree=scene.Trees[i];if(tree.Hidden)continue;
                        string side=tree.X<scene.SkyWidth*.33?"left":tree.X>scene.SkyWidth*.67?"right":"center";
                        var row=new TreeChoice{Display=display,Tree=tree,Label="Tree "+(i+1)+" · "+side+
                            (overlays.Count>1?" · Display "+(overlays.IndexOf(display)+1):"")};
                        list.Items.Add(row);if(tree==editingTree && display==treeDisplay)list.SelectedItem=row;
                    }
                }
                if(list.SelectedIndex<0){list.SelectedIndex=0;treeDisplay=null;editingTree=null;}
            } finally{syncingTree=false;}
            UpdateTreePreview();
        }
        private void OpenTreeStudio(Overlay display,WinterTree picked)
        {
            if(prefs.Weather==WeatherMode.Off)EnsureSnow();
            if(building)SetBuild(false);
            OpenPage("Decor");
            var editor=Control<Expander>("TreeDesignBox");editor.IsExpanded=true;
            Control<ScrollViewer>("Scroller").ScrollToTop();
            if(display==null || !overlays.Contains(display) || display.Suspended) {
                var restored=overlays.FirstOrDefault(o=>!o.Suspended && o.MonitorInfo.Id==prefs.LastTreeMonitor &&
                    o.Surface.Scene.Trees.Contains(o.Surface.Scene.DesignedTree) && !o.Surface.Scene.DesignedTree.Hidden);
                display=restored ?? CurrentMonitor();
                if(display!=null && !display.Surface.Scene.Trees.Any(t=>!t.Hidden))
                    display=overlays.FirstOrDefault(o=>!o.Suspended && o.Surface.Scene.Trees.Any(t=>!t.Hidden))??display;
            }
            if(display==null){RefreshTreeChoices();Control<TextBlock>("TreeEditorStatus").Text="Enable a display or leave fullscreen to decorate a tree.";return;}
            var scene=display.Surface.Scene;
            if(picked==null || picked.Hidden || !scene.Trees.Contains(picked)) {
                picked=scene.DesignedTree;
                if(picked==null || picked.Hidden || !scene.Trees.Contains(picked))picked=scene.Trees.FirstOrDefault(t=>!t.Hidden);
                if(picked==null)picked=scene.PlantForEditor(scene.SkyWidth*.68,scene.SkyHeight);
            }
            ChooseTree(display,picked);RefreshTreeChoices();
            if(picked==null)Control<TextBlock>("TreeEditorStatus").Text="Choose a visible tree, or make room for a new tree.";
            display.Surface.InvalidateVisual();
        }
        private void UpdateTreePreview()
        {
            bool old=syncingTree;syncingTree=true;
            try {
                bool live=HasEditingTree;TreeTrim trim=DesignTrim;int palette=DesignPalette;
                Control<ComboBox>("TreePalette").SelectedIndex=palette;
                Control<CheckBox>("TreeBaubles").IsChecked=(trim&TreeTrim.Baubles)!=0;
                Control<CheckBox>("TreeLights").IsChecked=(trim&TreeTrim.Lights)!=0;
                var twinkle=Control<CheckBox>("TreeTwinkle");twinkle.IsChecked=(trim&TreeTrim.Twinkle)!=0;
                twinkle.IsEnabled=(trim&TreeTrim.Lights)!=0 && prefs.TwinkleLights;
                if(Control<Expander>("TreeDesignBox").IsExpanded)
                    Control<Image>("TreePreview").Source=SnowArtwork.TreePreview(prefs.TwinkleLights?trim:trim&~TreeTrim.Twinkle,palette,
                        live?editingTree:null,live?treeDisplay.Surface.Scene:null);
                int count=live?treeDisplay.Surface.Scene.Decorations.Count(item=>item.Tree==editingTree):0;
                Control<StackPanel>("TreeOrnaments").Visibility=live?Visibility.Visible:Visibility.Collapsed;
                Control<Button>("RemoveTreeOrnament").IsEnabled=count>0;
                Control<TextBlock>("TreeEditorStatus").Text=(live?(count==1?"1 hand-hung ornament":count+" hand-hung ornaments"):"Choose a tree to hang individual ornaments.")+
                    (prefs.TwinkleLights?"":" · Master twinkle is off.");
            } finally {syncingTree=old;}
        }
    }
}
