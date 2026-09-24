# =============================================================================
#  ESL-MOD development helper - crash / log collector
#
#  Gathers every place IW4x (and Windows) leaves evidence about a crash:
#    * IW4x launcher logs
#    * per-mod session logs (mods/<mod>/logs/games_mp.log)
#    * Windows Error Reporting reports
#    * Windows crash dumps
#    * Application event log entries
#    * files modified in the game folder in the last few hours
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\collect_crash_info.ps1
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\collect_crash_info.ps1 -GamePath "C:\Games\iw4x"
# =============================================================================

[CmdletBinding()]
param(
    [string] $GamePath = 'D:\Games\iw4x',
    [int]    $RecentHours = 3
)

$ErrorActionPreference = 'SilentlyContinue'

function Section([string] $title) {
    Write-Output ''
    Write-Output ('================ ' + $title + ' ================')
}

function Show-File([string] $path, [int] $lines) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Output ('[missing] ' + $path)
        return
    }

    $item = Get-Item -LiteralPath $path
    Write-Output ('[file]    ' + $path)
    Write-Output ('          ' + $item.Length + ' bytes, last write ' + $item.LastWriteTime)

    if ($item.Length -eq 0) {
        Write-Output '          *** FILE IS EMPTY ***'
        return
    }

    Get-Content -LiteralPath $path -Tail $lines | ForEach-Object { Write-Output ('    | ' + $_) }
}

Write-Output ('ESL-MOD crash information collector - ' + (Get-Date))
Write-Output ('Game folder: ' + $GamePath)
Write-Output ('Windows    : ' + [System.Environment]::OSVersion.VersionString)

# -----------------------------------------------------------------------------
Section 'IW4x launcher logs (3 newest)'
Get-ChildItem -LiteralPath (Join-Path $GamePath 'cache') -Filter 'launcher_*.log' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 3 |
    ForEach-Object { Show-File $_.FullName 80 }

# -----------------------------------------------------------------------------
Section 'Session logs (mods/<mod>/logs/games_mp.log)'
Get-ChildItem -Path (Join-Path $GamePath 'mods') -Recurse -Filter 'games_mp.log' -File |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object { Show-File $_.FullName 60 }

# -----------------------------------------------------------------------------
Section 'Main session log (last 30 lines)'
Show-File (Join-Path $GamePath 'main\games_mp.log') 30

# -----------------------------------------------------------------------------
Section 'Windows Error Reporting reports mentioning iw4x (5 newest)'
$werRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER'
foreach ($sub in @('ReportArchive', 'ReportQueue')) {
    $dir = Join-Path $werRoot $sub
    if (-not (Test-Path -LiteralPath $dir)) { continue }

    Get-ChildItem -LiteralPath $dir -Directory |
        Where-Object { $_.Name -match 'iw4' -or $_.Name -match 'Modern' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5 |
        ForEach-Object {
            Write-Output ('[report] ' + $_.FullName + '   ' + $_.LastWriteTime)
            Get-ChildItem -LiteralPath $_.FullName -File |
                ForEach-Object { Write-Output ('          - ' + $_.Name) }

            $werFile = Join-Path $_.FullName 'Report.wer'
            if (Test-Path -LiteralPath $werFile) {
                Get-Content -LiteralPath $werFile |
                    Where-Object { $_ -match 'AppName|AppPath|ExceptionCode|Module|Sig\[|Faulting' } |
                    ForEach-Object { Write-Output ('            ' + $_) }
            }
        }
}

# -----------------------------------------------------------------------------
Section 'Windows crash dumps'
$dumpDirs = @(
    (Join-Path $env:LOCALAPPDATA 'CrashDumps'),
    (Join-Path $GamePath 'crashes'),
    (Join-Path $GamePath 'players\crashes')
)
foreach ($dir in $dumpDirs) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10 |
        ForEach-Object { Write-Output ('[dump] ' + $_.LastWriteTime + '  ' + $_.Length + ' bytes  ' + $_.FullName) }
}

# -----------------------------------------------------------------------------
Section 'Application event log - crashes/hangs in the last 7 days'
$since = (Get-Date).AddDays(-7)
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since } -MaxEvents 500 |
    Where-Object {
        $_.Message -match 'iw4x' -or
        $_.ProviderName -match 'Application Error|Application Hang|Windows Error Reporting|\.NET Runtime'
    } |
    Select-Object -First 12 |
    ForEach-Object {
        Write-Output ('--- ' + $_.TimeCreated + '   provider=' + $_.ProviderName + '  id=' + $_.Id)
        $msg = $_.Message
        if ($msg -and $msg.Length -gt 800) { $msg = $msg.Substring(0, 800) }
        Write-Output $msg
    }

# -----------------------------------------------------------------------------
Section ('Files modified in the game folder in the last ' + $RecentHours + ' hour(s)')
$cutoff = (Get-Date).AddHours(-1 * $RecentHours)
Get-ChildItem -LiteralPath $GamePath -Recurse -File |
    Where-Object { $_.LastWriteTime -gt $cutoff -and $_.FullName -notmatch '\\cache\\launcher_' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 40 |
    ForEach-Object { Write-Output ($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $_.Length.ToString().PadLeft(9) + '  ' + $_.FullName) }

# -----------------------------------------------------------------------------
Section 'Player / mod state'
Show-File (Join-Path $GamePath 'players\iw4x_config.cfg') 40
Get-ChildItem -LiteralPath (Join-Path $GamePath 'players\mods') -Directory |
    ForEach-Object { Write-Output ('[playerdir] ' + $_.FullName) }

Write-Output ''
Write-Output 'Collector finished.'
