# =============================================================================
#  ESL-MOD - package the mod for players
#
#  Building:  build\ESL-MOD.zip   ->   mods\ESL-MOD\...
#
#  Players extract it into their IW4x folder so that
#      <IW4x>\mods\ESL-MOD\z_eslmod.iwd
#  exists, then pick ESL-MOD in the launcher's mod list.  That is the reliable
#  way to get a client onto the server: IW4x's own "download the mod from the
#  server" path needs an HTTP file server (sv_wwwBaseUrl, see docs\SERVER.md)
#  and without it a client that lacks the mod fails to join.
#
#  Usage:
#      tools\pack-mod.cmd
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\pack-mod.ps1 -Iw4xPath "C:\Games\iw4x"
#      ... -OutFile "D:\share\ESL-MOD.zip"
# =============================================================================

[CmdletBinding()]
param(
    [string] $Iw4xPath = 'D:\Games\iw4x',
    [string] $OutFile  = '',

    # keep the server-only folders (logs, demos) in the archive
    [switch] $IncludeLogs
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $Iw4xPath 'mods\ESL-MOD'

if (-not $OutFile) {
    $OutFile = Join-Path $root 'build\ESL-MOD.zip'
}

if (-not (Test-Path -LiteralPath $src)) {
    throw "Mod folder not found: $src - run tools\install.ps1 first"
}

$iwd = Join-Path $src 'z_eslmod.iwd'
if (-not (Test-Path -LiteralPath $iwd)) {
    throw "Mod archive not found: $iwd - run tools\install.ps1 first"
}

# stage a clean tree so the zip contains mods\ESL-MOD\... and nothing else
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('eslmod-pack-' + [guid]::NewGuid().ToString('N'))
$stageMod = Join-Path $stage 'mods\ESL-MOD'

New-Item -ItemType Directory -Force -Path $stageMod | Out-Null
Copy-Item -Path (Join-Path $src '*') -Destination $stageMod -Recurse -Force

if (-not $IncludeLogs) {
    # folders first, then the log files - IW4x rotates them, so console_mp.log
    # also shows up as console_mp.log.000, .001, ...
    foreach ($drop in @('logs', 'demos')) {
        $p = Join-Path $stageMod $drop
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }

    foreach ($pattern in @('console_mp.log*', 'games_mp.log*', '*.minidump', '*.dmp')) {
        Get-ChildItem -LiteralPath $stageMod -Filter $pattern -File -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    }
}

$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $OutFile)
Remove-Item -LiteralPath $stage -Recurse -Force

$file = Get-Item -LiteralPath $OutFile
$sha  = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash

Write-Output ''
Write-Output 'Packed the mod for players:'
Write-Output ('  archive : ' + $file.FullName)
Write-Output ('  size    : ' + $file.Length + ' bytes')
Write-Output ('  sha256  : ' + $sha)
Write-Output ''
Write-Output 'Players:'
Write-Output '  1. extract the zip into the IW4x folder (it contains mods\ESL-MOD\...)'
Write-Output '  2. select ESL-MOD in the launcher, then join the server'
