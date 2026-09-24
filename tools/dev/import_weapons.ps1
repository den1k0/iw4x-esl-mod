# =============================================================================
#  ESL-MOD development helper - weapon rebalance import
#
#  The weapon rebalance started life as its own mod folder
#  (<IW4x>\mods\weapon_rebalance\weapons.iwd).  ESL-MOD ships it *inside*
#  z_eslmod.iwd, so the build needs the archive in the repository:
#
#      <IW4x>\mods\weapon_rebalance\weapons.iwd
#          -> third_party\weapon_rebalance\weapons.iwd
#      <IW4x>\mods\weapon_rebalance\changelog.txt
#          -> third_party\weapon_rebalance\changelog.txt
#
#  Run this again whenever the rebalance is edited.  The build always packs the
#  repository copy, so a build never depends on the installed game folder - and
#  a fresh clone can be built without one.
#
#  The archive must contain nothing but weapons\... entries: it is merged into
#  the ESL payload, and anything else would fight with the mod's own files.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\import_weapons.ps1
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\import_weapons.ps1 -Iw4xPath "C:\Games\iw4x"
# =============================================================================

[CmdletBinding()]
param(
    [string] $Iw4xPath = 'D:\Games\iw4x',
    [string] $ModName  = 'weapon_rebalance',
    [int]    $MinFiles = 100
)

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$srcDir  = Join-Path $Iw4xPath ('mods\' + $ModName)
$destDir = Join-Path $root 'third_party\weapon_rebalance'
$tarExe  = Join-Path $env:SystemRoot 'System32\tar.exe'

$srcIwd = Join-Path $srcDir 'weapons.iwd'

if (-not (Test-Path -LiteralPath $tarExe)) {
    throw "tar.exe not found at $tarExe - Windows 10 1803 or newer is required."
}

if (-not (Test-Path -LiteralPath $srcIwd)) {
    throw "Weapon rebalance archive not found: $srcIwd"
}

# --- read the archive before copying it ---------------------------------------
# An .iwd is a ZIP; tar.exe reads it and lists the entry names with forward
# slashes, which is also the naming the packer needs.
$entries = @(& $tarExe -tf $srcIwd)

if ($LASTEXITCODE -ne 0) {
    throw "tar.exe could not read $srcIwd (exit code $LASTEXITCODE)"
}

$files  = @($entries | Where-Object { -not $_.EndsWith('/') })
$stray  = @($files | Where-Object { -not $_.StartsWith('weapons/') })

if ($stray.Count -gt 0) {
    throw ('archive contains entries outside weapons/: ' + ($stray -join ', '))
}

if ($files.Count -lt $MinFiles) {
    throw ('only ' + $files.Count + ' weapon files in the archive - wrong iwd?')
}

# --- copy ---------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
}

$destIwd = Join-Path $destDir 'weapons.iwd'
Copy-Item -LiteralPath $srcIwd -Destination $destIwd -Force

$changelog = Join-Path $srcDir 'changelog.txt'
$destLog   = Join-Path $destDir 'changelog.txt'
if (Test-Path -LiteralPath $changelog) {
    Copy-Item -LiteralPath $changelog -Destination $destLog -Force
}

$destFile = Get-Item -LiteralPath $destIwd
$sha      = (Get-FileHash -LiteralPath $destIwd -Algorithm SHA256).Hash

Write-Output ''
Write-Output 'Imported weapon rebalance:'
Write-Output ('  source       : ' + $srcIwd)
Write-Output ('  archive      : ' + $destIwd)
Write-Output ('  weapon files : ' + $files.Count)
Write-Output ('  size         : ' + $destFile.Length + ' bytes')
Write-Output ('  sha256       : ' + $sha)
if (Test-Path -LiteralPath $destLog) {
    Write-Output ('  changelog    : ' + $destLog)
}
Write-Output ''
Write-Output 'Next step: tools\build.ps1   (packs it into z_eslmod.iwd)'
