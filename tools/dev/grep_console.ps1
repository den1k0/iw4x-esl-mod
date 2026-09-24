<#
    grep_console.ps1 - search the IW4x client console log for a pattern.

    Companion to console_errors.ps1: that one prints everything that looks like an
    error, this one answers a specific question ("did my menu load?", "did the
    response arrive?", "was it rejected?").

    Usage:
        powershell -NoProfile -File tools\dev\grep_console.ps1 -Pattern lethal
        powershell -NoProfile -File tools\dev\grep_console.ps1 -Pattern "not allowed|reject"
        powershell -NoProfile -File tools\dev\grep_console.ps1 -Pattern "Could not find menu" -Context 0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Pattern,

    [string] $GameRoot = 'D:\Games\iw4x',
    [string] $Log      = 'console_mp.log',
    [int]    $Context  = 2,
    [int]    $Max      = 80
)

$ErrorActionPreference = 'Stop'

$path = Join-Path (Join-Path $GameRoot 'userraw') $Log
if (-not (Test-Path -LiteralPath $path)) {
    Write-Output "No such log: $path"
    exit 1
}

$lines = @(Get-Content -LiteralPath $path)
$hits  = @(Select-String -Path $path -Pattern $Pattern)

Write-Output ("== {0} = {1} lines, pattern '{2}' = {3} hits ==" -f $Log, $lines.Count, $Pattern, $hits.Count)

if ($hits.Count -eq 0) { exit 0 }

$shown = @{}
$count = 0

foreach ($h in $hits) {
    if ($count -ge $Max) {
        Write-Output ('... {0} more hits not shown' -f ($hits.Count - $count))
        break
    }

    $first = [Math]::Max(1, $h.LineNumber - $Context)
    $last  = [Math]::Min($lines.Count, $h.LineNumber + $Context)

    for ($i = $first; $i -le $last; $i++) {
        if ($shown.ContainsKey($i)) { continue }
        $shown[$i] = $true
        Write-Output ('{0,6}: {1}' -f $i, $lines[$i - 1])
    }

    $count++
}
