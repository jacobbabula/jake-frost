[CmdletBinding(DefaultParameterSetName='Store')]
param(
    [Parameter(Mandatory=$true)][string]$AppDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true,ParameterSetName='Preview')][switch]$Preview,
    [Parameter(Mandatory=$true,ParameterSetName='Store')][string]$IdentityName,
    [Parameter(Mandatory=$true,ParameterSetName='Store')][string]$Publisher,
    [Parameter(Mandatory=$true,ParameterSetName='Store')][string]$PublisherDisplayName,
    [string]$MakeAppx
)
$ErrorActionPreference='Stop'
if($Preview) {
    $IdentityName='JakeFrost.LocalPreview';$Publisher='CN=Jake Frost Local Preview';$PublisherDisplayName='Jake Frost'
}
if(!$MakeAppx) {
    $bin=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $MakeAppx=Get-ChildItem -LiteralPath $bin -Directory | Where-Object Name -Match '^\d+\.\d+\.\d+\.\d+$' |
        Sort-Object {[version]$_.Name} -Descending | ForEach-Object {Join-Path $_.FullName 'x64\makeappx.exe'} |
        Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
}
if(!$MakeAppx){throw 'Install the Windows 10 or 11 SDK packaging tools or pass -MakeAppx.'}
$app=(Resolve-Path -LiteralPath $AppDirectory).Path
$output=[IO.Directory]::CreateDirectory($OutputDirectory).FullName
$work=[IO.Directory]::CreateDirectory((Join-Path ([IO.Path]::GetTempPath()) ('JakeFrost-MSIX-'+[guid]::NewGuid().ToString('N')))).FullName
try {
    $package=[IO.Directory]::CreateDirectory((Join-Path $work 'package')).FullName
    $assets=Join-Path $package 'Assets'
    & (Join-Path $PSScriptRoot 'MakeLogos.ps1') -OutputDirectory $assets
    Move-Item -LiteralPath (Join-Path $assets 'StoreListingLogo.png') -Destination (Join-Path $output 'StoreListingLogo.png') -Force
    foreach($file in 'JakeFrost.exe','JakeFrost.exe.config'){Copy-Item -LiteralPath (Join-Path $app $file) -Destination $package}
    [xml]$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'AppxManifest.xml') -Raw
    $identity=$manifest.Package.Identity
    $identity.SetAttribute('Name',$IdentityName);$identity.SetAttribute('Publisher',$Publisher)
    $version=[Reflection.AssemblyName]::GetAssemblyName((Join-Path $app 'JakeFrost.exe')).Version
    if($version.Revision -ne 0){throw 'A Store package must reserve its fourth version component for Microsoft.'}
    $identity.SetAttribute('Version',$version.ToString(4))
    $manifest.Package.Properties.PublisherDisplayName=$PublisherDisplayName
    $manifest.Save((Join-Path $package 'AppxManifest.xml'))
    $filename=if($Preview){'Jake-Frost-Identity-Preview'}else{'Jake-Frost-Store'}
    $msix=Join-Path $output ($filename+'.msix')
    & $MakeAppx pack /o /d $package /p $msix
    if($LASTEXITCODE){throw 'MakeAppx failed to package or validate the manifest.'}
    $unpack=Join-Path $work 'unpacked'
    & $MakeAppx unpack /o /p $msix /d $unpack
    if($LASTEXITCODE){throw 'MakeAppx verification failed.'}
    foreach($file in 'JakeFrost.exe','JakeFrost.exe.config'){
        if((Get-FileHash -LiteralPath (Join-Path $app $file)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $unpack $file)).Hash){throw "Payload mismatch: $file"}
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $toUpload=[IO.Directory]::CreateDirectory((Join-Path $work 'upload')).FullName
    Copy-Item -LiteralPath $msix -Destination $toUpload
    $draft=Join-Path $work ($filename+'.msixupload')
    [IO.Compression.ZipFile]::CreateFromDirectory($toUpload,$draft)
    Move-Item -LiteralPath $draft -Destination $output -Force
    Write-Output "MSIX and upload archive verified for $IdentityName $version"
} finally {
    $actual=[IO.Path]::GetFullPath($work)
    if([IO.Path]::GetDirectoryName($actual) -eq [IO.Path]::GetTempPath().TrimEnd('\') -and [IO.Path]::GetFileName($actual) -match '^JakeFrost-MSIX-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $actual -Recurse -Force
    }
}
