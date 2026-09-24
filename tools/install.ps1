# =============================================================================
#  ESL-MOD installer
#
#  Copies the built archive (and the example configs) into
#      <IW4x>\mods\ESL-MOD\
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1 -Iw4xPath "C:\Games\iw4x"
# =============================================================================

[CmdletBinding()]
param(
    [string] $Iw4xPath = 'D:\Games\iw4x',
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$iwdPath = Join-Path $root 'build\z_eslmod.iwd'
$modDir  = Join-Path $Iw4xPath 'mods\ESL-MOD'

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1')
}

if (-not (Test-Path -LiteralPath $iwdPath)) {
    throw "Build output not found: $iwdPath"
}

if (-not (Test-Path -LiteralPath $Iw4xPath)) {
    throw "IW4x folder not found: $Iw4xPath (pass -Iw4xPath <folder>)"
}

if (-not (Test-Path -LiteralPath $modDir)) {
    New-Item -ItemType Directory -Force -Path $modDir | Out-Null
}

Copy-Item -LiteralPath $iwdPath -Destination (Join-Path $modDir 'z_eslmod.iwd') -Force

# mod.ff is the mod's own fastfile, and it is deliberately *not* inside the .iwd:
# the engine loads it from the mod folder next to the archive.  The end-of-match
# map vote needs it for the preview materials (preview_mp_*) its cards draw - an
# image is a fastfile asset even when the pixels come from the game's own iwds -
# see docs/MAPVOTE.md.  It is a third-party file: sesh_server_v2's, unmodified.
$ffPath = Join-Path $root 'third_party\sesh_server_v2\mod.ff'

if (-not (Test-Path -LiteralPath $ffPath)) {
    throw ('mod.ff missing: ' + $ffPath +
           ' - the map vote cards need the preview materials it defines')
}

Copy-Item -LiteralPath $ffPath -Destination (Join-Path $modDir 'mod.ff') -Force

# Example configs go into a "configs" sub-folder on purpose: a .cfg sitting
# directly in the mod folder could be picked up by the engine, and these are
# meant to be exec'd deliberately from a server config:
#     exec mods/ESL-MOD/configs/ESL-MOD.cfg
$cfgDir = Join-Path $root 'config'
if (Test-Path -LiteralPath $cfgDir) {
    $cfgDest = Join-Path $modDir 'configs'
    if (-not (Test-Path -LiteralPath $cfgDest)) {
        New-Item -ItemType Directory -Force -Path $cfgDest | Out-Null
    }
    Copy-Item -Path (Join-Path $cfgDir '*.cfg') -Destination $cfgDest -Force
}

Write-Output ''
Write-Output 'Installed:'
Write-Output ('  ' + (Join-Path $modDir 'z_eslmod.iwd'))
Write-Output ('  ' + (Join-Path $modDir 'mod.ff') + '   (map vote preview materials)')
Write-Output ('  ' + (Join-Path $modDir 'configs') + '\*.cfg   (exec these from your server config)')
Write-Output ''
Write-Output 'Load it in game with:'
Write-Output '  fs_game mods/ESL-MOD'
Write-Output 'or select "ESL-MOD" in the IW4x launcher mod list.'
