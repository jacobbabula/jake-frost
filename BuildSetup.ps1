param(
    [string]$AppDirectory = $PSScriptRoot,
    [string]$OutputDirectory = $PSScriptRoot,
    [string]$CompilerPath
)
$ErrorActionPreference = 'Stop'
$app = (Resolve-Path -LiteralPath $AppDirectory).Path
$exe = Join-Path $app 'JakeFrost.exe'
if (!(Test-Path -LiteralPath $exe) -or !(Test-Path -LiteralPath (Join-Path $app 'JakeFrost.exe.config'))) {
    throw 'Build Jake Frost with Build.ps1 before building the installer.'
}
if (!$CompilerPath) {
    $onPath = Get-Command ISCC.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($onPath) {
        $CompilerPath = $onPath.Source
    } else {
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
            if (!$base) {continue}
            foreach ($dir in 'Inno Setup 7','Inno Setup 6') {
                $candidate = Join-Path (Join-Path $base $dir) 'ISCC.exe'
                if (Test-Path -LiteralPath $candidate) {$CompilerPath = $candidate; break}
            }
            if ($CompilerPath) {break}
        }
    }
}
if (!$CompilerPath) {throw 'Install Inno Setup 6.2 or later, or provide the path to ISCC.exe with -CompilerPath.'}
$compiler = (Resolve-Path -LiteralPath $CompilerPath).Path
$output = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$version = [Reflection.AssemblyName]::GetAssemblyName($exe).Version
$scriptFile = Join-Path $PSScriptRoot 'installer\windows\JakeFrost.iss'
& $compiler '/Qp' "/DAppDirectory=$app" "/DAppVersion=$($version.ToString(3))" "/DFileVersion=$version" "/O$output" $scriptFile
if ($LASTEXITCODE -ne 0) {throw "Inno Setup compilation failed ($LASTEXITCODE)."}
Write-Output (Join-Path $output 'Jake-Frost-Setup.exe')
