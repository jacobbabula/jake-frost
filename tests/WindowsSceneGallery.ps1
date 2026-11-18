param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$source=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\src')).Path
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
if (!(Test-Path (Join-Path $framework 'csc.exe'))) {$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319'}
$binary=Join-Path ([IO.Path]::GetTempPath()) ('JakeFrost-SceneGallery-'+[Guid]::NewGuid().ToString('N')+'.exe')
$opts=@('/nologo','/optimize+','/utf8output','/main:WindowsSceneGallery',"/out:$binary",
    '/r:System.dll','/r:System.Core.dll','/r:System.Xaml.dll','/r:System.Drawing.dll',
    '/r:System.Windows.Forms.dll','/r:System.Web.Extensions.dll','/r:System.Security.dll')
foreach ($library in 'WindowsBase','PresentationCore','PresentationFramework') {$opts += "/r:$framework\WPF\$library.dll"}
foreach ($name in 'Switchback','SwitchbackNight','Lantern','LanternNight') {
    $opts += "/resource:$source\Wallpapers\$name.jpg,JakeFrost.Wallpaper.$name"
}
try {
    $src=@(Get-ChildItem -LiteralPath $source -Filter '*.cs' | ForEach-Object FullName)
    & (Join-Path $framework 'csc.exe') @opts @src (Join-Path $PSScriptRoot 'WindowsSceneGallery.cs')
    if ($LASTEXITCODE) { throw 'Windows scene gallery compilation failed.' }
    & $binary ([IO.Path]::GetFullPath($OutputDirectory))
    if ($LASTEXITCODE) { throw 'Windows scene gallery did not finish.' }
} finally {
    if (Test-Path -LiteralPath $binary) {Remove-Item -LiteralPath $binary -Force}
}
