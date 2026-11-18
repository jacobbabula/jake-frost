param(
    [string]$SourceDirectory=(Join-Path $PSScriptRoot '..\src'),
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$Name
)
$ErrorActionPreference='Stop'
if ($Name -notmatch '^[a-z0-9-]+$') { throw 'Use a simple name for the PNG.' }
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$output=[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory)).FullName
$out=Join-Path ([IO.Path]::GetTempPath()) ('JakeFrost-PloughSheet-'+[Guid]::NewGuid().ToString('N')+'.exe')
$opts=@('/nologo','/optimize+','/utf8output','/main:PloughSheet',"/out:$out",'/r:System.dll','/r:System.Core.dll','/r:System.Xaml.dll','/r:System.Drawing.dll','/r:System.Windows.Forms.dll','/r:System.Web.Extensions.dll')
foreach ($lib in 'WindowsBase','PresentationCore','PresentationFramework') {$opts += "/r:$framework\WPF\$lib.dll"}
$src=@(Get-ChildItem -LiteralPath $SourceDirectory -Filter '*.cs' | ForEach-Object FullName)
try {
    & (Join-Path $framework 'csc.exe') @opts @src (Join-Path $PSScriptRoot 'WindowsPloughSheet.cs')
    if ($LASTEXITCODE) {throw 'Visual probe did not compile'}
    & $out (Join-Path $output ($Name+".png")) $Name
    if ($LASTEXITCODE) {throw 'Native render did not finish'}
} finally {
    if (Test-Path -LiteralPath $out) {Remove-Item -LiteralPath $out -Force}
}
