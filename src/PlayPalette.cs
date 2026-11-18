using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Frostpane
{
    internal sealed class PlayPalette : UniformGrid
    {
        private sealed class ToolButton : RadioButton
        {
            internal Action Repeat;
            protected override void OnClick()
            {
                bool alreadySelected=IsChecked==true;
                base.OnClick();
                if (alreadySelected) Repeat();
            }
        }
        private sealed class Choice
        {
            public readonly PlayTool Tool;
            public readonly string Label, Hint, Ink, Icon;
            public Choice(PlayTool tool,string label,string hint,string ink,string icon)
            { Tool=tool; Label=label; Hint=hint; Ink=ink; Icon=icon; }
        }
        private static readonly Choice[] Choices = {
            new Choice(PlayTool.Roll,"Roll","Roll through a drift, then stack three balls to make a snowman.","#36769A","M4,14 A6,6 0 1 0 16,14 A6,6 0 1 0 4,14 M6,12 Q7,9 10,10 M11,4 A3,3 0 1 0 17,4 A3,3 0 1 0 11,4"),
            new Choice(PlayTool.Puff,"Puff","Tap snow or sweep through a drift to scatter a cloud of powder.","#36769A","M3,15 C0,12 3,8 6,9 C5,4 12,3 14,7 C18,5 21,10 18,13 M4,18 L3,19 M10,15 L10,18 M15,15 L17,18 M1,5 L3,6 M17,2 L16,4"),
            new Choice(PlayTool.Pile,"Pile","Click or brush along a ledge or the ground to shape a snow hill.","#47806D","M1,17 Q4,17 7,11 Q11,2 14,10 Q16,16 20,17 Z M8,11 Q10,10 11,8 Q12,10 14,10"),
            new Choice(PlayTool.Throw,"Throw","Grab a snowball or pack a fresh one. Flick and release to throw it.","#996747","M12,10 A4.3,4.3 0 1 0 20.6,10 A4.3,4.3 0 1 0 12,10 M2,11 L9,9 M5,15 L11,12 M1,16 L3,15 M6,6 L11,6"),
            new Choice(PlayTool.Tree,"Tree","Click to plant a Christmas tree. Drag a planted tree to move it.","#3E7966","M10,1 L5,8 L8,7 L3,13 L6,12 L1.5,17 L18.5,17 L14,12 L17,13 L12,7 L15,8 Z M10,17 L10,20"),
            new Choice(PlayTool.Lights,"Lights","Drag to hang lights. Move the end pins to stretch or tilt, drag the center pin to bow, and use + or − to size the bulbs.","#9C7129","M1,4 Q10,12 20,4 M4,6 L4,9 M2.5,11 A1.5,2.3 0 1 0 5.5,11 A1.5,2.3 0 1 0 2.5,11 M10,8 L10,12 M8.5,14 A1.5,2.3 0 1 0 11.5,14 A1.5,2.3 0 1 0 8.5,14 M17,6 L17,9 M15.5,11 A1.5,2.3 0 1 0 18.5,11 A1.5,2.3 0 1 0 15.5,11"),
            new Choice(PlayTool.Sled,"Sled","Click to place a sled. Tap to push it, or drag and release it on a hill.","#925E54","M2,9 L14,9 Q17,9 17,6 M5,9 L6,14 M12,9 L13,14 M1,15 L15,15 Q20,15 20,11"),
            new Choice(PlayTool.Arrange,"Arrange","Drag a corner to resize or the circular arrow to rotate. Shift + scroll turns an item 15°. Drag the ends of a light string to tilt it.","#417E86","M2,7 L2,2 L7,2 M13,2 L18,2 L18,7 M18,13 L18,18 L13,18 M7,18 L2,18 L2,13 M6,14 L14,6 M9,6 L14,6 L14,11"),
            new Choice(PlayTool.Erase,"Remove","Click a decoration or a sled to take it down.","#885F73","M3,12 L12,3 Q13,2 14,3 L18,7 Q19,8 18,9 L10,17 L7,17 Z M6,9 L13,15 M10,17 L19,17")
        };
        private readonly Dictionary<PlayTool,RadioButton> buttons=new Dictionary<PlayTool,RadioButton>();
        private bool syncing;
        internal static void AddToolCommands(Action<PlayTool,string> add)
        {
            foreach(Choice item in Choices) add(item.Tool,item.Label);
        }
        internal static string Hint(PlayTool tool)
        {
            if(tool==PlayTool.StyleTree) return "Click a planted tree to apply your colors, baubles and lights.";
            if(tool==PlayTool.PickTree) return "Click the tree you want to decorate, or click empty snow to plant one.";
            foreach (Choice item in Choices) if (item.Tool==tool) return item.Hint;
            return "Click to place your decoration. Drag it to move it or hang it on a tree.";
        }
        internal PlayPalette(int columns,Action<PlayTool> choose)
        {
            Columns=columns;
            foreach (Choice item in Choices) {
                var icon=new Path {Data=Geometry.Parse(item.Icon),Stretch=Stretch.Uniform,Width=17,Height=17,
                    Stroke=(Brush)new BrushConverter().ConvertFromString(item.Ink),StrokeThickness=1.35,
                    StrokeLineJoin=PenLineJoin.Round,StrokeStartLineCap=PenLineCap.Round,StrokeEndLineCap=PenLineCap.Round};
                var row=new StackPanel {Orientation=Orientation.Horizontal};
                row.Children.Add(icon); row.Children.Add(new TextBlock {Text=item.Label,Foreground=Brushes.MidnightBlue,
                    FontFamily=new FontFamily("Segoe UI"),FontSize=12,Margin=new Thickness(5,0,0,0),VerticalAlignment=VerticalAlignment.Center});
                var radio=new ToolButton {Content=row,ToolTip=item.Hint,Cursor=Cursors.Hand,Margin=new Thickness(2)};
                radio.SetResourceReference(Control.TemplateProperty,"ToolTile");
                AutomationProperties.SetName(radio,item.Label); AutomationProperties.SetAutomationId(radio,"Tool_"+item.Tool);
                PlayTool tool=item.Tool; radio.Checked+=delegate { if (!syncing) choose(tool); };
                radio.Repeat=delegate { choose(tool); };
                buttons.Add(tool,radio); Children.Add(radio);
            }
        }
        internal void SelectTool(PlayTool tool)
        {
            syncing=true;
            try {
                RadioButton selected;
                if (buttons.TryGetValue(tool,out selected)) selected.IsChecked=true;
                else foreach (var button in buttons.Values) button.IsChecked=false;
            } finally { syncing=false; }
        }
    }
}
