# =============================================================================
#  ESL-MOD - the weapon stat sheet (docs\weapon-stats.html)
#
#  Reads the TWEAKED weapon payload - the same files the mod packs and the same
#  numbers the in-game footer shows - and writes one self-contained HTML table:
#
#      docs\weapon-stats.html          tools\weapon-sheet.cmd
#
#  One row per weapon, with the damage pair, the damage-curve ranges, the hit
#  location multipliers, the penetration class, the aim-down-sights pair, the rate
#  of fire and the hits to kill for each hit location.
#
#  It reads build\payload\weapons\mp, which tools\build.ps1 regenerates on every
#  build, so run this AFTER a build (tools\build.cmd or tools\install.cmd) - the
#  page footer prints the payload's newest file time, so a stale sheet is visible.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\weapon-sheet.ps1
#      ... -Payload build\payload\weapons\mp -Out docs\weapon-stats.html
#      ... -Health 100      (the health the hits-to-kill column assumes)
#
#  NOTE: every number is parsed and printed with the INVARIANT culture.  Weapon
#  files write "0.266", and on a machine whose culture uses "," as the decimal
#  separator a plain [double]"0.266" is 266 - which is how a rate of fire of
#  0.085 s would quietly come out as 1 round per minute.
# =============================================================================

[CmdletBinding()]
param(
    [string] $Payload = '',
    [string] $Out     = '',
    [int]    $Health  = 100
)

$ErrorActionPreference = 'Stop'

$inv = [System.Globalization.CultureInfo]::InvariantCulture
$root = Split-Path -Parent $PSScriptRoot

# The version, from the same single source the build reads (see "Version" in
# docs\CONFIG.md) - the page names the build it describes rather than looking
# current for ever.
$version = ''

$versionFile = Join-Path $root 'version.txt'

if (Test-Path -LiteralPath $versionFile) {
    foreach ($line in (Get-Content -LiteralPath $versionFile)) {
        $trimmed = $line.Trim()

        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

        $version = $trimmed
        break
    }
}

$title = 'ESL-MOD weapon stats'

if ($version -ne '') { $title = 'ESL-MOD v' + $version + ' weapon stats' }

if (-not $Payload) { $Payload = Join-Path $root 'build\payload\weapons\mp' }
if (-not $Out)     { $Out     = Join-Path $root 'docs\weapon-stats.html' }

if (-not (Test-Path -LiteralPath $Payload)) {
    throw ('weapon payload not found: ' + $Payload + ' - run tools\build.cmd first')
}

# --- helpers ------------------------------------------------------------------

# The payload's dithered RGB tints, one per damage/hit zone; a plain table is
# harder to read at this width than the reference sheet it is modelled on.
function Format-Number([double] $value, [int] $decimals = 2) {
    return $value.ToString('0.' + ('#' * $decimals), $inv)
}

function Get-Dvar([string] $text, [string] $name) {
    $m = [regex]::Match($text, '\\' + [regex]::Escape($name) + '\\([^\\]*)')

    if ($m.Success) { return $m.Groups[1].Value.Trim() }

    return ''
}

function Get-Number([string] $text, [string] $name, [double] $default = 0) {
    $raw = Get-Dvar $text $name

    if ($raw -eq '') { return $default }

    $value = 0.0

    # invariant: "0.266" is two hundred and sixty-six thousandths, whatever the
    # machine's culture thinks a decimal separator is
    if (-not [double]::TryParse($raw, [System.Globalization.NumberStyles]::Float,
                                $inv, [ref] $value)) {
        return $default
    }

    return $value
}

# inches (the unit a weapon file uses) -> metres
function To-Metres([double] $inches) {
    return [int][math]::Round($inches * 0.0254)
}

