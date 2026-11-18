param(
    [Parameter(Mandatory=$true)][string]$AppDirectory,
    [Parameter(Mandatory=$true)][ValidateSet('Write','Read')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$Path
)
$ErrorActionPreference='Stop'
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path (Join-Path $AppDirectory 'JakeFrost.exe')))
$crypto=$assembly.GetType('Frostpane.FriendEnvelope',$true)
$giftType=$assembly.GetType('Frostpane.GiftPayload',$true)
$static=[Reflection.BindingFlags]'Static,NonPublic'
$instance=[Reflection.BindingFlags]'Instance,NonPublic'
# A public, deliberately fixed test vector. No real invitation or service is involved.
$secret='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
$giftId='0123456789abcdef0123456789abcdef'
function Transform([string]$method,[object[]]$arguments){
    $crypto.GetMethod($method,$static).Invoke($null,$arguments)
}
if($Mode -eq 'Write'){
    $note=[Activator]::CreateInstance($giftType,$true)
    $giftType.GetField('Id',$instance).SetValue($note,$giftId)
    $giftType.GetField('Note',$instance).SetValue($note,'Fresh snow from Windows')
    $raw=$giftType.GetMethod('Encode',$instance).Invoke($note,@())
    $payload=[ordered]@{
        address=Transform 'Id' @($secret)
        proof=Transform 'Proof' @($secret)
        name=Transform 'Seal' @($secret,'name/a','Windows friend')
        body=Transform 'Seal' @($secret,("gift/b/"+$giftId),$raw)
    }
    [IO.File]::WriteAllText($Path,($payload|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
} else {
    $data=Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    if((Transform 'Open' @($secret,'name/b',[string]$data.name)) -cne 'Mac friend'){throw 'Could not authenticate the Mac name.'}
    $raw=Transform 'Open' @($secret,("gift/a/"+$giftId),[string]$data.body)
    $note=$giftType.GetMethod('DecodeGift',$static).Invoke($null,@($raw))
    if($giftType.GetField('Note',$instance).GetValue($note) -cne 'Fresh snow from Mac'){throw 'Could not read the authenticated Mac gift.'}
    Write-Output 'PASS: Windows shipping decoder authenticated the Mac friend name and encrypted gift.'
}

