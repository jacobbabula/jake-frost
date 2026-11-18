param([Parameter(Mandatory=$true)][string]$AppDirectory)
$ErrorActionPreference='Stop'
if ($env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {throw 'Run the interactive menu test on the disposable Windows desktop.'}
$env:JAKEFROST_SETTINGS_DIR=Join-Path $env:RUNNER_TEMP ('visitor-menu-'+[guid]::NewGuid().ToString('N'))
Add-Type -AssemblyName PresentationFramework,System.Windows.Forms
$image=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath (Join-Path $AppDirectory 'JakeFrost.exe')).Path)
$type=$image.GetType('Frostpane.FrostApp',$true)
$flags=[Reflection.BindingFlags]'NonPublic,Instance'
$app=[Activator]::CreateInstance($type,$true)
$app.ShutdownMode='OnExplicitShutdown'
$wake=New-Object Threading.AutoResetEvent($false)
$gift=New-Object Threading.AutoResetEvent($false)
try {
    $type.GetMethod('Start',$flags).Invoke($app,@($wake.PSObject.BaseObject,$gift.PSObject.BaseObject,$false))
    $panel=$app.MainWindow
    $panel.Left=48;$panel.Top=24
    $panel.UpdateLayout()
    $tray=$type.GetField('menu',$flags).GetValue($app)
    $twinkle=$panel.FindName('TwinkleLightsOption')
    if(!$twinkle.IsChecked){throw 'Twinkling must start enabled in a new profile.'}
    $twinkle.IsChecked=$false
    $prefs=$type.GetField('prefs',$flags).GetValue($app)
    $prefs.GetType().GetMethod('Save',$flags).Invoke($prefs,@())
    $reopened=[Activator]::CreateInstance($prefs.GetType(),$true)
    $prefs.GetType().GetMethod('Load',$flags).Invoke($reopened,@())
    if($prefs.GetType().GetField('TwinkleLights',$flags).GetValue($reopened)){throw 'The desktop light switch did not survive reopening.'}
    foreach ($visitor in 'Send snowplough','Send snowmen','Send Yeti','Send Santa','Blizzard') {
        $x=$panel.Left;$y=$panel.Top
        $panel.Hide()
        $command=@($tray.Items | Where-Object Text -eq $visitor)
        if ($command.Count -ne 1) {throw "Missing tray command $visitor."}
        $command[0].PerformClick()
        $panel.UpdateLayout()
        $restore=$panel.FindName('RestoreButton')
        if (!$panel.IsVisible -or !$restore.IsVisible -or $panel.ActualWidth -gt 45 -or $panel.ActualHeight -gt 45 -or
            [Windows.Automation.AutomationProperties]::GetName($restore) -ne 'Restore Jake Frost' -or
            [Math]::Abs($x-$panel.Left) -gt 1 -or [Math]::Abs($y-$panel.Top) -gt 1) {
            throw "$visitor failed to show the Restore bar at the previous anchor."
        }
        $restore.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
        if (!$panel.FindName('ExpandedPanel').IsVisible) {throw 'Restore did not reopen the panel.'}
    }
    Write-Output 'PASS the actual tray commands restore a previously hidden panel as a visible anchored bar.'
} finally {
    if ($app.MainWindow) {$type.GetMethod('Quit',$flags).Invoke($app,@())}
    $wake.Dispose();$gift.Dispose()
}