# The hits needed to kill through the damage curve, as one cell:
#
#     "3 &#8594; 4 @ 47 m"     three hits kill up to 47 m, four are needed beyond
#     "1"                      one hit at any range
#
# The curve is the one the files describe: full damage up to maxDamageRange, then
# a straight drop to minDamage at minDamageRange, then constant.  A hit location
# with multiplier m does damage * m per hit, and a player has $Health.
function Get-HitCell([double] $dmg, [double] $minDmg, [double] $fullIn, [double] $minIn,
                     [double] $mult, [int] $health) {

    if ($mult -le 0 -or $dmg -le 0) { return '-' }

    $hits = [int][math]::Ceiling($health / ($dmg * $mult))

    if ($hits -lt 1) { $hits = 1 }

    $cell = [string] $hits
    $n    = $hits

    # Walk up the hit counts: each one holds up to the range at which the damage
    # has dropped to what that many hits need.  It stops as soon as the damage
    # cannot drop that far (the count then holds at every range).
    while ($n -lt 9) {
        $need = $health / $n / $mult

        if ($need -le $minDmg) { break }   # never reaches that damage: the count holds
        if ($need -gt $dmg)    { break }   # cannot get there: nothing left to add
        if ($minIn -le $fullIn) { break }  # no drop curve in the file at all

        # NOTE: "needs exactly the full damage" is a transition, not a stop - a
        # Deagle headshot is 50 x 2 = 100 at point blank, so one shot kills up to
        # the full-damage range and two are needed beyond it.  Comparing with >=
        # here would print "1", i.e. claim it kills at every range.

        $range = $fullIn + ($minIn - $fullIn) * (($dmg - $need) / ($dmg - $minDmg))

        if ($range -ge $minIn) { break }

        # printed even when it rounds to the same metre as the Min column: the count
        # really does change there, and dropping it would claim the lower count holds
        # at every range
        $metres = [int][math]::Round($range * 0.0254)

        $cell += ' &#8594; ' + ($n + 1) + ' @ ' + $metres + ' m'
        $n++
    }

    return $cell
}

# The rate of fire.  fireTime alone is not enough and no single field is: what
# limits a weapon differs per class.  The cycle is
#
#     cycle = max( fireTime, rechamberBoltTime, rechamberTime if > 0.2 )
#
# rechamberTime is a generic 0.1 on almost every weapon - trusting it alone would
# print 600 for everything - so it only counts when it is clearly a real cycle, and
# a bolt action keeps its real one in rechamberBoltTime (the Intervention's
# fireTime is 0.05 s = 1200 rpm while its bolt takes 0.865 s).  A semi-automatic
# weapon whose rechamberTime is the 0.1 filler ends up with the trigger as its real
# limit, and prints the fire cap the file implies.
function Get-Rpm([double] $fire, [double] $rechamber, [double] $bolt) {
    $cycle = $fire

    if ($bolt -gt $cycle) { $cycle = $bolt }
    if ($rechamber -gt 0.2 -and $rechamber -gt $cycle) { $cycle = $rechamber }
    if ($cycle -le 0) { return '' }

    return [string][int][math]::Round(60 / $cycle)
}

# --- read the payload ---------------------------------------------------------

# One row per weapon: every file of a weapon collapses into the part of its name
# before the first "_", and "<base>_mp" is preferred as the file to read (that is
# the one multiplayer loads) - the same rule tools\build.ps1 uses for the footer.
$files = @(Get-ChildItem -LiteralPath $Payload -File | Sort-Object Name)
$read  = @{}
$bare  = @{}

foreach ($file in $files) {
    $base = $file.Name -replace '_.*$', ''

    if (-not $read.ContainsKey($base)) { $read[$base] = $file }
    if ($file.Name -eq ($base + '_mp')) { $bare[$base] = $file }
}

foreach ($key in $bare.Keys) { $read[$key] = $bare[$key] }

$rows = @()

foreach ($key in ($read.Keys | Sort-Object)) {
    $file = $read[$key]
    $text = Get-Content -LiteralPath $file.FullName -Raw

    $dmg    = Get-Number $text 'damage'
    $minDmg = Get-Number $text 'minDamage'
    $fire   = Get-Number $text 'fireTime'

    # the same filter the footer uses: a file without a damage pair and a fire time
    # is not a weapon a player can be handed (the launchers, the killstreak
    # weapons, the underbarrel shotgun attachment)
    if ($dmg -le 0 -or $fire -le 0) { continue }
    if ((Get-Dvar $text 'damage') -eq '' -or (Get-Dvar $text 'minDamage') -eq '') { continue }

    $fullIn = Get-Number $text 'maxDamageRange'
    $minIn  = Get-Number $text 'minDamageRange'

    $head  = Get-Number $text 'locHead' 1
    $neck  = Get-Number $text 'locNeck' 1
    $upper = Get-Number $text 'locTorsoUpper' 1
    $lower = Get-Number $text 'locTorsoLower' 1

    $pen   = Get-Dvar $text 'penetrateType'
    $adsIn = Get-Number $text 'adsTransInTime'
    $adsOut = Get-Number $text 'adsTransOutTime'

    $rows += [pscustomobject] @{
        Key     = $key
        File    = $file.Name
        Max     = [int][math]::Round($dmg)
        Min     = [int][math]::Round($minDmg)
        Full    = To-Metres $fullIn
        Drops   = To-Metres $minIn
        Head    = $head
        Neck    = $neck
        Upper   = $upper
        Lower   = $lower
        Pen     = $(if ($pen -eq '') { '-' } else { $pen })
        AdsIn   = $adsIn
        AdsOut  = $adsOut
        Rpm     = (Get-Rpm $fire (Get-Number $text 'rechamberTime') (Get-Number $text 'rechamberBoltTime'))
        HitHead  = (Get-HitCell $dmg $minDmg $fullIn $minIn $head  $Health)
        HitNeck  = (Get-HitCell $dmg $minDmg $fullIn $minIn $neck  $Health)
        HitUpper = (Get-HitCell $dmg $minDmg $fullIn $minIn $upper $Health)
        HitLower = (Get-HitCell $dmg $minDmg $fullIn $minIn $lower $Health)
    }
}

