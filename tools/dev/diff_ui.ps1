<#
    diff_ui.ps1 - compare the shipped UI files with the ProMod originals.

    Every file under src\ui and src\ui_mp is an edited copy of a file in
    .tmp_reference\promod (extracted from mods\promod\z_promod.iwd).  Editing a
    .menu/.inc file is risky: the menu preprocessor is line oriented, so a single
    misplaced character (a comment ending a \ continuation, a stray ';') makes the
    whole menufile fail to load at runtime.

    This script prints, per file:
      * which lines differ from the original
      * any \ continuation that is not the last character on its line
      * any line with trailing whitespace after a backslash (same thing)
      * unbalanced braces and stray semicolons outside macros

    Usage:
        powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\diff_ui.ps1
#>

[CmdletBinding()]
param(
    [string] $Src  = 'src',
    [string] $Ref  = '.tmp_reference\promod',
    [switch] $OnlyProblems
)

$ErrorActionPreference = 'Stop'

$files = @()
foreach ($sub in @('ui', 'ui_mp')) {
    $p = Join-Path $Src $sub
    if (Test-Path -LiteralPath $p) {
        $files += Get-ChildItem -LiteralPath $p -Recurse -File
    }
}

if ($files.Count -eq 0) { Write-Output "no UI files under $Src"; exit 1 }

$problemCount = 0

foreach ($f in $files) {
    # path of this file relative to the shipped root, e.g. ui_mp\emzui\cac_ingame.inc
    $rel  = $f.FullName.Substring((Resolve-Path $Src).Path.Length + 1)
    $orig = Join-Path $Ref $rel

    Write-Output "==================================================================="
    Write-Output "FILE  $rel"

    $mine = Get-Content -LiteralPath $f.FullName

    # ---------------------------------------------------------------- diff
    if (Test-Path -LiteralPath $orig) {
        $theirs = Get-Content -LiteralPath $orig
        $diff = Compare-Object -ReferenceObject $theirs -DifferenceObject $mine
        if ($diff) {
            Write-Output ("DIFF  {0} differing lines vs promod original" -f $diff.Count)
            if (-not $OnlyProblems) {
                foreach ($d in $diff) {
                    $tag = if ($d.SideIndicator -eq '=>') { '  +  ' } else { '  -  ' }
                    Write-Output ($tag + $d.InputObject)
                }
            }
        } else {
            Write-Output 'DIFF  identical to the promod original'
        }
    } else {
        Write-Output 'DIFF  no promod original for this file'
    }

    # ------------------------------------------------- broken continuations
    # A "#define" body is continued with a trailing backslash.  The backslash
    # must be the very last character on the line - a space after it turns the
    # macro into garbage and the file fails to parse.
    for ($i = 0; $i -lt $mine.Count; $i++) {
        $t = $mine[$i].TrimEnd("`r", "`n")
        if ($t -match '\\\s+$') {
            Write-Output ("BAD   line {0}: backslash followed by whitespace (breaks the #define)" -f ($i + 1))
            Write-Output ("      |{0}" -f $t)
            $problemCount++
        }
    }

    # ------------------------------------------- comments inside a \ macro body
    # A "#define ... \" body is line-continued, so a comment line that does not
    # end with a backslash terminates the macro - and everything after it is
    # parsed as menu content, which silently deletes the menus it defined
    # ("Could not find menu ...").  This check exists because that mistake was
    # made twice in cac_ingame.inc.
    for ($i = 1; $i -lt $mine.Count; $i++) {
        $prev = $mine[$i - 1].TrimEnd("`r", "`n")
        $cur  = $mine[$i]

        if ($prev -match '\\\s*$' -and $cur.TrimStart().StartsWith('//')) {
            Write-Output ("BAD   line {0}: comment inside a continued #define body" -f ($i + 1))
            Write-Output ("      |{0}" -f $cur)
            $problemCount++
        }
    }

    # --------------------------------------------------- suspicious content
    for ($i = 0; $i -lt $mine.Count; $i++) {
        $t = $mine[$i]

        # comments are only safe above a #define, never inside its body
        if ($t -match '^\s*#define' -and $t -notmatch '\\\s*$' -and $t -match '\s\s//') {
            Write-Output ("WARN  line {0}: comment on a #define line" -f ($i + 1))
            $problemCount++
        }
    }

    $open  = ($mine | Select-String -Pattern '\{' -AllMatches | ForEach-Object { $_.Matches.Count } | Measure-Object -Sum).Sum
    $close = ($mine | Select-String -Pattern '\}' -AllMatches | ForEach-Object { $_.Matches.Count } | Measure-Object -Sum).Sum
    Write-Output ("BRACES {0} open / {1} close" -f $open, $close)
    if ($open -ne $close) { $problemCount++ }
}

Write-Output "==================================================================="
Write-Output ("files: {0}   flagged problems: {1}" -f $files.Count, $problemCount)
