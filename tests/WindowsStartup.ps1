param(
    [Parameter(Mandatory=$true)][string]$BaselineApplication,
    [Parameter(Mandatory=$true)][string]$Application,
    [ValidateRange(1,25)][int]$Trials=7
)
$ErrorActionPreference='Stop'
$paths=@((Resolve-Path -LiteralPath $BaselineApplication).Path,(Resolve-Path -LiteralPath $Application).Path)
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$scratch=Join-Path $tempRoot ('JakeFrost-startup-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($scratch)
try {
    Add-Type -Path (Join-Path $PSScriptRoot 'WindowsStartup.cs')
    $panel=@(@(),@()); $ready=@(@(),@())
    # Warm the filesystem once for each binary. Each measured launch is a fresh process and new profile.
    for ($i=0; $i -le $Trials; $i++) {
        foreach ($variant in @(($i%2),(1-($i%2)))) {
            $profile=Join-Path $scratch "profile-$i-$variant"
            $times=[WindowsStartup]::Measure($paths[$variant],$profile)
            if ($i -gt 0) {
                $panel[$variant] += $times[0]
                $ready[$variant] += $times[1]
            }
        }
    }
    function Median($data) {
        $sorted=@($data|Sort-Object); $half=[int][Math]::Floor($sorted.Count/2)
        if ($sorted.Count%2) {return $sorted[$half]}
        ($sorted[$half-1]+$sorted[$half])/2
    }
    foreach ($variant in 0,1) {
        $version=[Reflection.AssemblyName]::GetAssemblyName($paths[$variant]).Version
        Write-Output "Jake Frost $version, $Trials fresh-process launches, warmed file cache: visible panel $(Median $panel[$variant]) ms, responsive panel and visible snow overlay $(Median $ready[$variant]) ms median."
    }
} finally {
    $resolved=(Resolve-Path -LiteralPath $scratch).Path
    if ([IO.Path]::GetDirectoryName($resolved) -eq $tempRoot -and [IO.Path]::GetFileName($resolved) -match '^JakeFrost-startup-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
