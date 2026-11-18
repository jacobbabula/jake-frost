param(
    [Parameter(Mandatory=$true)][string]$AppDirectory,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
# Run the built app's codec under its shipping .NET Framework runtime.
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -File $PSCommandPath -AppDirectory $AppDirectory -OutputPath $OutputPath
    if ($LASTEXITCODE) {throw "Windows gift export failed ($LASTEXITCODE)."}
    return
}
$assemblyPath = (Resolve-Path -LiteralPath (Join-Path $AppDirectory 'JakeFrost.exe')).Path
$assembly = [Reflection.Assembly]::LoadFrom($assemblyPath)
$payloadType = $assembly.GetType('Frostpane.GiftPayload',$true)
$postType = $assembly.GetType('Frostpane.GiftPost',$true)
$instance = [Reflection.BindingFlags]'Instance,NonPublic'
$fixture = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\macOS\Tests\Fixtures\windows-tree.fpgift')).Path
$original = [IO.File]::ReadAllText($fixture)
$gift = $payloadType.GetMethod('DecodeGift',[Reflection.BindingFlags]'Static,NonPublic').Invoke($null,@($original))
$sender = $payloadType.GetField('Sender',$instance).GetValue($gift)
$payloadType.GetField('Id',$instance).SetValue($gift,[guid]::NewGuid().ToString('N'))

$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$parent = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
$unusedProfile = Join-Path $parent.FullName ([guid]::NewGuid().ToString('N'))
$post = $postType.GetConstructors($instance)[0].Invoke(@($unusedProfile.PSObject.BaseObject))
$postType.GetMethod('Export',$instance).Invoke($post,@($destination.PSObject.BaseObject,$gift.PSObject.BaseObject,$sender.PSObject.BaseObject))
$exported = [IO.File]::ReadAllLines($destination)
$previous = [IO.File]::ReadAllLines($fixture)
if ($exported[1] -eq $previous[1] -or $exported[2] -eq $previous[2] -or
    ($exported[3..13] -join "`n") -cne ($previous[3..13] -join "`n")) {
    throw 'The production export must have fresh IDs and retain the entire dressed tree.'
}
Write-Output "Exported gift with Jake Frost $($assembly.GetName().Version) to $destination"
