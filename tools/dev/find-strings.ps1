# =============================================================================
#  ESL-MOD development helper - printable strings in a binary
#
#  Used to find out which dvars / URLs a game binary knows about, e.g. the mod
#  download machinery:
#
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\find-strings.ps1 ^
#          -Path "D:\Games\iw4x\iw4x.dll" -Filter "ownload|www|modlist"
#
#  Usage:
#      ... -Path <file>[,<file>] -Filter <regex> [-MinLen 6] [-Max 60]
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]] $Path,
    [Parameter(Mandatory = $true)][string]   $Filter,
    [int] $MinLen = 6,
    [int] $Max    = 60
)

$ErrorActionPreference = 'Stop'
$latin1 = [System.Text.Encoding]::GetEncoding(28591)

foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ('missing: ' + $p)
        continue
    }

    $bytes = [System.IO.File]::ReadAllBytes($p)
    $text  = $latin1.GetString($bytes)

    $found = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($text, '[\x20-\x7E]{' + $MinLen + ',}')) {
        if ($m.Value -match $Filter) { $found.Add($m.Value) }
    }

    $unique = @($found | Sort-Object -Unique)

    Write-Output ('=== ' + $p + ' : ' + $unique.Count + ' matching strings')
    $unique | Select-Object -First $Max | ForEach-Object { Write-Output ('  ' + $_) }
    Write-Output ''
}
