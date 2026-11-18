param([Parameter(Mandatory=$true)][string]$AppDirectory)
$ErrorActionPreference='Stop'
if($env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows'){
    throw 'This interactive test uses an isolated hosted Windows desktop.'
}
$env:JAKEFROST_SETTINGS_DIR=Join-Path $env:RUNNER_TEMP ('landscape-'+[guid]::NewGuid().ToString('N'))
Add-Type -AssemblyName PresentationFramework
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class LandscapeShell {
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr window);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr handle,StringBuilder name,int length);
    public static string ClassName(IntPtr window) {var s=new StringBuilder(80);GetClassName(window,s,s.Capacity);return s.ToString();}
}
'@
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
        }
        $clock.SelectedIndex=0
    }
    $combo.SelectedIndex=0
    if([LandscapeShell]::IsWindow($handle)){throw 'Wallpaper still attached after selecting System wallpaper.'}
    if((Get-ItemProperty -LiteralPath $registry).Wallpaper -ne $original){throw 'The system wallpaper path changed.'}
    Write-Output 'PASS both landscapes, manual night and local time, real Explorer child window and original wallpaper restoration.'
} finally {
    if($app.MainWindow){$type.GetMethod('Quit',$flags).Invoke($app,@())}
    $gift.Dispose();$wake.Dispose()
}
