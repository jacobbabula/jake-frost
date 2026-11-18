param(
    [Parameter(Mandatory=$true)][ValidateSet('Send','Receive')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$AppDirectory,
    [Parameter(Mandatory=$true)][string]$ProfileDirectory,
    [Parameter(Mandatory=$true)][string]$ShareDirectory
)
$ErrorActionPreference = 'Stop'
# Use a disposable profile and the shipping executable for both halves of the round trip.
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -File $PSCommandPath -Mode $Mode -AppDirectory $AppDirectory -ProfileDirectory $ProfileDirectory -ShareDirectory $ShareDirectory
    if ($LASTEXITCODE) { throw "Shared-folder gift test failed ($LASTEXITCODE)." }
    return
}
$app = (Resolve-Path -LiteralPath (Join-Path $AppDirectory 'JakeFrost.exe')).Path
$assembly = [Reflection.Assembly]::LoadFrom($app)
$instance = [Reflection.BindingFlags]'Instance,NonPublic'
$postType = $assembly.GetType('Frostpane.GiftPost',$true)
$giftType = $assembly.GetType('Frostpane.GiftPayload',$true)
$friendType = $assembly.GetType('Frostpane.PostFriend',$true)
$profile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfileDirectory)
$share = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ShareDirectory)
$connection = Join-Path $profile 'GiftPost\connection.txt'
$winID = '22222222222222222222222222222222'
$macID = '11111111111111111111111111111111'
$macName = 'Mac friend'
$winName = 'Windows friend'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if ($Mode -eq 'Send') {
    if ((Test-Path -LiteralPath $profile) -or (Test-Path -LiteralPath $share)) {throw 'The fixture needs fresh test directories.'}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($connection))
    [void][IO.Directory]::CreateDirectory($share)
    # Give the two operating systems known identities before they have exchanged cards.
    [IO.File]::WriteAllText($connection,("FROSTPANE-POST-1","$winID","","" -join [char]10),$utf8)
    $peers = [IO.Directory]::CreateDirectory((Join-Path $share 'Frostpane Post\Friends'))
    [IO.File]::WriteAllText((Join-Path $peers.FullName ($macID+'.friend')),$macName,$utf8)
} elseif (!(Test-Path -LiteralPath $connection -PathType Leaf) -or !(Test-Path -LiteralPath $share -PathType Container)) {
    throw 'Restore the original Windows test profile and the share returned from Mac.'
}

$post = $postType.GetConstructors($instance)[0].Invoke(@($profile.PSObject.BaseObject))
if ($postType.GetProperty('Id',$instance).GetValue($post,$null) -cne $winID) {throw 'Windows test identity was not restored.'}
$postType.GetMethod('Connect',$instance).Invoke($post,@($share.PSObject.BaseObject,$winName.PSObject.BaseObject))
$friends = $postType.GetMethod('Friends',$instance).Invoke($post,@())
$mac = @($friends | Where-Object {
    $friendType.GetField('Id',$instance).GetValue($_) -ceq $macID -and
    $friendType.GetField('Name',$instance).GetValue($_) -ceq $macName
})
if ($mac.Count -ne 1) {throw 'Windows could not discover the expected Mac friend.'}
if ($Mode -eq 'Send') {
    $fixture = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\macOS\Tests\Fixtures\windows-tree.fpgift')).Path
    $shape=[Activator]::CreateInstance($giftType,$true)
    $kind=$giftType.GetField('Kind',$instance)
    $kind.SetValue($shape,[Enum]::Parse($kind.FieldType,'Snowman'))
    $giftType.GetField('Size',$instance).SetValue($shape,12.0)
    $giftType.GetField('Mid',$instance).SetValue($shape,32.0)
    $giftType.GetField('Head',$instance).SetValue($shape,19.0)
    $wire=$giftType.GetMethod('Encode',$instance).Invoke($shape,@())
    $decoded=$giftType.GetMethod('DecodeGift',[Reflection.BindingFlags]'Static,NonPublic').Invoke($null,@($wire))
    if((($wire -split [char]10)[8..10] -join ',') -ne '32,19,12' -or $giftType.GetField('Mid',$instance).GetValue($decoded) -ne 32 -or
        $giftType.GetMethod('Encode',$instance).Invoke($decoded,@()) -cne $wire) {throw 'An irregular gift must retain a v3 envelope and round-trip unchanged.'}
    $gift = $giftType.GetMethod('DecodeGift',[Reflection.BindingFlags]'Static,NonPublic').Invoke($null,@([IO.File]::ReadAllText($fixture)))
    $giftType.GetField('Id',$instance).SetValue($gift,[guid]::NewGuid().ToString('N'))
    $giftType.GetField('Note',$instance).SetValue($gift,'Windows to Mac')
    $postType.GetMethod('Send',$instance).Invoke($post,@($gift.PSObject.BaseObject,$mac[0].PSObject.BaseObject))
    $id = $giftType.GetField('Id',$instance).GetValue($gift)
    if (!(Test-Path -LiteralPath (Join-Path $share "Frostpane Post\Mail\$macID\$id.fpgift") -PathType Leaf)) {
        throw 'Windows did not queue the addressed tree in the shared Mac inbox.'
    }
    # The return journey must use the card actually written by the Mac app.
    [IO.File]::Delete((Join-Path $peers.FullName ($macID+'.friend')))
    Write-Output 'PASS: Windows release connected a shared folder and sent its dressed tree to the Mac identity.'
} else {
    $pending = $postType.GetMethod('Receive',$instance).Invoke($post,@())
    if ($pending.Count -ne 1) {throw "Expected one addressed snowman from Mac, got $($pending.Count)."}
    $gift = $pending[0]
    $expected = @{Kind='Snowman';Sender='Mac friend';SenderId=$macID;RecipientId=$winID;Note='Mac to Windows';Size='44';Mid='76';Head='59'}
    foreach ($name in $expected.Keys) {
        $actual = $giftType.GetField($name,$instance).GetValue($gift)
        if ([string]$actual -cne $expected[$name]) {throw "Wrong shared gift field $name ($actual)."}
    }
    $postType.GetMethod('Acknowledge',$instance).Invoke($post,@($gift.PSObject.BaseObject))
    if ($postType.GetMethod('Receive',$instance).Invoke($post,@()).Count -ne 0) {throw 'Windows replayed a delivered shared gift.'}
    $saved = $postType.GetMethod('Latest',$instance).Invoke($post,@())
    if ($giftType.GetField('Id',$instance).GetValue($saved) -cne $giftType.GetField('Id',$instance).GetValue($gift)) {
        throw 'Windows did not archive the Mac snowman.'
    }
    Write-Output 'PASS: Windows release discovered its Mac friend, received the addressed snowman and archived it exactly once.'
}
