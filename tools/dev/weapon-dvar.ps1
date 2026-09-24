# =============================================================================
#  Reads a single weapon dvar out of the weapon files of a build payload.
#
#  A weapon file is a small text file: an intro, then one or more long lines of
#  "\key\value" pairs (a file can hold more than one weapon variant, so every
#  occurrence is printed, not just the first).
#
#  Usage:
#      powershell -NoProfile -File tools\dev\weapon-dvar.ps1 -Dvar adsTransInTime
#      powershell -NoProfile -File tools\dev\weapon-dvar.ps1 -Dvar adsTransInTime -Filter cheytac*
#      powershell -NoProfile -File tools\dev\weapon-dvar.ps1 -Dvar damage -Filter ump45* -Distinct
#
#  -Filter is a wildcard on the file name (default: every weapon file).
#  -Distinct collapses the result to "value(s) = count", which is what matters
#  when a tweak is supposed to give every variant of a weapon the same number.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Dvar,

    [string] $Filter = '*',

    [string] $Path,

    [switch] $Distinct
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $Path) {
    $Path = Join-Path $root 'build\payload\weapons\mp'
}

if (-not (Test-Path -LiteralPath $Path)) {
    throw ('weapon folder not found: ' + $Path + ' - run tools\build.cmd first')
}

$files = @(Get-ChildItem -LiteralPath $Path -File |
           Where-Object { $_.Name -like $Filter } |
           Sort-Object Name)

if ($files.Count -eq 0) {
    throw ('no weapon file matches "' + $Filter + '" in ' + $Path)
}

# The value runs until the next backslash, or until the end of the file.
$pattern = '\\' + [regex]::Escape($Dvar) + '\\([^\\]*)'

$groups = @{}

foreach ($file in $files) {
    $text    = Get-Content -LiteralPath $file.FullName -Raw
    $matches = [regex]::Matches($text, $pattern)

    if ($matches.Count -eq 0) {
        $shown = '<not set>'
    }
    else {
        $shown = (($matches | ForEach-Object { $_.Groups[1].Value }) |
                  Select-Object -Unique) -join ', '
    }

    if ($Distinct) {
        if ($groups.ContainsKey($shown)) { $groups[$shown]++ } else { $groups[$shown] = 1 }
    }
    else {
        Write-Output ($file.Name + ' = ' + $shown)
    }
}

if ($Distinct) {
    Write-Output ($Dvar + ' over ' + $files.Count + ' file(s) matching "' + $Filter + '":')
    foreach ($key in ($groups.Keys | Sort-Object)) {
        Write-Output ('  ' + $key + '  (' + $groups[$key] + ')')
    }
}
