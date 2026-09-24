# =============================================================================
#  ESL-MOD development helper - import the vote menus
#
#  IW4x's voting is its own UI: the stock game has the vote *commands*, but the
#  menu that issues them (`callvote`, `kickplayer`, `changemap`, `changegametype`)
#  ships as rawfiles inside IW4x's own archive, iw4x\iw4x_00.iwd.
#
#  A mod .iwd overrides a rawfile by carrying the same path, so those four menus
#  are what ESL-MOD has to fork to add anything to a vote - here a sound, see
#  docs/VOTING.md.  This script copies them out of the IW4x archive into src\ui_mp
#  (which the build packs), and prints the hash of each one so the fork stays
#  traceable to the build of the game it came from.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\import_vote_menus.ps1
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\import_vote_menus.ps1 -WhatIf
# =============================================================================

[CmdletBinding()]
param(
    [string] $Iw4xPath = 'D:\Games\iw4x',
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path -LiteralPath $Iw4xPath)) {
    throw "IW4x install not found: $Iw4xPath (pass -Iw4xPath)"
}

$menus = @(
    'callvote.menu',
    'changemap.menu',
    'changegametype.menu',
    'kickplayer.menu'
)

$sourceArchive = Get-ChildItem -LiteralPath (Join-Path $Iw4xPath 'iw4x') -Filter '*.iwd' |
                 Where-Object { $_.Name -like 'iw4x_*' } |
                 Sort-Object Name |
                 Where-Object {
                     $zip = [System.IO.Compression.ZipFile]::OpenRead($_.FullName)
                     $found = $zip.GetEntry('ui_mp/scriptmenus/callvote.menu') -ne $null
                     $zip.Dispose()
                     $found
                 } |
                 Select-Object -First 1

if (-not $sourceArchive) {
    throw ("no archive under " + (Join-Path $Iw4xPath 'iw4x') +
           ' carries ui_mp/scriptmenus/callvote.menu - is this an IW4x install?')
}

$outDir = Join-Path $root 'src\ui_mp\scriptmenus'

if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Write-Output ('source  : ' + $sourceArchive.FullName)

$zip = [System.IO.Compression.ZipFile]::OpenRead($sourceArchive.FullName)

try {
    foreach ($menu in $menus) {
        $entry = $zip.GetEntry('ui_mp/scriptmenus/' + $menu)

        if (-not $entry) {
            throw ('ui_mp/scriptmenus/' + $menu + ' is not in ' + $sourceArchive.Name)
        }

        $reader = New-Object System.IO.StreamReader($entry.Open())
        $text   = $reader.ReadToEnd()
        $reader.Close()

        # the engine reads either ending, but a mixed file is a needless variable
        $text = $text -replace "`r`n", "`n"

        $target = Join-Path $outDir $menu

        if ($WhatIf) {
            Write-Output ('would write : ' + $target)
            continue
        }

        # written with LF endings and no BOM - a stray BOM would be parsed as the
        # first token of the menu
        [System.IO.File]::WriteAllText($target, $text, (New-Object System.Text.UTF8Encoding($false)))

        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

        Write-Output ('imported: src\ui_mp\scriptmenus\' + $menu +
                      '  (' + (Get-Item -LiteralPath $target).Length + ' bytes, sha256 ' +
                      $hash.Substring(0, 16) + '...)')
    }
}
finally {
    $zip.Dispose()
}
