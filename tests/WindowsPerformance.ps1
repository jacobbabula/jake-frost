param(
    [string]$SourceDirectory = (Join-Path $PSScriptRoot '..\src'),
    [string]$OutputDirectory = [IO.Path]::GetTempPath()
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $OutputDirectory).Path
$scratch = [IO.Directory]::CreateDirectory((Join-Path $root ('JakeFrost-benchmark-' + [Guid]::NewGuid().ToString('N')))).FullName
try {
    $framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
    if (!(Test-Path (Join-Path $framework 'csc.exe'))) {
        $framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319'
    }
    $binary = Join-Path $scratch 'WindowsPerformance.exe'
    $arguments = @('/nologo','/optimize+','/utf8output','/main:WindowsPerformance',"/out:$binary",
        '/r:System.dll','/r:System.Core.dll','/r:System.Xaml.dll','/r:System.Drawing.dll',
        '/r:System.Windows.Forms.dll','/r:System.Web.Extensions.dll')
    foreach ($name in 'WindowsBase','PresentationCore','PresentationFramework') {
        $arguments += "/r:$framework\WPF\$name.dll"
    }
    $files = @(Get-ChildItem -LiteralPath $SourceDirectory -Filter '*.cs' | ForEach-Object FullName)
    & (Join-Path $framework 'csc.exe') @arguments @files (Join-Path $PSScriptRoot 'WindowsPerformance.cs')
    if ($LASTEXITCODE -ne 0) {throw 'Windows performance probe compilation failed.'}
    & $binary $scratch
    if ($LASTEXITCODE -ne 0) {throw 'Windows performance probe failed.'}
} finally {
    $resolved = (Resolve-Path -LiteralPath $scratch).Path
    if ([IO.Path]::GetDirectoryName($resolved) -eq $root.TrimEnd('\') -and
        [IO.Path]::GetFileName($resolved) -match '^JakeFrost-benchmark-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
