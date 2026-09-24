# =============================================================================
#  ESL-MOD development helper - import the in-game create-a-class UI
#
#  The base game's in-game class menu is only a class *selector*; the full editor
#  UI that ProMod uses is their heavily edited descendant of the stock menus.
#  This script copies exactly the files needed to reproduce that editor:
#
#      ui_mp/scriptmenus/changeclass_mw.menu          (generic)
#      ui_mp/scriptmenus/changeclass_marines_mw.menu  (allies)
#      ui_mp/scriptmenus/changeclass_opfor_mw.menu    (axis)
#
#  and everything reachable through their #include graph, from the extracted
#  ProMod reference into src\ (which the build packs into the .iwd).
#
#  Everything ProMod-specific is filtered out by name (quickpromod, shoutcast,
#  demo, clientcmd, echo, ...), and anything not present in the reference is left
#  alone: it is a stock game file and resolves from the game's own zones.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\import_ui.ps1
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\import_ui.ps1 -WhatIf
# =============================================================================

[CmdletBinding()]
param(
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'

$root   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$refDir = Join-Path $root '.tmp_reference\promod'
$outDir = Join-Path $root 'src'

if (-not (Test-Path -LiteralPath $refDir)) {
    throw "Extracted ProMod reference not found: $refDir (see docs/DIAGNOSTICS.md)"
}

$roots = @(
    'ui_mp/scriptmenus/changeclass_mw.menu',
    'ui_mp/scriptmenus/changeclass_marines_mw.menu',
    'ui_mp/scriptmenus/changeclass_opfor_mw.menu'
)

# ProMod-only files that must never be imported (their own menus/features).
$exclude = @(
    'quickpromod', 'quickpromodgfx', 'shoutcast', 'demo.menu', 'clientcmd',
    'echo.menu', 'team_marinesopfor_flipped', 'stratmode', 'strattime',
    'timeout', 'readyup', 'comp', 'modes'
)

function ConvertTo-FullPath([string] $rel) {
    return (Join-Path $refDir ($rel -replace '/', '\'))
}

function Get-Includes([string] $file) {
    $text = Get-Content -LiteralPath $file -Raw
    $result = New-Object System.Collections.Generic.List[string]

    foreach ($m in [regex]::Matches($text, '(?m)^\s*#include\s+"([^"]+)"')) {
        $rel = $m.Groups[1].Value -replace '\\', '/'
        # includes are written relative to the game root
        $result.Add($rel)
    }

    return $result
}

$queue   = New-Object System.Collections.Generic.Queue[string]
$seen    = New-Object System.Collections.Generic.HashSet[string]
$toCopy  = New-Object System.Collections.Generic.List[string]
$baseGame = New-Object System.Collections.Generic.List[string]

foreach ($r in $roots) { $queue.Enqueue($r) }

while ($queue.Count -gt 0) {
    $rel = $queue.Dequeue()

    if ($seen.Contains($rel)) { continue }
    [void]$seen.Add($rel)

    $full = ConvertTo-FullPath $rel

    if (-not (Test-Path -LiteralPath $full)) {
        # not shipped by ProMod => stock game file, resolves from the base zones
        $baseGame.Add($rel)
        continue
    }

    $skip = $false
    foreach ($e in $exclude) {
        if ($rel -like ('*' + $e + '*')) { $skip = $true; break }
    }
    if ($skip) {
        Write-Output ('skipped (ProMod specific): ' + $rel)
        continue
    }

    $toCopy.Add($rel)

    foreach ($inc in Get-Includes $full) { $queue.Enqueue($inc) }
}

Write-Output ''
Write-Output ('files to import : ' + $toCopy.Count)
foreach ($f in ($toCopy | Sort-Object)) { Write-Output ('  + ' + $f) }

Write-Output ''
Write-Output ('stock files referenced (not shipped) : ' + $baseGame.Count)
foreach ($f in ($baseGame | Sort-Object -Unique)) { Write-Output ('  - ' + $f) }

if ($WhatIf) {
    Write-Output ''
    Write-Output 'WhatIf - nothing written.'
    exit 0
}

$copied = 0
foreach ($rel in $toCopy) {
    $src = ConvertTo-FullPath $rel
    $dst = Join-Path $outDir ($rel -replace '/', '\')

    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force
    $copied++
}

Write-Output ''
Write-Output ('imported ' + $copied + ' files into ' + $outDir)
