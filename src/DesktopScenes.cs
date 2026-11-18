using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation;
using System.Windows.Media;

namespace Frostpane
{
    internal sealed partial class FrostApp
    {
        private LiveWallpaper wallpaper;
        private WallpaperScene wallpaperChoice;
        private WallpaperTime wallpaperTime;
        private bool wallpaperMoves=true;
        private TextBlock wallpaperStatus;
        private void ConnectScenes()
        {
            Control<Button>("ElfFightButton").Click+=delegate {BeginFight(false);};
            Control<Button>("SnowmanFightButton").Click+=delegate {BeginFight(true);};
            string file=Path.Combine(Preferences.DirectoryName,"wallpaper.dat");
            try {
                if(File.Exists(file)) {
                    var lines=File.ReadAllLines(file); WallpaperScene s; WallpaperTime t; bool move;
                    if(lines.Length==3 && Enum.TryParse(lines[0],out s) && Enum.IsDefined(typeof(WallpaperScene),s) &&
                        Enum.TryParse(lines[1],out t) && Enum.IsDefined(typeof(WallpaperTime),t) && Boolean.TryParse(lines[2],out move)) {
                        wallpaperChoice=s;wallpaperTime=t;wallpaperMoves=move;
                    }
                }
            } catch(IOException) {} catch(UnauthorizedAccessException) {}
            var box=new StackPanel {Margin=new Thickness(0,6,0,8)};
            var grid=new Grid();grid.ColumnDefinitions.Add(new ColumnDefinition());grid.ColumnDefinitions.Add(new ColumnDefinition());
            var landscapes=WallpaperList(new[]{"System wallpaper","Switchback Station","Lantern Sound"},(int)wallpaperChoice,"Landscape");
            var times=WallpaperList(new[]{"Follow local time","Dawn","Morning","Midday","Golden hour","Dusk","Night"},(int)wallpaperTime,"Lighting");
            landscapes.Margin=new Thickness(0,0,6,0);Grid.SetColumn(times,1);grid.Children.Add(landscapes);grid.Children.Add(times);box.Children.Add(grid);
            var motion=new CheckBox {Content="Animate the landscape",IsChecked=wallpaperMoves,Margin=new Thickness(0,8,0,0)};
            box.Children.Add(motion);
            wallpaperStatus=new TextBlock {TextWrapping=TextWrapping.Wrap,FontSize=12,Margin=new Thickness(0,4,0,0)};
            box.Children.Add(wallpaperStatus);
            var expander=new Expander {Header="Desktop wallpaper",Content=box};
            Control<Border>("WallpaperHost").Child=expander;
            Action change=delegate {
                wallpaperChoice=(WallpaperScene)landscapes.SelectedIndex; wallpaperTime=(WallpaperTime)times.SelectedIndex;
                wallpaperMoves=motion.IsChecked==true;times.IsEnabled=motion.IsEnabled=wallpaperChoice!=WallpaperScene.Off;
                try {
                    Directory.CreateDirectory(Preferences.DirectoryName);
                    string temp=file+".new";File.WriteAllLines(temp,new[]{wallpaperChoice.ToString(),wallpaperTime.ToString(),wallpaperMoves.ToString()});
                    if(File.Exists(file)) File.Replace(temp,file,null); else File.Move(temp,file);
                } catch(IOException) {} catch(UnauthorizedAccessException) {}
                UpdateWallpaper();
            };
            times.IsEnabled=motion.IsEnabled=wallpaperChoice!=WallpaperScene.Off;
            landscapes.SelectionChanged+=delegate {change();};times.SelectionChanged+=delegate {change();};
            motion.Checked+=delegate {change();};motion.Unchecked+=delegate {change();};
        }
        private static ComboBox WallpaperList(string[] titles,int index,string label)
        {
            var list=new ComboBox {ItemsSource=titles,SelectedIndex=index,MinHeight=29,ToolTip=label};
            AutomationProperties.SetName(list,label);AutomationProperties.SetAutomationId(list,"Wallpaper"+label);
            return list;
        }
        private void UpdateWallpaper()
        {
            if(wallpaperChoice==WallpaperScene.Off && wallpaper==null) return;
            try {
                if(wallpaper==null) wallpaper=new LiveWallpaper();
                wallpaper.Update(wallpaperChoice,wallpaperTime,wallpaperMoves,paused||displayAsleep,
                    onBattery && prefs.SaveBattery,overlays.Select(o=>o.MonitorInfo).ToList(),prefs.HiddenScreens,prefs.PauseFullscreen);
                wallpaperStatus.Text=wallpaperChoice!=WallpaperScene.Off && !wallpaper.Available ?
                    "Waiting for the Windows desktop or an enabled display." : "";
                if(wallpaperChoice==WallpaperScene.Off) {wallpaper.Dispose();wallpaper=null;}
            } catch(Exception ex) {
                if(!(ex is IOException || ex is System.ComponentModel.Win32Exception || ex is InvalidOperationException || ex is System.Runtime.InteropServices.COMException)) throw;
                if(wallpaper!=null) wallpaper.Dispose();wallpaper=null;wallpaperStatus.Text="Windows could not display this landscape.";
            }
        }
        private void BeginFight(bool snowmen)
        {
            var target=DesktopForVisit();
            if(target==null) return;
            if(!target.Surface.Scene.StartFight(snowmen)) {
                OpenPage("Workshop");
                MessageBox.Show(panel,"Roll and stack three snowballs to build a snowman, or send a snowman to your desktop first.",
                    "Wake the snowmen",MessageBoxButton.OK,MessageBoxImage.Information);
            }
        }
    }
}
