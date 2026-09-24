<#
    console_errors.ps1 - print the interesting part of IW4x's client console log.

    IW4x writes the real script/menu diagnostics to:
        <iw4x>\userraw\console_mp.log          (current session)
        <iw4x>\userraw\console_mp.00N.log      (older sessions, rotated)

    The per-mod log (mods\<mod>\logs\games_mp.log) stays empty even with
    "logfile 1", so this is the file to read.

    Usage:
        powershell -NoProfile -File tools\dev\console_errors.ps1
        powershell -NoProfile -File tools\dev\console_errors.ps1 -GameRoot D:\Games\iw4x
        powershell -NoProfile -File tools\dev\console_errors.ps1 -Tail 120
#>

[CmdletBinding()]
param(
    [string] $GameRoot = 'D:\Games\iw4x',
    [int]    $Context = 14,     # lines of context printed before each hit
    [int]    $After   = 6,      # lines printed after each hit
    [int]    $Tail    = 0       # if > 0, just print this many trailing lines
)

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $GameRoot 'userraw'
if (-not (Test-Path -LiteralPath $logDir)) {
    Write-Output "No userraw directory at: $logDir"
    exit 1
}

# newest first: console_mp.log wins, then console_mp.00N.log by number
$logs = @()
$main = Join-Path $logDir 'console_mp.log'
if (Test-Path -LiteralPath $main) { $logs += (Get-Item -LiteralPath $main) }
$logs += Get-ChildItem -LiteralPath $logDir -Filter 'console_mp.*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

if ($logs.Count -eq 0) {
    Write-Output "No console logs found in: $logDir"
    exit 1
}

Write-Output "== console logs (newest first) =="
foreach ($f in $logs | Select-Object -First 8) {
    Write-Output ("   {0,-28} {1,10:N0} bytes   {2}" -f $f.Name, $f.Length, $f.LastWriteTime)
}
Write-Output ''

$newest = $logs | Select-Object -First 1
Write-Output "== $($newest.Name) =="

$lines = @(Get-Content -LiteralPath $newest.FullName)

if ($Tail -gt 0) {
    $start = [Math]::Max(1, $lines.Count - $Tail + 1)
    for ($i = $start; $i -le $lines.Count; $i++) {
        Write-Output ('{0,6}: {1}' -f $i, $lines[$i - 1])
    }
    exit 0
}

# things that actually mean "something went wrong"
$pattern = 'bad syntax|compile error|unknown function|uninitialised|uninitialized|could not|fatal|Error:|script error|undefined'

$hits = @(Select-String -Path $newest.FullName -Pattern $pattern -AllMatches)
if ($hits.Count -eq 0) {
    Write-Output 'no error-looking lines found'
    exit 0
}

# group consecutive hits so a stack of related lines prints once
$shown = @{}
foreach ($h in $hits) {
    $first = [Math]::Max(1, $h.LineNumber - $Context)
    $last  = [Math]::Min($lines.Count, $h.LineNumber + $After)
    for ($i = $first; $i -le $last; $i++) {
        if ($shown.ContainsKey($i)) { continue }
        $shown[$i] = $true
        Write-Output ('{0,6}: {1}' -f $i, $lines[$i - 1])
    }
    Write-Output ''
}

Write-Output "== last 25 lines of $($newest.Name) =="
$start = [Math]::Max(1, $lines.Count - 24)
for ($i = $start; $i -le $lines.Count; $i++) {
    Write-Output ('{0,6}: {1}' -f $i, $lines[$i - 1])
}
