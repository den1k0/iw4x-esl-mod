# =============================================================================
#  ESL-MOD development helper - live server log watcher
#
#  Prints whatever the dedicated server appends to its logs while a connection
#  attempt is made, so a join can be followed as it happens:
#
#      mods\ESL-MOD\logs\games_mp.log   joins (J;), quits (Q;), round/game flow
#      mods\ESL-MOD\console_mp.log      connection attempts, session registrations,
#                                       map loads, errors
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\watch-server.ps1
#      ... -Seconds 120
# =============================================================================

[CmdletBinding()]
param(
    [int]    $Seconds  = 90,
    [string] $Iw4xPath = 'D:\Games\iw4x'
)

$ErrorActionPreference = 'Continue'

$modDir    = Join-Path $Iw4xPath 'mods\ESL-MOD'
$repoRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$webLog    = Join-Path $repoRoot 'build\webserve-access.log'

$targets = @(
    [pscustomobject]@{ Tag = 'game   '; Path = (Join-Path $modDir 'logs\games_mp.log') },
    [pscustomobject]@{ Tag = 'console'; Path = (Join-Path $modDir 'console_mp.log') }
)

# the mod-download web server, if tools\publish-mod.ps1 is serving
if (Test-Path -LiteralPath $webLog) {
    $targets += [pscustomobject]@{ Tag = 'websrv '; Path = $webLog }
}

foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t.Path)) {
        Write-Output ('missing: ' + $t.Path)
        exit 1
    }
}

# remember where each log currently ends
$pos = @{}
foreach ($t in $targets) { $pos[$t.Path] = (Get-Item -LiteralPath $t.Path).Length }

Write-Output ('watching ' + $Seconds + ' s - make the connection attempt now')
Write-Output ''

$deadline = (Get-Date).AddSeconds($Seconds)

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2

    foreach ($t in $targets) {
        $len = (Get-Item -LiteralPath $t.Path).Length
        if ($len -le $pos[$t.Path]) { continue }

        $stream = [System.IO.File]::Open($t.Path, [System.IO.FileMode]::Open,
                                         [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            [void]$stream.Seek($pos[$t.Path], [System.IO.SeekOrigin]::Begin)
            $reader = New-Object System.IO.StreamReader($stream)
            $text = $reader.ReadToEnd()
            $reader.Close()
        } finally {
            $stream.Close()
        }

        foreach ($line in ($text -split "`r?`n")) {
            if ($line.Trim()) { Write-Output ($t.Tag + ' | ' + $line.Trim()) }
        }

        $pos[$t.Path] = $len
    }
}

Write-Output ''
Write-Output 'watch ended'
