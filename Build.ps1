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
    '/r:System.dll', '/r:System.Core.dll', '/r:System.Xaml.dll', '/r:System.Drawing.dll', '/r:System.Windows.Forms.dll', '/r:System.Web.Extensions.dll')
foreach ($name in @('WindowsBase', 'PresentationCore', 'PresentationFramework')) {
    $options += "/r:$framework\WPF\$name.dll"
}
$sources = @(Get-ChildItem -LiteralPath $source -Filter '*.cs' | ForEach-Object FullName)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$markup = Join-Path $tempRoot ('JakeFrost-markup-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($markup)
try {
    & (Join-Path $framework 'MSBuild.exe') (Join-Path $source 'Panel.proj') /nologo /verbosity:quiet "/p:OutputPath=$markup"
    if ($LASTEXITCODE -ne 0) {throw "Panel markup compilation failed ($LASTEXITCODE)."}
    $options += "/resource:$markup\JakeFrost.g.resources,JakeFrost.g.resources"
    & (Join-Path $framework 'csc.exe') @options @sources
    if ($LASTEXITCODE -ne 0) { throw "JakeFrost compilation failed ($LASTEXITCODE)." }
} finally {
    $resolved = (Resolve-Path -LiteralPath $markup).Path
    if ([IO.Path]::GetDirectoryName($resolved) -eq $tempRoot -and [IO.Path]::GetFileName($resolved) -match '^JakeFrost-markup-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Copy-Item -LiteralPath (Join-Path $source 'JakeFrost.exe.config') -Destination (Join-Path $OutputDirectory 'JakeFrost.exe.config') -Force
Write-Output $binary
