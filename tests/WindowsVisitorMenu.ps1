param([Parameter(Mandatory=$true)][string]$AppDirectory,[string]$TreeEditorScreenshot)
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
    if($TreeEditorScreenshot) {
        $press=[Windows.Controls.Button]::ClickEvent
        $panel.FindName('DecorateTreeButton').RaiseEvent([Windows.RoutedEventArgs]::new($press))
        $choice=$panel.FindName('TreeChoice')
        if($choice.Items.Count -ne 2 -or $choice.SelectedIndex -ne 1){throw 'Workshop did not plant and select the first desktop tree.'}
        $ornaments=$panel.FindName('TreeOrnament')
        foreach($name in 'Gold bauble','Bells','Candy cane') {
            $ornaments.SelectedItem=@($ornaments.Items | Where-Object {$_.Content -eq $name})[0]
            $panel.FindName('HangTreeOrnament').RaiseEvent([Windows.RoutedEventArgs]::new($press))
        }
        $panel.FindName('TreePalette').SelectedIndex=2
        $panel.FindName('WorkshopTab').IsChecked=$true
        $panel.FindName('DecorateTreeButton').RaiseEvent([Windows.RoutedEventArgs]::new($press))
        if($choice.Items.Count -ne 2 -or $choice.SelectedIndex -ne 1 -or $panel.FindName('TreeEditorStatus').Text -ne '3 hand-hung ornaments'){
            throw 'Opening the editor again lost the chosen tree or planted another one.'
        }
        $panel.UpdateLayout()
        $element=$panel.Content
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][Math]::Ceiling($element.ActualWidth),[int][Math]::Ceiling($element.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($element)
        $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $dest=[IO.Path]::GetFullPath($TreeEditorScreenshot)
        $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))
        $stream=[IO.File]::Create($dest)
        try{$encoder.Save($stream)}finally{$stream.Dispose()}
        Write-Output 'PASS Workshop planted one tree on an empty desktop and reopened that same tree with three ornaments. Captured the shipping WPF panel.'
    }
    $twinkle=$panel.FindName('TwinkleLightsOption')
    if(!$twinkle.IsChecked){throw 'Twinkling must start enabled in a new profile.'}
    $twinkle.IsChecked=$false
    $depth=$panel.FindName('Depth')
    $depth.Value=320
    if($depth.Value -ne 320 -or $panel.FindName('DepthLabel').Text -ne '320 DIP'){throw 'The drift slider did not reach the larger depth.'}
    $prefs=$type.GetField('prefs',$flags).GetValue($app)
    $prefs.GetType().GetMethod('Save',$flags).Invoke($prefs,@())
    $reopened=[Activator]::CreateInstance($prefs.GetType(),$true)
    $prefs.GetType().GetMethod('Load',$flags).Invoke($reopened,@())
    if($prefs.GetType().GetField('TwinkleLights',$flags).GetValue($reopened)){throw 'The desktop light switch did not survive reopening.'}
    if($prefs.GetType().GetField('Depth',$flags).GetValue($reopened) -ne 320){throw 'The larger drift depth did not survive reopening.'}
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
