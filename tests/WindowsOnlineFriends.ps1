param(
    [Parameter(Mandatory=$true)][string]$AppDirectory,
    [uri]$Service
)
$ErrorActionPreference='Stop'
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path (Join-Path $AppDirectory 'JakeFrost.exe')))
$online=$assembly.GetType('Frostpane.OnlinePost',$true)
$giftType=$assembly.GetType('Frostpane.GiftPayload',$true)
$postType=$assembly.GetType('Frostpane.GiftPost',$true)
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
$profile=[IO.Directory]::CreateDirectory((Join-Path ([IO.Path]::GetTempPath()) ('JakeFrost-online-test-'+[Guid]::NewGuid().ToString('N')))).FullName
function Open-Profile($which,$address=$Service) {
    $dir=[IO.Path]::Combine($profile,$which)
    $online.GetConstructor($flags,$null,[type[]]@([string],[uri]),$null).Invoke(@($dir,$address))
}
function Call($subject,[string]$method,[object[]]$arguments) {
    $subject.GetType().GetMethod($method,$flags).Invoke($subject,$arguments)
}
function Receive-Mail($subject,$post) {
    $action=[Action`1].MakeGenericType($giftType)
    $callback=[Delegate]::CreateDelegate($action,$post,$postType.GetMethod('ReceiveOnline',$flags))
    Call $subject 'Poll' @($callback)
}
function Fresh-Post($which) {
    $dir=[IO.Path]::Combine($profile,$which)
    $postType.GetConstructor($flags,$null,[type[]]@([string]),$null).Invoke(@($dir))
}
function New-Note([string]$message) {
    $gift=[Activator]::CreateInstance($giftType,$true)
    $giftType.GetField('Note',$flags).SetValue($gift,$message)
    $gift
}
function Require($condition,[string]$message) { if(!$condition){throw $message} }
$server=$null
$id=$null
try {
    if(!$Service) {
        $entry=(Resolve-Path (Join-Path $PSScriptRoot '..\relay\test-server.mjs')).Path
        $portFile=Join-Path $profile 'port.txt'
        $server=Start-Process -FilePath 'node.exe' -ArgumentList ('"'+$entry+'" "'+$portFile+'"') -WindowStyle Hidden -PassThru
        for($i=0;$i -lt 100 -and !(Test-Path -LiteralPath $portFile);$i++){Start-Sleep -Milliseconds 100}
        $port=[int]([IO.File]::ReadAllText($portFile))
        if($port -le 0 -or $port -gt 65535){throw 'Invalid local relay port.'}
        $Service=[uri]("http://127.0.0.1:"+$port+"/api/post")
    }
    $alice=Open-Profile 'alice'; $bob=Open-Profile 'bob';$eve=Open-Profile 'eve'
    $aliceLocal=Fresh-Post 'alice'; $bobLocal=Fresh-Post 'bob'
    $invite=Call $alice 'Invite' @('Winter tester A')
    $id=@(Call $alice 'List' @())[0].id
    Require ($invite -cmatch '^JF1-[A-Za-z0-9_-]{43}$') 'Wrong invite format'
    Require ((Call $bob 'Accept' @($invite,'Winter tester B')) -ceq 'Winter tester A') 'Invitation did not show the inviting friend'
    $usedRejected=$false
    try { $null=Call $eve 'Accept' @($invite,'Winter tester C') }catch{ $usedRejected=$true }
    Require $usedRejected 'A third device claimed an accepted invitation'
    $ownRejected=$false
    try { $null=Call $alice 'Accept' @($invite,'Winter tester A') }catch{ $ownRejected=$true }
    Require $ownRejected 'An owner accepted their own invite'
    Receive-Mail $alice $aliceLocal
    $savedName=@(Call $alice 'List' @())[0].name
    Require ($savedName -ceq 'Winter tester B') 'Sender did not discover the accepting friend'
    $gift=New-Note 'Offline delivery one'
    $temporarilyOffline=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $temporarilyOffline.Start()
    $closedPort=$temporarilyOffline.LocalEndpoint.Port
    $temporarilyOffline.Stop()
    $offline=Open-Profile 'alice' ([uri]("http://127.0.0.1:"+$closedPort+"/api/post"))
    Require (!(Call $offline 'Send' @($id,$gift))) 'An offline sender did not queue the gift'
    $alice=Open-Profile 'alice'
    Receive-Mail $alice $aliceLocal
    Require (Call $alice 'Send' @($id,$gift)) 'An online retry could not be confirmed'
    $bob=Open-Profile 'bob'
    Receive-Mail $bob $bobLocal
    Receive-Mail $bob $bobLocal
    $inbox=@(Call $bobLocal 'Receive' @())
    Require ($inbox.Count -eq 1) 'A redelivered gift was lost or duplicated'
    Require ($giftType.GetField('Note',$flags).GetValue($inbox[0]) -ceq 'Offline delivery one') 'The gift content changed'
    Require ($giftType.GetField('Sender',$flags).GetValue($inbox[0]) -ceq 'Winter tester A') 'The recipient saw the wrong sender'
    Call $bobLocal 'Acknowledge' @($inbox[0])
    $back=New-Note 'Reply from Winter tester B'
    Require (Call $bob 'Send' @($id,$back)) 'The reply was not confirmed'
    $alice=Open-Profile 'alice'
    Receive-Mail $alice $aliceLocal
    $reply=@(Call $aliceLocal 'Receive' @())
    Require ($reply.Count -eq 1) 'The reply did not arrive after restart'
    Call $bob 'Remove' @($id)
    Receive-Mail $alice $aliceLocal
    Require (@(Call $alice 'List' @()).Count -eq 0) 'A removed friend was still active'
    Write-Output 'PASS: two independent Windows profiles accepted one private invitation, refused re-use, reopened encrypted contacts, delivered and deduplicated gifts in both directions, and revoked the friendship.'
} finally {
    if($id) {foreach($profilePost in @($alice,$bob)){try{Call $profilePost 'Remove' @($id)}catch{}}}
    if($server -and !$server.HasExited){$server.Kill();$server.WaitForExit()}
    $full=[IO.Path]::GetFullPath($profile)
    if([IO.Path]::GetDirectoryName($full) -eq [IO.Path]::GetTempPath().TrimEnd('\') -and [IO.Path]::GetFileName($full) -match '^JakeFrost-online-test-[a-f0-9]{32}$') {
        Remove-Item -Recurse -Force -LiteralPath $full
    }
}
