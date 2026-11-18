using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace Frostpane
{
    internal sealed partial class FrostApp
    {
        private bool compact;
        private double expandedWidth;

        private void ConnectCompactPanel()
        {
            Control<Button>("MinimizeButton").Click += delegate { SetCompact(true); };
            var restore=Control<Button>("RestoreButton");
            Point origin=new Point();
            restore.PreviewMouseLeftButtonDown+=delegate(object sender,MouseButtonEventArgs e) {
                origin=e.GetPosition(restore);
            };
            restore.PreviewMouseMove+=delegate(object sender,MouseEventArgs e) {
                if(!restore.IsMouseCaptured || e.LeftButton!=MouseButtonState.Pressed) return;
                Point here=e.GetPosition(restore);
                if(Math.Abs(here.X-origin.X)<SystemParameters.MinimumHorizontalDragDistance &&
                   Math.Abs(here.Y-origin.Y)<SystemParameters.MinimumVerticalDragDistance) return;
                restore.ReleaseMouseCapture();panel.DragMove();e.Handled=true;
            };
            restore.Click += delegate {
                if (building) OpenPage("Workshop"); else OpenPanel();
            };
            Control<Button>("DoneButton").Click += delegate { SetBuild(false); };
            Control<DockPanel>("CompactPanel").MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs e) {
                if (e.Handled || e.LeftButton != MouseButtonState.Pressed) return;
                if (e.ClickCount == 2) OpenPanel(); else panel.DragMove();
            };
            panel.StateChanged += delegate {
                if (panel.WindowState != WindowState.Minimized || quitting) return;
                panel.WindowState = WindowState.Normal;
                SetCompact(true);
            };
        }

        private void SetCompact(bool value)
        {
            if (compact != value) {
                // Keep the same top-left corner and native window when switching layouts.
                double left = panel.Left, top = panel.Top;
                if (value) expandedWidth = panel.Width;
                panel.WindowStartupLocation = WindowStartupLocation.Manual;
                compact = value;
                Control<DockPanel>("ExpandedPanel").Visibility = value ? Visibility.Collapsed : Visibility.Visible;
                Control<DockPanel>("CompactPanel").Visibility = value ? Visibility.Visible : Visibility.Collapsed;
                panel.Width = value ? (building ? 124 : 42) : expandedWidth;
                if (!double.IsNaN(left) && !double.IsNaN(top)) {panel.Left = left; panel.Top = top;}
            }
            if (!value) return;
            panel.Width = building ? 124 : 42;
            var restore = Control<Button>("RestoreButton");
            restore.ToolTip=building?"Choose another desktop tool":"Open Jake Frost. Drag to move.";
            var done = Control<Button>("DoneButton");
            done.Visibility = building ? Visibility.Visible : Visibility.Collapsed;
            done.Content = escapeRegistered ? "Done · Esc" : "Done";
            done.ToolTip=building?PlayPalette.Hint(prefs.Tool):null;
        }
    }
}
