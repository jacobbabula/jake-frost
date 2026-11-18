param(
    [Parameter(Mandatory=$true)][string]$SetupPath,
    [Parameter(Mandatory=$true)][string]$AppDirectory,
    [string]$CompilerPath,
    [string]$GiftPath
)
$ErrorActionPreference = 'Stop'
# This test exercises the real Start menu, Installed apps and file associations.
if ($env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Run this installation test on a disposable GitHub-hosted Windows runner.'
}
$setup = (Resolve-Path -LiteralPath $SetupPath).Path
$app = (Resolve-Path -LiteralPath $AppDirectory).Path
$installedDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\Jake Frost'
$installed = Join-Path $installedDir 'JakeFrost.exe'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Jake Frost.lnk'
$frostData = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Frostpane'
$extKey = 'HKCU:\Software\Classes\.fpgift'
$classKey = 'HKCU:\Software\Classes\JakeFrost.Gift'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JakeFrost.Desktop_is1'
$scratch = (New-Item -ItemType Directory -Path (Join-Path $env:RUNNER_TEMP ('Jake-Frost-'+[guid]::NewGuid().ToString('N')))).FullName
function Check([bool]$ok, [string]$message) {
    if (!$ok) {throw $message}
    Write-Output "PASS $message"
}
function RegistryDefault([string]$key) {
    (Get-Item -LiteralPath $key).GetValue('')
}
function New-NoteGift([string]$path) {
    $lines = @('FROSTPANE-GIFT-1',[guid]::NewGuid().ToString('N'),'','','QSBmcmllbmQ=','Note','SGVsbG8h','0','18','13','9','1','','END')
    [IO.File]::WriteAllText($path,($lines -join [char]10),[Text.UTF8Encoding]::new($false))
}
function Wait-GiftArrival([string]$path, [Diagnostics.Process]$desktop) {
    # The app writes Received only when its train reaches the delivery point.
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (!(Test-Path -LiteralPath $path)) {
        if ($desktop.HasExited) {throw "Jake Frost exited during delivery ($($desktop.ExitCode))."}
        if ($timer.Elapsed.TotalSeconds -gt 150) {throw "Timed out waiting for the train to deliver $path."}
        Start-Sleep -Milliseconds 250
    }
}
function Open-WhileRunning([string]$path, [Diagnostics.Process]$desktop) {
    $opener = Start-Process -FilePath $path -Verb Open -PassThru
    Check ($null -ne $opener -and $opener.Id -ne $desktop.Id -and
        $opener.WaitForExit(20000) -and $opener.ExitCode -eq 0) 'shell forwarded the file and its transient process exited successfully'
    $remaining = @(Get-Process -Name JakeFrost -ErrorAction SilentlyContinue | Where-Object Path -eq $installed)
    Check ($remaining.Count -eq 1 -and $remaining[0].Id -eq $desktop.Id) 'the original desktop instance continues running alone'
}
function Run-Installer([string]$path, [string]$action, [switch]$ExpectRefusal) {
    $log = Join-Path $scratch ($action+'.log')
    $argsForSetup = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="{0}"' -f $log))
    $process = Start-Process -FilePath $path -ArgumentList $argsForSetup -WindowStyle Hidden -PassThru -Wait
    $expected = if ($ExpectRefusal) {7} else {0}
    if ($process.ExitCode -ne $expected) {
        if (Test-Path -LiteralPath $log) {Get-Content -LiteralPath $log -Tail 30}
        throw "$action returned $($process.ExitCode), expected $expected."
    }
}
Check (!(Test-Path -LiteralPath $installedDir) -and !(Test-Path -LiteralPath $extKey) -and
    !(Test-Path -LiteralPath $frostData) -and !(Test-Path -LiteralPath $uninstallKey)) 'clean runner profile'

# Install a small earlier-version fixture under the same product identity.
$oldApp = (New-Item -ItemType Directory -Path (Join-Path $scratch 'old')).FullName
$stub = Join-Path $oldApp 'Old.cs'
[IO.File]::WriteAllText($stub, '[assembly:System.Reflection.AssemblyVersion("1.0.0.0")] class Old { static void Main() {} }')
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:winexe ("/out:"+(Join-Path $oldApp 'JakeFrost.exe')) $stub
if ($LASTEXITCODE) {throw 'Unable to build the earlier-version fixture.'}
Copy-Item -LiteralPath (Join-Path $app 'JakeFrost.exe.config') -Destination $oldApp
& (Join-Path $PSScriptRoot '..\BuildSetup.ps1') -AppDirectory $oldApp -OutputDirectory $oldApp -CompilerPath $CompilerPath
$oldSetup = Join-Path $oldApp 'Jake-Frost-Setup.exe'
Run-Installer $oldSetup 'install-earlier'
Check ((Get-FileHash -LiteralPath $installed).Hash -eq (Get-FileHash -LiteralPath (Join-Path $oldApp 'JakeFrost.exe')).Hash) 'first install writes its exact executable'

