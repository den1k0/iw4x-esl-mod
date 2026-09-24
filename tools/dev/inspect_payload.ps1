<#
    inspect_payload.ps1 - structural sanity check of the generated GSC payload.

    The GSC compiler's "bad syntax" errors sometimes come with an empty
    file/line annotation, which happens when the parser runs off the end of the
    file.  This script prints the things that cause that:

      * the byte values of the first / last few bytes (BOM, missing newline)
      * the seam where src\maps\mp\gametypes\_esl.gsc was appended
      * the count of "{", "}", "#include", "#using_animtree" etc.
      * any line whose first non-space character looks wrong

    Usage:
        powershell -NoProfile -File tools\dev\inspect_payload.ps1
#>

[CmdletBinding()]
param(
    [string] $Payload = 'build\payload\maps\mp\gametypes\_globallogic.gsc'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Payload)) {
    Write-Output "payload not found: $Payload"
    exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($Payload)
$text  = [System.Text.Encoding]::ASCII.GetString($bytes)
$lines = $text -split "`n"

Write-Output "file      : $Payload"
Write-Output "bytes     : $($bytes.Length)"
Write-Output "lines     : $($lines.Count)"
Write-Output ('first byte: 0x{0:X2}   last byte: 0x{1:X2}' -f $bytes[0], $bytes[$bytes.Length - 1])
Write-Output ''

# --- EOF / BOM checks ---------------------------------------------------------
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Output 'WARNING: UTF-8 BOM at start of file (GSC parser does not expect one)'
}
if ($bytes[$bytes.Length - 1] -ne 0x0A) {
    Write-Output 'WARNING: file does not end with a newline (can produce "bad syntax" at EOF)'
} else {
    Write-Output 'ok: file ends with LF'
}
if ($text.Contains("`r")) {
    Write-Output 'note: file contains CR characters (CRLF line endings)'
}
Write-Output ''

# --- seam ---------------------------------------------------------------------
$seam = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*//\s*=+\s*$') { continue }
    if ($lines[$i] -match 'esl_init\s*\(\s*\)\s*;') { $seam = $i; break }
}

if ($seam -ge 0) {
    Write-Output "== first esl_init() hook at line $($seam + 1) =="
    $s = [Math]::Max(0, $seam - 6)
    $e = [Math]::Min($lines.Count - 1, $seam + 6)
    for ($i = $s; $i -le $e; $i++) { Write-Output ('{0,6}: {1}' -f ($i + 1), $lines[$i].TrimEnd()) }
    Write-Output ''
}

# --- token tallies ------------------------------------------------------------
$openBrace  = ([regex]::Matches($text, '\{')).Count
$closeBrace = ([regex]::Matches($text, '\}')).Count
$openParen  = ([regex]::Matches($text, '\(')).Count
$closeParen = ([regex]::Matches($text, '\)')).Count
$includes   = ([regex]::Matches($text, '(?m)^\s*#include')).Count
$blockOpen  = ([regex]::Matches($text, '/#')).Count
$blockClose = ([regex]::Matches($text, '#/')).Count

Write-Output "braces    : $openBrace / $closeBrace"
Write-Output "parens    : $openParen / $closeParen"
Write-Output "#include  : $includes"
Write-Output "/*-blocks : $blockOpen / $blockClose"
Write-Output ''

# --- suspicious lines ---------------------------------------------------------
Write-Output '== lines starting with a character that cannot start a statement =='
$bad = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    $t = $lines[$i].Trim()
    if ($t -eq '') { continue }
    if ($t.StartsWith('//')) { continue }

    # same-line "case X: something"
    if ($t -match '^case\s+.*:\s*\S') {
        Write-Output ('{0,6}: same-line case  | {1}' -f ($i + 1), $t)
        $bad++
        continue
    }

    # a statement ending with an operator (line continuation used by mistake)
    if ($t -match '[-+*/&|=<>]\s*$' -and $t -notmatch '[),]$') {
        Write-Output ('{0,6}: dangling operator | {1}' -f ($i + 1), $t)
        $bad++
        continue
    }

    # "} else" / "else {" / ") {" brace-on-next-line style
    if ($t -match '^}\s*else' -or $t -match '^else\s*\{') {
        Write-Output ('{0,6}: brace style     | {1}' -f ($i + 1), $t)
        $bad++
        continue
    }

    # dot-method calls are field access in GSC, not calls
    if ($t -match 'self\.[A-Za-z_][A-Za-z0-9_]*\s*\(') {
        Write-Output ('{0,6}: dot-call        | {1}' -f ($i + 1), $t)
        $bad++
        continue
    }
}
if ($bad -eq 0) { Write-Output '   none' }
Write-Output ''

# --- tail ---------------------------------------------------------------------
Write-Output '== last 8 lines =='
$s = [Math]::Max(0, $lines.Count - 8)
for ($i = $s; $i -lt $lines.Count; $i++) { Write-Output ('{0,6}: {1}' -f ($i + 1), $lines[$i].TrimEnd()) }
