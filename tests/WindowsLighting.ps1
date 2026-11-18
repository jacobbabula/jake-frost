param([string]$AppDirectory=(Join-Path $PSScriptRoot '..\dist\Jake-Frost'))
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -File $PSCommandPath -AppDirectory $AppDirectory
    if ($LASTEXITCODE) {throw "Windows lighting checks failed ($LASTEXITCODE)."}
    return
}
Add-Type -AssemblyName PresentationCore,PresentationFramework
$app=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath (Join-Path $AppDirectory 'JakeFrost.exe')).Path)
$sceneType=$app.GetType('Frostpane.SnowScene',$true)
$instance=[Reflection.BindingFlags]'Instance,NonPublic,Public'
$draw=$app.GetType('Frostpane.SnowArtwork').GetMethod('Draw',[Reflection.BindingFlags]'Static,NonPublic')
function New-Scene {
    $s=[Activator]::CreateInstance($sceneType,@(42))
    $s.Resize(640,400)
    return $s
}
function Invoke-Scene($scene,[string]$name,[object[]]$values) {
    $sceneType.GetMethod($name,$instance).Invoke($scene,$values)
}
function Field($obj,[string]$name) {
    return ,$obj.GetType().GetField($name,$instance).GetValue($obj)
}
function Set-Field($obj,[string]$name,$value) {
    $obj.GetType().GetField($name,$instance).SetValue($obj,$value)
}
function Set-Mode($scene,[string]$property,[string]$name) {
    $p=$sceneType.GetProperty($property,$instance)
    $p.SetValue($scene,[Enum]::Parse($p.PropertyType,$name),$null)
}
function Set-Lightning($scene,[bool]$on) {
    $sceneType.GetProperty('LightningEnabled',$instance).SetValue($scene,$on,$null)
}
function Tick($scene,[int]$frames) {
    for($i=0;$i -lt $frames;$i++) {$scene.Step(1.0/30,2,0)}
}
function Fingerprint($scene) {
    $visual=New-Object Windows.Media.DrawingVisual
    $dc=$visual.RenderOpen()
    try {$null=$draw.Invoke($null,@($dc.PSObject.BaseObject,$scene))} finally {$dc.Close()}
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(640,400,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $pixels=New-Object byte[] (640*400*4)
    $bitmap.CopyPixels($pixels,640*4,0)
    $hash=[Security.Cryptography.SHA256]::Create()
    try {return [Convert]::ToBase64String($hash.ComputeHash($pixels))} finally {$hash.Dispose()}
}
function Play-Click($scene,[double]$x,[double]$y) {
    Invoke-Scene $scene 'PlayDown' @($x,$y)
    Invoke-Scene $scene 'PlayUp' @($x,$y)
}
$scene=New-Scene
Set-Mode $scene Weather Sakura
Set-Field $scene SnowVolume 0
Set-Mode $scene Tool Lights
Set-Field $scene ShowDecorationHandles $true
Set-Field $scene NewBulbScale 3.0
Invoke-Scene $scene PlayDown @(100.0,90.0)
Invoke-Scene $scene PlayMove @(440.0,140.0)
Invoke-Scene $scene PlayUp @(440.0,140.0)
$lights=Field $scene Lights
if($lights.Count -ne 1 -or (Field $lights[0] BulbScale) -ne 3.0) {throw 'New string ignored selected bulb size.'}
$strand=$lights[0]
foreach($i in 1..4) {
    $plus=Invoke-Scene $scene StrandButton @($strand,3)
    Play-Click $scene $plus.X $plus.Y
}
if((Field $strand BulbScale) -ne 5 -or $lights.Count -ne 1) {throw 'Desktop + control did not grow this strand to 500%.'}
$minus=Invoke-Scene $scene StrandButton @($strand,2)
Play-Click $scene $minus.X $minus.Y
if((Field $strand BulbScale) -ne 4) {throw 'Desktop minus did not shrink the same strand.'}
$saved=$scene.ExportDecorations()
$restored=New-Scene
$restored.ImportDecorations($saved)
if((Field (Field $restored Lights)[0] BulbScale) -ne 4) {throw 'Lights lost their size on restore.'}
Set-Field $scene ShowDecorationHandles $false
$start=Fingerprint $scene
Tick $scene 26
if((Fingerprint $scene) -eq $start) {throw 'Twinkle did not change the rendered pixels.'}
Set-Field $scene TwinkleLights $false
$start=Fingerprint $scene
Tick $scene 26
if((Fingerprint $scene) -ne $start) {throw 'Lights kept twinkling after the option was switched off.'}
Write-Output 'PASS Desktop + and minus, 500% bulb size, saved strand, animated and steady WPF pixels.'

$storm=New-Scene
Set-Mode $storm Weather Rain
Tick $storm 60
if((Field $storm LightningTime) -gt 0) {throw 'Lightning was active without opt-in.'}
Set-Lightning $storm $true
Tick $storm 40
$bolt=Field $storm LightningBolt
if((Field $storm LightningTime) -le 0 -or !$bolt -or $bolt.Bounds.Height -lt 80) {throw 'Rain did not start a visible screen-sized strike.'}
$strike=Fingerprint $storm
Set-Lightning $storm $false
if((Field $storm LightningTime) -ne 0 -or (Fingerprint $storm) -eq $strike) {throw 'Disabling lightning did not remove a rendered strike.'}
Set-Lightning $storm $true
Set-Mode $storm Weather Leaves
Tick $storm 40
if((Field $storm LightningTime) -gt 0) {throw 'Lightning escaped rain mode.'}
Set-Mode $storm Weather Rain
Tick $storm 40
$bolt=Field $storm LightningBolt
Tick $storm 720
if([object]::ReferenceEquals($bolt,(Field $storm LightningBolt))) {throw 'Rain did not schedule another distinct strike.'}
Write-Output 'PASS Opt-in rain lightning, branching rendered strike, immediate dismissal, other weather modes, and recurrent strikes.'

$treeScene=New-Scene
Set-Mode $treeScene Weather Sakura
Set-Field $treeScene SnowVolume 0
Set-Mode $treeScene Tool Tree
Play-Click $treeScene 320 300
Tick $treeScene 60
$tree=(Field $treeScene Trees)[0]
$first=Fingerprint $treeScene
Tick $treeScene 27
if((Fingerprint $treeScene) -eq $first) {throw 'Tree lights did not twinkle.'}
Set-Field $treeScene TwinkleLights $false
$first=Fingerprint $treeScene
Tick $treeScene 27
if((Fingerprint $treeScene) -ne $first) {throw 'The master twinkle switch left tree lights animated.'}
Set-Field $treeScene TwinkleLights $true
$first=Fingerprint $treeScene
Tick $treeScene 27
if((Fingerprint $treeScene) -eq $first) {throw 'The master switch lost the original twinkling tree design.'}
$trim=$app.GetType('Frostpane.TreeTrim')
Set-Field $tree Trim ([Enum]::Parse($trim,'Baubles,Lights'))
$first=Fingerprint $treeScene
Tick $treeScene 27
if((Fingerprint $treeScene) -ne $first) {throw 'Master twinkle overrode a tree designed with steady lights.'}
Set-Field $treeScene NewTreeTrim ([Enum]::Parse($trim,'Baubles'))
Set-Field $treeScene NewTreePalette 2
Set-Mode $treeScene Tool StyleTree
Play-Click $treeScene $tree.X ($tree.Y-$tree.Size*.45)
if((Field $tree Trim).ToString() -ne 'Baubles' -or (Field $tree Palette) -ne 2) {throw 'Desktop tree styling missed the clicked tree.'}
$first=Fingerprint $treeScene
Tick $treeScene 27
if((Fingerprint $treeScene) -ne $first) {throw 'Tree without lights still twinkled.'}
$copy=New-Scene
$copy.ImportDecorations($treeScene.ExportDecorations())
$other=(Field $copy Trees)[0]
if((Field $other Trim).ToString() -ne 'Baubles' -or (Field $other Palette) -ne 2) {throw 'A styled tree changed after scene restore.'}
$dress=Invoke-Scene $treeScene ExportTreeDress @($tree)
Set-Field $other Trim ([Enum]::Parse($trim,'All'))
Invoke-Scene $copy ImportTreeDress @($other,$dress)
if((Field $other Trim).ToString() -ne 'Baubles' -or (Field $other Palette) -ne 2) {throw 'Tree gift lost its trim or colors.'}
Write-Output 'PASS Tree twinkle, apply to a planted tree, steady rendering, scene persistence and gift appearance.'