Run-Installer $setup 'upgrade'
foreach ($name in 'JakeFrost.exe','JakeFrost.exe.config') {
    Check ((Get-FileHash -LiteralPath (Join-Path $installedDir $name)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $app $name)).Hash) "upgrade installs byte-identical $name"
}
$version = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $app 'JakeFrost.exe')).FileVersion
Check ((Get-ItemProperty -LiteralPath $uninstallKey).DisplayVersion -eq ([version]$version).ToString(3)) 'Installed apps advertises the upgraded version'
Check ((New-Object -ComObject WScript.Shell).CreateShortcut($shortcut).TargetPath -eq $installed) 'Start menu shortcut launches the installed app'
Check ((RegistryDefault $extKey) -eq 'JakeFrost.Gift') 'new gift extension opens with Jake Frost'
Check ((RegistryDefault (Join-Path $classKey 'shell\open\command')) -eq ('"{0}" "%1"' -f $installed)) 'quoted open command forwards exactly one gift path'
Check ((Get-Item -LiteralPath (Join-Path $extKey OpenWithProgids)).GetValueNames() -contains 'JakeFrost.Gift') 'Jake Frost appears in Open with'
Run-Installer $oldSetup 'downgrade' -ExpectRefusal

if ($GiftPath) {
    $gift = (Resolve-Path -LiteralPath $GiftPath).Path
} else {
    $gift = Join-Path $scratch 'Gift from a friend.fpgift'
    New-NoteGift $gift
}
$giftId = [IO.File]::ReadAllLines($gift)[1]
Check ($giftId -match '^[A-Fa-f0-9]{32}$') 'gift fixture contains a valid ID'
$pendingDir = Join-Path $frostData 'GiftPost\Pending'
$receivedDir = Join-Path $frostData 'GiftPost\Received'
$received = Join-Path $receivedDir "$giftId.fpgift"
# This goes through the Explorer association, including any path quoting.
$desktop = Start-Process -FilePath $gift -Verb Open -PassThru
Check ($null -ne $desktop -and $desktop.Path -eq $installed) 'opening a gift from the shell launches the installed app'
Wait-GiftArrival $received $desktop
$sourceGift = [IO.File]::ReadAllLines($gift)
$archivedGift = [IO.File]::ReadAllLines($received)
Check ($archivedGift[1] -eq $sourceGift[1] -and $archivedGift[4] -ceq $sourceGift[4] -and
    $archivedGift[5] -ceq $sourceGift[5] -and $archivedGift[6] -ceq $sourceGift[6]) 'the train delivers the original gift, sender and message'

$nextGift = Join-Path $scratch 'A second gift for the open app.fpgift'
New-NoteGift $nextGift
$nextReceived = Join-Path $receivedDir ([IO.File]::ReadAllLines($nextGift)[1]+'.fpgift')
Open-WhileRunning $nextGift $desktop
& (Join-Path $PSScriptRoot 'WindowsPanel.ps1') -AppProcessId $desktop.Id -GiftReceipt $nextReceived
Wait-GiftArrival $nextReceived $desktop
$firstWrite = [IO.File]::GetLastWriteTimeUtc($received)
Open-WhileRunning $gift $desktop
Check (@(Get-ChildItem -LiteralPath $pendingDir -Filter '*.fpgift').Count -eq 0 -and
    @(Get-ChildItem -LiteralPath $receivedDir -Filter '*.fpgift').Count -eq 2 -and
    [IO.File]::GetLastWriteTimeUtc($received) -eq $firstWrite) 'opening the first gift again leaves both deliveries intact without queuing another'
$desktop.Kill()
$desktop.WaitForExit()

Set-Item -LiteralPath $extKey -Value 'SetupTest.OtherGift'
Run-Installer $setup 'repair'
Check ((RegistryDefault $extKey) -eq 'SetupTest.OtherGift') 'repair preserves another default gift handler'
$uninstaller = @(Get-ChildItem -LiteralPath $installedDir -Filter 'unins*.exe' -File)
Check ($uninstaller.Count -eq 1) 'upgrades reuse one registered uninstaller'
Run-Installer $uninstaller[0].FullName 'uninstall'
Check (!(Test-Path -LiteralPath $installed) -and !(Test-Path -LiteralPath $shortcut) -and
    !(Test-Path -LiteralPath $uninstallKey) -and !(Test-Path -LiteralPath $classKey)) 'uninstall removes program, shortcut, registration and its own gift handler'
Check ((RegistryDefault $extKey) -eq 'SetupTest.OtherGift') 'uninstall leaves another file handler alone'
Check ((Test-Path -LiteralPath $received) -and (Test-Path -LiteralPath $nextReceived)) 'uninstall preserves both delivered gifts'

# Verify first install and cleanup again from a genuinely unclaimed file type.
$extension = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes\.fpgift',$true)
try {$extension.DeleteValue('')} finally {$extension.Dispose()}
Run-Installer $setup 'clean-install'
Check ((RegistryDefault $extKey) -eq 'JakeFrost.Gift') 'released installer also claims gifts on fresh install'
$uninstaller = @(Get-ChildItem -LiteralPath $installedDir -Filter 'unins*.exe' -File)
Run-Installer $uninstaller[0].FullName 'clean-uninstall'
Check (!(Test-Path -LiteralPath $extKey)) 'uninstall removes its own file association'