if ($rows.Count -lt 20) {
    throw ('weapon sheet: only ' + $rows.Count + ' weapons recognised - that cannot be right')
}

# --- render -------------------------------------------------------------------

$payloadTime = (Get-ChildItem -LiteralPath $Payload -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1).LastWriteTime

$generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')

$lines = New-Object System.Collections.Generic.List[string]

[void] $lines.Add('<!DOCTYPE html>')
[void] $lines.Add('<html lang="en">')
[void] $lines.Add('<head>')
[void] $lines.Add('<meta charset="utf-8">')
[void] $lines.Add('<title>' + $title + '</title>')
[void] $lines.Add('<style>')
[void] $lines.Add('  :root { --line: #c9cdd4; --head: #eceef2; --group: #dde1e8; --dim: #5a6472; }')
[void] $lines.Add('  body { margin: 0 0 3rem; padding: 1.5rem; background: #fff; color: #12151a;')
[void] $lines.Add('         font: 13px/1.45 "Segoe UI", Roboto, system-ui, sans-serif; }')
[void] $lines.Add('  h1 { font-size: 20px; margin: 0 0 .25rem; }')
[void] $lines.Add('  .meta { color: var(--dim); margin: 0 0 1rem; }')
[void] $lines.Add('  .legend { color: var(--dim); max-width: 78ch; margin: 0 0 1rem; }')
[void] $lines.Add('  .legend code { background: var(--head); padding: 0 3px; border-radius: 3px; }')
[void] $lines.Add('  table { border-collapse: collapse; font-variant-numeric: tabular-nums; }')
[void] $lines.Add('  th, td { border: 1px solid var(--line); padding: 2px 6px; white-space: nowrap; }')
[void] $lines.Add('  thead th { background: var(--head); font-weight: 600; text-align: center; position: sticky; }')
[void] $lines.Add('  thead tr:first-child th { top: 0; background: var(--group); }')
[void] $lines.Add('  thead tr:last-child th { top: 24px; }')
[void] $lines.Add('  th.row, td.row { position: sticky; left: 0; background: var(--head); text-align: left; }')
[void] $lines.Add('  tbody tr:nth-child(even) td { background: #f7f8fa; }')
[void] $lines.Add('  tbody tr:nth-child(even) td.row { background: var(--head); }')
[void] $lines.Add('  td.num { text-align: right; }')
[void] $lines.Add('  td.hit { text-align: left; color: #12151a; }')
[void] $lines.Add('  td.one { color: #0a7a37; }')
[void] $lines.Add('  td.pen { text-align: center; }')
[void] $lines.Add('  .note { color: var(--dim); max-width: 78ch; margin-top: 1rem; }')
[void] $lines.Add('</style>')
[void] $lines.Add('</head>')
[void] $lines.Add('<body>')
[void] $lines.Add('<h1>' + $title + '</h1>')
[void] $lines.Add('<p class="meta">' + $rows.Count + ' weapons, generated ' + $generated +
                  ' from <code>build/payload/weapons/mp</code> (newest file ' +
                  $payloadTime.ToString('yyyy-MM-dd HH:mm') + ') - the tweaked payload, which is ' +
                  'what the match uses. Run <code>tools\weapon-sheet.cmd</code> again after a build.</p>')
