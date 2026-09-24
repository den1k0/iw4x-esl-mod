# =============================================================================
#  GSC local-variable lint for the ESL body
#
#  GSC refuses to compile a function that reads a variable the compiler never
#  saw assigned:
#
#      ******* script compile error *******
#      Error: uninitialised variable 'attachok'
#
#  That is a hard error, so the whole mod fails to load - and the game reports
#  one name at a time, only after a full round trip into a map.  Both mistakes
#  of this class so far had the same shape: a variable that belongs to one
#  function being read in another (attachOk / xmagsOk are locals of
#  esl_pushAvailability(), and the side-arm response read them anyway).
#
#  The check is deliberately loose: a name counts as assigned if it is assigned
#  anywhere inside its own function, and parameters count too.  That keeps false
#  positives at zero while still catching the cross-function case, because there
#  the name is never assigned in the function that reads it at all.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\lint_gsc_locals.ps1
#
#  Exit code is 0 when clean, 1 when something was reported.
# =============================================================================

param(
    [string]$File = ''
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$src  = if ($File -ne '') { $File } else { Join-Path $root 'src\maps\mp\gametypes\_esl.gsc' }

if (-not (Test-Path -LiteralPath $src)) {
    throw "ESL source not found: $src"
}

$text = Get-Content -LiteralPath $src -Raw

# Comments first: a helper that is only mentioned in prose must not count as a
# read, and the ESL file is heavily commented on purpose.
$text = [regex]::Replace($text, '/\*.*?\*/', '', 'Singleline')
$text = [regex]::Replace($text, '//[^\r\n]*', '')

$lines = $text -split "\r?\n"

$keywords = @{}
foreach ($k in @(
    'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default', 'return',
    'break', 'continue', 'thread', 'waittill', 'endon', 'notify', 'not', 'and',
    'or', 'self', 'level', 'game', 'undefined', 'true', 'false', 'int', 'float',
    'string', 'vector', 'function', 'static', 'const', 'embed', 'foreach', 'in',
    'to', 'by', 'step', 'assert', 'println', 'print', 'isDefined', 'isdefined',
    'wait', 'waittillframeend', 'waittillmatch', 'switchto', 'endon', 'breakpoint'
)) {
    $keywords[$k.ToLower()] = $true
}

# -----------------------------------------------------------------------------
#  collect the top-level functions (GSC: the name starts in column 0, the body
#  is everything up to the closing brace in column 0)
# -----------------------------------------------------------------------------
$functions = @()

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s*\(([^()]*)\)\s*$') {
        continue
    }

    $name   = $Matches[1]
    $params = $Matches[2]

    $open = $i + 1
    while ($open -lt $lines.Count -and $lines[$open].Trim() -ne '{') { $open++ }

    $body = New-Object System.Collections.Generic.List[int]
    $k = $open + 1
    while ($k -lt $lines.Count -and $lines[$k] -ne '}') {
        $body.Add($k)
        $k++
    }

    $functions += [pscustomobject]@{
        Name   = $name
        Params = $params
        Body   = $body
        Line   = $i + 1
    }

    $i = $k
}

# every function defined in the file, so a bare function reference (self thread
# foo without parentheses does not happen, but ::foo and level.callback = ::foo
# do) is not mistaken for a variable
$defined = @{}
foreach ($f in $functions) { $defined[$f.Name.ToLower()] = $true }

# -----------------------------------------------------------------------------
#  analyse
# -----------------------------------------------------------------------------
$problems = @()

foreach ($f in $functions) {
    $bodyText = ($f.Body | ForEach-Object { $lines[$_] }) -join "`n"

    $assigned = @{}
    foreach ($p in ($f.Params -split ',')) {
        $p = $p.Trim()
        if ($p -match '^[A-Za-z_][A-Za-z0-9_]*$') { $assigned[$p.ToLower()] = $true }
    }

    # assignment: the name is assigned somewhere in this function.  The leading
    # character class rules out field writes such as self.x = 1 or level.x = 1.
    foreach ($m in [regex]::Matches($bodyText, '(?:^|[;{(\s])([A-Za-z_][A-Za-z0-9_]*)\s*=[^=]')) {
        $assigned[$m.Groups[1].Value.ToLower()] = $true
    }

    # waittill / notify bind their trailing arguments as variables:
    #     level waittill( "connected", player );
    foreach ($m in [regex]::Matches($bodyText, '(?:waittill|notify)\s*\([^)]*?,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)')) {
        $assigned[$m.Groups[1].Value.ToLower()] = $true
    }

    # reads: drop calls, string literals and field accesses first
    $reads = $bodyText
    $reads = [regex]::Replace($reads, '[A-Za-z_][A-Za-z0-9_]*\s*\(', '(')
    $reads = [regex]::Replace($reads, '"[^"]*"', '""')
    $reads = [regex]::Replace($reads, '\.[A-Za-z_][A-Za-z0-9_]*', '')
    # namespaces are references, not variables: maps\mp\gametypes\_class::foo(...)
    $reads = [regex]::Replace($reads, '[A-Za-z_][A-Za-z0-9_\\]*::', '')

    $seen = @{}
    foreach ($m in [regex]::Matches($reads, '[A-Za-z_][A-Za-z0-9_]*')) {
        $name = $m.Value
        $key  = $name.ToLower()

        if ($seen.ContainsKey($key)) { continue }
        if ($keywords.ContainsKey($key)) { continue }
        if ($assigned.ContainsKey($key)) { continue }
        if ($defined.ContainsKey($key)) { continue }

        $seen[$key] = $true

        # find the line it was read on, for the report
        $where = 0
        for ($b = 0; $b -lt $f.Body.Count; $b++) {
            if ($lines[$f.Body[$b]] -match ('(?<![\w.$])' + [regex]::Escape($name) + '(?![\w])')) {
                $where = $f.Body[$b] + 1
                break
            }
        }

        $problems += [pscustomobject]@{
            Function = $f.Name
            Variable = $name
            Line     = $where
        }
    }
}

if ($problems.Count -eq 0) {
    Write-Output ('lint    : ' + $functions.Count + ' functions in _esl.gsc, no unassigned locals')
    exit 0
}

Write-Output ('lint    : ' + $problems.Count + ' unassigned local(s) in ' + $functions.Count + ' functions')
foreach ($p in $problems) {
    Write-Output ('  ' + $p.Function + '  reads  ' + $p.Variable + '   (line ' + $p.Line + ')')
}

exit 1
