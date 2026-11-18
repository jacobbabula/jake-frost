param([string]$OutputDirectory = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
if (!(Test-Path (Join-Path $framework 'csc.exe'))) {
    $framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319'
}
$source = Join-Path $PSScriptRoot 'src'
$null = New-Item -ItemType Directory -Force -Path $OutputDirectory
$binary = Join-Path $OutputDirectory 'JakeFrost.exe'
$options = @('/nologo', '/optimize+', '/target:winexe', '/platform:anycpu', '/utf8output',
    "/out:$binary", "/win32manifest:$source\JakeFrost.manifest",
    "/win32icon:$source\JakeFrost.ico", "/resource:$source\JakeFrost.ico,JakeFrost.Icon",
    "/resource:$source\Panel.xaml,JakeFrost.Panel",
    '/r:System.dll', '/r:System.Core.dll', '/r:System.Xaml.dll', '/r:System.Drawing.dll', '/r:System.Windows.Forms.dll', '/r:System.Web.Extensions.dll')
foreach ($name in @('WindowsBase', 'PresentationCore', 'PresentationFramework')) {
    $options += "/r:$framework\WPF\$name.dll"
}
$sources = @(Get-ChildItem -LiteralPath $source -Filter '*.cs' | ForEach-Object FullName)
& (Join-Path $framework 'csc.exe') @options @sources
if ($LASTEXITCODE -ne 0) { throw "JakeFrost compilation failed ($LASTEXITCODE)." }
Copy-Item -LiteralPath (Join-Path $source 'JakeFrost.exe.config') -Destination (Join-Path $OutputDirectory 'JakeFrost.exe.config') -Force
Write-Output $binary