[void] $lines.Add('<p class="legend"><b>Range</b> is in metres: <i>Full</i> is how far the maximum damage ' +
                  'holds, <i>Min</i> is where it has dropped to <code>minDamage</code> (and stays there ' +
                  'beyond). <b>Hits to kill</b> assumes ' + $Health + ' health and reads ' +
                  '<code>3 &#8594; 4 @ 47 m</code> as "three hits kill up to 47 m, four are needed ' +
                  'further out"; a plain number holds at every range. <b>RPM</b> is the real cycle: ' +
                  'the longer of the fire time and the bolt/rechamber time, so a semi-automatic ' +
                  'weapon prints the rate its fire cap implies.</p>')
[void] $lines.Add('<table>')
[void] $lines.Add('<thead>')
[void] $lines.Add('  <tr>')
[void] $lines.Add('    <th class="row" rowspan="2">Weapon</th>')
[void] $lines.Add('    <th colspan="2">Damage</th>')
[void] $lines.Add('    <th colspan="2">Range (m)</th>')
[void] $lines.Add('    <th colspan="4">Multipliers (&#215;)</th>')
[void] $lines.Add('    <th rowspan="2">Penetration</th>')
[void] $lines.Add('    <th colspan="2">ADS (s)</th>')
[void] $lines.Add('    <th rowspan="2">RPM</th>')
[void] $lines.Add('    <th colspan="4">Hits to kill</th>')
[void] $lines.Add('  </tr>')
[void] $lines.Add('  <tr>')
[void] $lines.Add('    <th>Max</th><th>Min</th>')
[void] $lines.Add('    <th>Full</th><th>Min</th>')
[void] $lines.Add('    <th>Head</th><th>Neck</th><th>Upper<br>torso</th><th>Lower<br>torso</th>')
[void] $lines.Add('    <th>In</th><th>Out</th>')
[void] $lines.Add('    <th>Head</th><th>Neck</th><th>Upper<br>torso</th><th>Lower<br>torso</th>')
[void] $lines.Add('  </tr>')
[void] $lines.Add('</thead>')
[void] $lines.Add('<tbody>')

foreach ($row in $rows) {
    $cells = @(
        '<td class="row">' + $row.Key + '</td>',
        '<td class="num">' + $row.Max + '</td>',
        '<td class="num">' + $row.Min + '</td>',
        '<td class="num">' + $row.Full + '</td>',
        '<td class="num">' + $row.Drops + '</td>',
        '<td class="num">' + (Format-Number $row.Head 2) + '</td>',
        '<td class="num">' + (Format-Number $row.Neck 2) + '</td>',
        '<td class="num">' + (Format-Number $row.Upper 2) + '</td>',
        '<td class="num">' + (Format-Number $row.Lower 2) + '</td>',
        '<td class="pen">' + $row.Pen + '</td>',
        '<td class="num">' + (Format-Number $row.AdsIn 3) + '</td>',
        '<td class="num">' + (Format-Number $row.AdsOut 3) + '</td>',
        '<td class="num">' + $row.Rpm + '</td>',
        '<td class="hit">' + $row.HitHead + '</td>',
        '<td class="hit">' + $row.HitNeck + '</td>',
        '<td class="hit">' + $row.HitUpper + '</td>',
        '<td class="hit">' + $row.HitLower + '</td>'
    )

    [void] $lines.Add('  <tr>' + ($cells -join '') + '</tr>')
}

[void] $lines.Add('</tbody>')
[void] $lines.Add('</table>')
[void] $lines.Add('<p class="note">Read straight out of the packed weapon files, so it cannot drift ' +
                  'from the match: the damage pair, the curve ends, the multipliers, the penetration ' +
                  'class and the aim times are the files'' own values, and RPM and the hits to kill ' +
                  'are computed from them. The same numbers appear in the class editor under each ' +
                  'slot, minus the torso columns - see docs/WEAPONS.md.</p>')
[void] $lines.Add('<p class="note">Files read: <code>' +
                  (($rows | ForEach-Object { $_.File }) -join ', ') + '</code></p>')
[void] $lines.Add('</body>')
[void] $lines.Add('</html>')

$outDir = Split-Path -Parent $Out

if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

# LF endings and no BOM, like the rest of the generated files here
[System.IO.File]::WriteAllText($Out, ($lines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Output ('weapon sheet: ' + $rows.Count + ' weapons')
Write-Output ('              ' + $Out)
Write-Output ('              payload newest file: ' + $payloadTime.ToString('yyyy-MM-dd HH:mm'))
