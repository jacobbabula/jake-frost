param([Parameter(Mandatory=$true)][string]$AppDirectory)
$ErrorActionPreference='Stop'
if($env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows'){
    throw 'This interactive test uses an isolated hosted Windows desktop.'
}
$env:JAKEFROST_SETTINGS_DIR=Join-Path $env:RUNNER_TEMP ('landscape-'+[guid]::NewGuid().ToString('N'))
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class LandscapeShell {
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr window);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll",EntryPoint="GetWindowLongW")] public static extern int Style(IntPtr h,int index);
    [DllImport("user32.dll")] public static extern IntPtr SetParent(IntPtr child,IntPtr parent);
    [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h,uint direction);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent,IntPtr after,string cls,string title);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr CreateWindowEx(int ex,string cls,string title,uint style,int x,int y,int w,int h,IntPtr parent,IntPtr menu,IntPtr module,IntPtr arg);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd,IntPtr dc);
    [DllImport("gdi32.dll")] static extern int GetPixel(IntPtr dc,int x,int y);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr handle,StringBuilder name,int length);
    public static string ClassName(IntPtr window) {var s=new StringBuilder(80);GetClassName(window,s,s.Capacity);return s.ToString();}
    public static bool Between(IntPtr top,IntPtr child,IntPtr bottom) {
        for(IntPtr h=GetWindow(top,2);h!=IntPtr.Zero && h!=bottom;h=GetWindow(h,2)) if(h==child)return true;
        return false;
    }
    public static IntPtr Fixture(bool raised) {
        // The sample popup lives only on this test runner. A white patch at its
        // origin also establishes whether a composed display is available to capture.
        var hwnd=CreateWindowEx(0x08000088,"STATIC","Wallpaper composition fixture",0x94000006,
            40,40,320,180,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
        if(hwnd==IntPtr.Zero)throw new Exception("Could not create a wallpaper composition fixture.");
        SetWindowPos(hwnd,new IntPtr(-1),40,40,320,180,0x0050);return hwnd;
    }
    public static IntPtr Child(IntPtr parent,int size) {
        return CreateWindowEx(0,"STATIC",null,0x50000006,0,0,size,size,parent,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
    }
    public static int[] Sample() {
        var dc=GetDC(IntPtr.Zero);
        try {
            var values=new int[24];int at=0;
            for(int y=0;y<4;y++)for(int x=0;x<6;x++)values[at++]=GetPixel(dc,62+x*51,60+y*42);
            return values;
        } finally {ReleaseDC(IntPtr.Zero,dc);}
    }
    public static int Difference(int[] a,int[] b) {
        int changed=0;
        for(int i=0;i<a.Length;i++) {
            if(a[i]<0 || b[i]<0)continue;
            int d=0;
            for(int shift=0;shift<=16;shift+=8)d+=Math.Abs(((a[i]>>shift)&255)-((b[i]>>shift)&255));
            if(d>=48)changed++;
        }
        return changed;
    }
}
'@
function Wait-WallpaperFrame {
    for($i=0;$i -lt 6;$i++) {
        [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
        Start-Sleep -Milliseconds 35
    }
}
$exe=(Resolve-Path (Join-Path $AppDirectory 'JakeFrost.exe')).Path
$asm=[Reflection.Assembly]::LoadFrom($exe)
$type=$asm.GetType('Frostpane.FrostApp',$true)
$flags=[Reflection.BindingFlags]'NonPublic,Instance'
$app=[Activator]::CreateInstance($type,$true)
$app.ShutdownMode='OnExplicitShutdown'
$wake=New-Object Threading.AutoResetEvent($false);$gift=New-Object Threading.AutoResetEvent($false)
$registry='HKCU:\Control Panel\Desktop'
$original=(Get-ItemProperty -LiteralPath $registry).Wallpaper
try {
    $type.GetMethod('Start',$flags).Invoke($app,@($wake.PSObject.BaseObject,$gift.PSObject.BaseObject,$false))
    $panel=$app.MainWindow
    $panel.FindName('WeatherTab').IsChecked=$true
    $expander=$panel.FindName('WallpaperHost').Child;$expander.IsExpanded=$true
    $combo=$expander.Content.Children[0].Children[0]
    $clock=$expander.Content.Children[0].Children[1]
    foreach($selection in 1,2) {
        $combo.SelectedIndex=$selection;$clock.SelectedIndex=6
        $wall=$type.GetField('wallpaper',$flags).GetValue($app)
        $layers=$wall.GetType().GetField('layers',$flags).GetValue($wall)
        if($layers.Count -lt 1){throw 'Explorer did not expose a usable wallpaper surface.'}
        foreach($layer in $layers.Values) {
            $window=$layer.GetType().GetField('Window',$flags).GetValue($layer)
            $handle=$window.Handle
            $shell=[LandscapeShell]::ClassName([LandscapeShell]::GetParent($handle))
            if($shell -notin 'WorkerW','Progman'){throw "Unexpected landscape parent: $shell"}
            if(!$window.RootVisual){throw 'Missing native landscape renderer.'}
            $raised=$shell -eq 'Progman'
            if((([LandscapeShell]::Style($handle,-20) -band 0x80000) -ne 0) -ne $raised){throw 'The live HWND has the wrong composition style for this Explorer version.'}
            if($raised){
                $parent=[LandscapeShell]::GetParent($handle)
                $icons=[LandscapeShell]::FindWindowEx($parent,[IntPtr]::Zero,'SHELLDLL_DefView',$null)
                $paper=[LandscapeShell]::FindWindowEx($parent,$icons,'WorkerW',$null)
                if($paper -eq [IntPtr]::Zero -or ![LandscapeShell]::Between($icons,$handle,$paper)){throw 'Wallpaper is outside the Explorer composition order.'}
                if(![LandscapeShell]::SetWindowPos($handle,[IntPtr]1,0,0,0,0,0x13)){throw 'Could not displace the test surface.'}
                $type.GetMethod('UpdateWallpaper',$flags).Invoke($app,@())
                if(![LandscapeShell]::Between($icons,$handle,$paper)){throw 'Wallpaper did not recover after Explorer stacking changed.'}
            }
        }
        $clock.SelectedIndex=0
    }
    # Exercise both WPF composition paths, including the one the runner's shell
    # does not use. Compare the composed desktop pixels after changing the actual art.
    $wallType=$wall.GetType()
    $hostType=$wallType.GetNestedType('DesktopHost',[Reflection.BindingFlags]::NonPublic)
    $createLayer=$wallType.GetMethod('CreateLayer',[Reflection.BindingFlags]'NonPublic,Static')
    $sceneEnum=$asm.GetType('Frostpane.WallpaperScene')
    $timeEnum=$asm.GetType('Frostpane.WallpaperTime')
    foreach($raised in $false,$true) {
        $frame=[LandscapeShell]::Fixture($raised);$fixtureLayer=$null
        try {
            $layout=[Activator]::CreateInstance($hostType)
            $hostType.GetField('Parent',$flags).SetValue($layout,$frame)
            if($raised) {
                $paper=[LandscapeShell]::Child($frame,320);$icons=[LandscapeShell]::Child($frame,11)
                $null=[LandscapeShell]::SetWindowPos($icons,[IntPtr]::Zero,0,0,0,0,0x13)
                $hostType.GetField('Icons',$flags).SetValue($layout,$icons)
                $hostType.GetField('Wallpaper',$flags).SetValue($layout,$paper)
            }
            Wait-WallpaperFrame
            $calibration=[LandscapeShell]::Sample()
            $capture=(@($calibration | Where-Object {$_ -eq 16777215}).Count -ge 16)
            $bounds=New-Object Drawing.Rectangle(40,40,320,180)
            $fixtureLayer=$createLayer.Invoke($null,@($layout,$bounds))
            if(!$fixtureLayer){throw "Could not create the test composition layer (raised=$raised)."}
            $fixtureWindow=$fixtureLayer.GetType().GetField('Window',$flags).GetValue($fixtureLayer)
            if((([LandscapeShell]::Style($fixtureWindow.Handle,-20) -band 0x80000) -ne 0) -ne $raised){throw 'Synthetic host did not receive the required WPF surface.'}
            if($raised -and ![LandscapeShell]::Between($icons,$fixtureWindow.Handle,$paper)){throw 'Synthetic raised wallpaper is outside the icon band.'}
            $art=$fixtureWindow.RootVisual
            $day=$wallType.GetField('bitmap',$flags).GetValue($wall);$night=$wallType.GetField('night',$flags).GetValue($wall)
            foreach($time in 3,6){
                $art.GetType().GetMethod('Configure',$flags).Invoke($art,@($day,$night,[Enum]::ToObject($sceneEnum,2),[Enum]::ToObject($timeEnum,$time),$false))
                $art.InvalidateVisual();Wait-WallpaperFrame
                if($art.ActualWidth -lt 1 -or $art.ActualHeight -lt 1){throw 'The wallpaper renderer has no client area.'}
                if($time -eq 3){$dayPixels=[LandscapeShell]::Sample()}else{$nightPixels=[LandscapeShell]::Sample()}
            }
            if($capture){
                if([LandscapeShell]::Difference($dayPixels,$nightPixels) -lt 6){throw "Day and night never reached the composed desktop (raised=$raised)."}
                Write-Output "PASS visible day/night desktop pixels (raised=$raised)."
            } else {Write-Output "Hosted desktop capture unavailable for pixel sampling (raised=$raised)."}
            if(!$raised) {
                $displaced=$handle
                if([LandscapeShell]::SetParent($displaced,$frame) -eq [IntPtr]::Zero){throw 'Could not displace the real wallpaper layer.'}
                $type.GetMethod('UpdateWallpaper',$flags).Invoke($app,@())
                if([LandscapeShell]::IsWindow($displaced) -or $layers.Count -lt 1){throw 'A reparented wallpaper was not recreated on the Explorer desktop.'}
                $replacement=($layers.Values | Select-Object -First 1)
                $handle=$replacement.GetType().GetField('Window',$flags).GetValue($replacement).Handle
            }
        } finally {
            if($fixtureLayer){$fixtureWindow.Dispose()}
            $null=[LandscapeShell]::DestroyWindow($frame)
        }
    }
    $combo.SelectedIndex=0
    if([LandscapeShell]::IsWindow($handle)){throw 'Wallpaper still attached after selecting System wallpaper.'}
    if((Get-ItemProperty -LiteralPath $registry).Wallpaper -ne $original){throw 'The system wallpaper path changed.'}
    Write-Output 'PASS both landscapes, manual night and local time, real Explorer child window and original wallpaper restoration.'
} finally {
    if($app.MainWindow){$type.GetMethod('Quit',$flags).Invoke($app,@())}
    $gift.Dispose();$wake.Dispose()
}
