# =============================================================================
#  ESL-MOD uninstaller
#
#  Removes <IW4x>\mods\ESL-MOD
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\uninstall.ps1
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\uninstall.ps1 -Iw4xPath "C:\Games\iw4x"
# =============================================================================

[CmdletBinding()]
param(
    [string] $Iw4xPath = 'D:\Games\iw4x'
)

$ErrorActionPreference = 'Stop'

$modDir = Join-Path $Iw4xPath 'mods\ESL-MOD'

if (-not (Test-Path -LiteralPath $modDir)) {
    Write-Output ('Nothing to do, not installed: ' + $modDir)
    exit 0
}

Remove-Item -LiteralPath $modDir -Recurse -Force
Write-Output ('Removed: ' + $modDir)
