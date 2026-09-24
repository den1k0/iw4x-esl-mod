# =============================================================================
#  ESL-MOD build script
#
#    1. regenerates the payload          (tools\dev\build_payload.ps1)
#    2. adds the UI files                (src\ui, src\ui_mp)
#    2b. merges the weapon rebalance     (third_party\weapon_rebalance)
#    2b2. copies ESL's own weapon files  (src\weapons\extra)
#    2c. applies the ESL weapon tweaks   (src\weapons\weapon-tweaks.txt)
#    3. packs everything into build\z_eslmod.iwd
#
#  The archive contains:
#    * maps\mp\gametypes\_globallogic.gsc - the game's own script plus the whole
#      ESL implementation
#    * maps\mp\gametypes\_menus.gsc       - the game's own script-menu dispatcher,
#      with the class menus redirected to the ESL ones and every response they
#      produce routed to esl_handleCacResponse()
#    * ui_mp\...                          - the in-game create-a-class menus
#    * weapons\mp\...                     - the weapon rebalance, merged in from
#      third_party\weapon_rebalance\weapons.iwd (see docs\WEAPONS.md)
#
#  Shipping exactly one script that the engine already loads is deliberate: a
#  brand new script file is a risk, because an unresolved reference to it during
#  level initialisation leaves the client hanging on "waiting for response".
#
#  An .iwd is a ZIP archive, and entry names must use forward slashes, which is
#  why bsdtar (tar.exe) is used instead of .NET's ZipFile.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$root       = Split-Path -Parent $PSScriptRoot
$srcDir     = Join-Path $root 'src'
$payloadDir = Join-Path $root 'build\payload'
$outDir     = Join-Path $root 'build'
$iwdPath    = Join-Path $outDir 'z_eslmod.iwd'
$tarExe     = Join-Path $env:SystemRoot 'System32\tar.exe'

if (-not (Test-Path -LiteralPath $tarExe)) {
    throw "tar.exe not found at $tarExe - Windows 10 1803 or newer is required."
}

# -----------------------------------------------------------------------------
#  1. regenerate the payload (also verifies it)
# -----------------------------------------------------------------------------
& (Join-Path $PSScriptRoot 'dev\build_payload.ps1')

$payloadFile = Join-Path $payloadDir 'maps\mp\gametypes\_globallogic.gsc'
if (-not (Test-Path -LiteralPath $payloadFile)) {
    throw "Payload missing: $payloadFile"
}

# -----------------------------------------------------------------------------
#  2. add the UI trees (in-game create-a-class menus)
# -----------------------------------------------------------------------------
foreach ($uiDir in @('ui', 'ui_mp')) {
    $from = Join-Path $srcDir $uiDir
    $to   = Join-Path $payloadDir $uiDir

    if (-not (Test-Path -LiteralPath $from)) {
        throw ("UI source folder missing: " + $from)
    }

    if (Test-Path -LiteralPath $to) {
        Remove-Item -LiteralPath $to -Recurse -Force
    }

    Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
}

# -----------------------------------------------------------------------------
#  2b. the weapon rebalance
#
#  This started as a separate mod folder in <IW4x>\mods\weapon_rebalance.  It is
#  merged into z_eslmod.iwd so ESL-MOD is one self-contained mod: the archive
#  holds nothing but weapons\mp\... entries, so it cannot overlap with anything
#  else the mod ships and there is no load-order question to answer.
#
#  The repository copy is the build input - refresh it with
#  tools\dev\import_weapons.ps1 after editing the rebalance.
# -----------------------------------------------------------------------------
$weaponsIwd = Join-Path $root 'third_party\weapon_rebalance\weapons.iwd'
$weaponsDir = Join-Path $payloadDir 'weapons'

if (-not (Test-Path -LiteralPath $weaponsIwd)) {
    throw ('Weapon rebalance archive missing: ' + $weaponsIwd +
           ' - import it with tools\dev\import_weapons.ps1')
}

# Clear a stale extraction first: entries dropped from the archive would
# otherwise stay in the payload and keep getting packed.
if (Test-Path -LiteralPath $weaponsDir) {
    Remove-Item -LiteralPath $weaponsDir -Recurse -Force
}

& $tarExe -xf $weaponsIwd -C $payloadDir

if ($LASTEXITCODE -ne 0) {
    throw ('tar.exe could not extract ' + $weaponsIwd)
}

$weaponEntries = @(& $tarExe -tf $weaponsIwd | Where-Object { -not $_.EndsWith('/') })
$weaponFiles   = @(Get-ChildItem -LiteralPath $weaponsDir -Recurse -File)

if ($weaponFiles.Count -ne $weaponEntries.Count) {
    throw ('weapon rebalance: ' + $weaponEntries.Count + ' entries in the archive but ' +
           $weaponFiles.Count + ' files on disk')
}

Write-Output ('weapons : ' + $weaponFiles.Count + ' files, third_party\weapon_rebalance\weapons.iwd')

# -----------------------------------------------------------------------------
#  2b2. weapons ESL adds itself
#
#  The rebalance archive holds none of these.  They are weapons the mod brings
#  back rather than rebalances, so they live in the repository under
#  src\weapons\extra and are copied in here: before step 2c, so the tweak list
#  reaches them like any other weapon file, and before 2d, so the class editor's
#  stats table gets a row for them.
#
#  Each file must be a WEAPONFILE, or the build would pack something the engine
#  cannot read as a weapon.
# -----------------------------------------------------------------------------
$extraDir     = Join-Path $root 'src\weapons\extra'
$extraWeapons = @(Get-ChildItem -LiteralPath $extraDir -File -ErrorAction SilentlyContinue)

foreach ($extra in $extraWeapons) {
    $head = Get-Content -LiteralPath $extra.FullName -Raw

    if (-not $head.StartsWith('WEAPONFILE\')) {
        throw ('src\weapons\extra\' + $extra.Name + ' is not a WEAPONFILE - refusing to ship it')
    }
}

foreach ($extra in $extraWeapons) {
    Copy-Item -LiteralPath $extra.FullName `
              -Destination (Join-Path (Join-Path $weaponsDir 'mp') $extra.Name) -Force
}

if ($extraWeapons.Count -gt 0) {
    $weaponFiles = @(Get-ChildItem -LiteralPath $weaponsDir -Recurse -File)

    Write-Output ('extra   : ' + $extraWeapons.Count + ' file(s) from src\weapons\extra (' +
                  (($extraWeapons | ForEach-Object { $_.Name }) -join ', ') +
                  ') -> ' + $weaponFiles.Count + ' weapon files in the payload')
}

# -----------------------------------------------------------------------------
#  2c. ESL weapon tweaks
#
#  The rebalance above is somebody else's archive, so ESL's own weapon changes
#  live in a small list (src\weapons\weapon-tweaks.txt) that is applied to the
#  extracted payload here.  Re-importing the rebalance therefore cannot lose
#  them, and the result is verified right away.
#
#  Line format:
#
#      <pattern>|<dvar>[,<dvar>]|<value>[|<keep>[,<keep>]]
#
#  <keep> lists current values that are expected and deliberately left alone -
#  the underbarrel shotgun weapon that sits inside every assault rifle's family
#  of files, say.  A value that is neither the target nor a kept one *fails the
#  build*: that is the shape of "the change only reached part of the family",
#  where the source data moved and the rule would have skipped a variant without
#  saying anything.  A rule that changes no file at all fails as well.
# -----------------------------------------------------------------------------
$tweaks      = @()
$tweaksFile  = Join-Path $srcDir 'weapons\weapon-tweaks.txt'
$weaponMpDir = Join-Path $weaponsDir 'mp'

if (Test-Path -LiteralPath $tweaksFile) {
    foreach ($line in (Get-Content -LiteralPath $tweaksFile)) {
        $text = $line.Trim()

        if ($text -eq '' -or $text.StartsWith('#')) { continue }

        $parts = $text.Split('|')

        if ($parts.Count -lt 3 -or $parts.Count -gt 5) {
            throw ('weapon tweaks: expected "<pattern>|<dvar>|<value>[|<replace from>][|<keep>]", got: ' + $text)
        }

        $from = @()
        $keep = @()

        # what the rule converts (a list, because the source data is often not
        # uniform - the rebalance reached only some of a weapon's files)
        if ($parts.Count -ge 4) {
            $from = @($parts[3].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        }

        # what it deliberately leaves alone (the underbarrel shotgun living in an
        # assault rifle's family of files, say)
        if ($parts.Count -eq 5) {
            $keep = @($parts[4].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        }

        $tweaks += @{
            Pattern = $parts[0].Trim()
            Dvars   = @($parts[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
            Value   = $parts[2].Trim()
            From    = $from
            Keep    = $keep
            Samples = @()   # a file this rule changed, re-read from the archive in step 6
        }
    }

    foreach ($tweak in $tweaks) {
        if ($tweak.Dvars.Count -eq 0) {
            throw ('weapon tweaks: no dvar in the "' + $tweak.Pattern + '" entry')
        }

        $matching = @(Get-ChildItem -LiteralPath $weaponMpDir -File |
                      Where-Object { $_.Name -like $tweak.Pattern })

        if ($matching.Count -eq 0) {
            throw ('weapon tweaks: "' + $tweak.Pattern + '" matches no weapon file')
        }

        $was     = @{}
        $changed = 0

        foreach ($file in $matching) {
            $text   = Get-Content -LiteralPath $file.FullName -Raw
            $result = $text

            foreach ($dvar in $tweak.Dvars) {
                $pattern = '\\' + [regex]::Escape($dvar) + '\\([^\\]*)'
                $matches = @([regex]::Matches($result, $pattern))

                if ($matches.Count -eq 0) {
                    throw ('weapon tweaks: ' + $file.Name + ' has no "' + $dvar + '"')
                }

                # backwards, so the offsets of the earlier matches stay valid
                for ($i = $matches.Count - 1; $i -ge 0; $i--) {
                    $m       = $matches[$i]
                    $current = $m.Groups[1].Value
                    $key     = $current

                    if ($tweak.Dvars.Count -gt 1) { $key = $dvar + '=' + $current }

                    if ($was.ContainsKey($key)) { $was[$key]++ } else { $was[$key] = 1 }

                    if ($current -eq $tweak.Value) { continue }
                    if ($tweak.Keep -contains $current) { continue }

                    # With no "replace from" list the rule converts anything left,
                    # as long as it was not listed as kept; with one it converts
                    # exactly those values.  Either way a value that is neither is
                    # an error rather than something silently skipped.
                    if ($tweak.From.Count -gt 0 -and ($tweak.From -notcontains $current)) {
                        throw ('weapon tweaks: ' + $file.Name + ' has ' + $dvar + ' = ' + $current +
                               ', which this rule does not convert (converts: ' + ($tweak.From -join ', ') +
                               '; keeps: ' + ($tweak.Keep -join ', ') + ') - update the "' +
                               $tweak.Pattern + '" entry')
                    }

                    $result = $result.Substring(0, $m.Index) +
                              ('\' + $dvar + '\' + $tweak.Value) +
                              $result.Substring($m.Index + $m.Length)
                }
            }

            if ($result -ne $text) {
                # WriteAllText keeps the file byte for byte apart from the
                # replaced values; Set-Content would add a BOM and a newline.
                [System.IO.File]::WriteAllText(
                    $file.FullName,
                    $result,
                    (New-Object System.Text.UTF8Encoding($false))
                )

                $changed++

                # every changed file is recorded, not just the first.  Step 6 re-reads
                # these from the archive, and a rule that has to convert two files with
                # different source values (the M40A3's singleplayer leftover and the
                # file the mod ships, say) then proves both of them rather than
                # whichever one the directory happened to list first.
                $tweak.Samples += $file.Name
            }
        }

        if ($changed -eq 0) {
            throw ('weapon tweaks: "' + $tweak.Pattern + '" ' + ($tweak.Dvars -join ',') +
                   ' changed no file - every occurrence is already ' + $tweak.Value + ' or kept')
        }

        Write-Output ('tweaks  : ' + $tweak.Pattern + ' ' + ($tweak.Dvars -join ',') + ' = ' + $tweak.Value +
                      '  (' + $changed + '/' + $matching.Count + ' file(s) changed, was: ' +
                      (($was.Keys | Sort-Object) -join ', ') + ')')
    }
}

# -----------------------------------------------------------------------------
#  2d. the weapon stats the class editor draws
#
#  Two lines per slot, composed here and pushed to the client as dvars by
#  esl_publishWeaponStats() in _esl.gsc; the menu draws them with dvarString().
#
#  This is not a table on purpose.  A menu text can only be a literal, a dvar or a
#  table cell, and a table cell turned out to be unusable for this: the engine's
#  parser cuts a cell at a '|' (so "Primary | DMG: 40 - 30 | ..." came back as
#  column 1 = "Primary" and column 2 = the damage pair), and a plain cell drawn on
#  its own rendered nothing at all in game - the footer's values never appeared
#  while its literals did.  In script a string is a string, so the wording is
#  built here and the menu only has to draw a dvar.
#
#  The lines are read from the weapon files *after* the extra weapons (2b2) and
#  the tweaks (2c), so they are the numbers the match uses:
#
#      e.g.   |DMG: 40 - 30  |Head: 1.6x        (line A)
#             |Range: 51 m  |RPM: 706          (line B)
#
#  The key is the base name the editor puts into loadout_primary /
#  loadout_secondary ("ump45", "cheytac", ...) and the row is read from that
#  weapon's bare file (<name>_mp), not from an attachment variant, so the numbers
#  describe the gun itself.
#
#  The bare "<name>_mp" file is preferred over any attachment variant.  The M40A3
#  only resolves because the mod ships that bare file itself (src\weapons\extra,
#  step 2b2): the archive's stray "m40a3" is the singleplayer leftover whose damage
#  the tweaks normalise to the Intervention's.  Anything without a damage or a
#  fireTime value is not a weapon and is skipped.  A magazine field is not in here
#  yet.
# -----------------------------------------------------------------------------
# The payload's mp\ folder used to carry the class editor's stats table.  The stats
# are generated into the script now, so a copy left over from an older build must
# not ride along into the archive.
$staleMp = Join-Path $payloadDir 'mp'

if (Test-Path -LiteralPath $staleMp) {
    Remove-Item -LiteralPath $staleMp -Recurse -Force
}

# 1 world unit is 1 inch in this engine
$unitToMetres = 0.0254

$metric = @{}
$bare   = @{}

foreach ($file in $weaponFiles) {
    $base = $file.Name -replace '_.*$', ''

    if (-not $metric.ContainsKey($base)) { $metric[$base] = $file }
    if ($file.Name -eq ($base + '_mp'))    { $bare[$base]   = $file }
}

if ($bare.Count -gt 0) {
    foreach ($key in $bare.Keys) { $metric[$key] = $bare[$key] }
}

$statA = New-Object System.Collections.Generic.List[string]
$statB = New-Object System.Collections.Generic.List[string]

foreach ($key in ($metric.Keys | Sort-Object)) {
    $text = Get-Content -LiteralPath $metric[$key].FullName -Raw

    $maxM  = [regex]::Match($text, '\\damage\\([^\\]*)')
    $minM  = [regex]::Match($text, '\\minDamage\\([^\\]*)')
    $headM = [regex]::Match($text, '\\locHead\\([^\\]*)')
    $rngM  = [regex]::Match($text, '\\minDamageRange\\([^\\]*)')
    $fireM = [regex]::Match($text, '\\fireTime\\([^\\]*)')
    $penM  = [regex]::Match($text, '\\penetrateType\\([^\\]*)')

    if (-not ($maxM.Success -and $minM.Success -and $fireM.Success)) { continue }

    $maxDmg = [double]$maxM.Groups[1].Value
    $minDmg = [double]$minM.Groups[1].Value
    $fire   = [double]$fireM.Groups[1].Value

    if ($maxDmg -le 0 -or $fire -le 0) { continue }

    $head  = '1'
    $range = 0

    # The penetration class the file carries - none / small / medium / large - is what
    # the footer shows where the rate of fire used to be.  Of the two it is the one a
    # player cannot read off the weapon in hand: how fast it cycles can be heard, while
    # "does this shoot through the wall I am behind" cannot.  All 1194 files in the
    # payload carry the field, and a file that somehow had none shows "-" rather than a
    # guessed class.
    #
    # fireTime is no longer printed anywhere but stays in the test above: it is what
    # keeps the launchers, the killstreak weapons and the underbarrel shotgun
    # attachment out of the table, since those have no damage or no fire time.
    $pen = '-'

    if ($penM.Success -and $penM.Groups[1].Value -ne '') { $pen = $penM.Groups[1].Value }

    if ($headM.Success) { $head = $headM.Groups[1].Value }

    if ($rngM.Success) {
        $range = [int][math]::Round(([double]$rngM.Groups[1].Value) * $unitToMetres)
    }

    $lineA = '|DMG: ' + [int][math]::Round($maxDmg) + ' - ' + [int][math]::Round($minDmg) +
             '  |Head: ' + $head + 'x'

    # Spelled out, not abbreviated: "|Pen: large" was shipped first and read as a
    # truncated word rather than as a field, which is a worse outcome than two extra
    # words in a line a player has to understand at a glance.
    $lineB = '|Range: ' + $range + ' m  |Penetration: ' + $pen

    $statA.Add(([char]9 + [char]9 + 'case "' + $key + '": return "' + $lineA + '";'))
    $statB.Add(([char]9 + [char]9 + 'case "' + $key + '": return "' + $lineB + '";'))
}

if ($statA.Count -lt 20) {
    throw ('weapon stats: only ' + $statA.Count + ' weapons recognised - that cannot be right')
}

# The generated lines go into the packed _globallogic.gsc, where the [esl-stats]
# markers that _esl.gsc carries wait for them.  A weapon file name or value
# carrying a quote would break the script, so the cases are built from data the
# values below cannot contain.
$statBlock = @()
$statBlock += '// [esl-stats:begin]'
$statBlock += 'esl_weaponStatLineA( weapon )'
$statBlock += '{'
$statBlock += "`tswitch ( weapon )"
$statBlock += "`t{"
$statBlock += $statA
$statBlock += "`t}"
$statBlock += ''
$statBlock += "`treturn `"`";"
$statBlock += '}'
$statBlock += ''
$statBlock += 'esl_weaponStatLineB( weapon )'
$statBlock += '{'
$statBlock += "`tswitch ( weapon )"
$statBlock += "`t{"
$statBlock += $statB
$statBlock += "`t}"
$statBlock += ''
$statBlock += "`treturn `"`";"
$statBlock += '}'
$statBlock += '// [esl-stats:end]'

$payloadText = Get-Content -LiteralPath $payloadFile -Raw

$beginMarker = '// [esl-stats:begin]'
$endMarker   = '// [esl-stats:end]'
$begin       = $payloadText.IndexOf($beginMarker)
$end         = $payloadText.IndexOf($endMarker)

if ($begin -lt 0 -or $end -lt $begin) {
    throw ('_globallogic.gsc carries no ' + $beginMarker + ' / ' + $endMarker +
           ' markers - _esl.gsc has to provide them for the weapon stats to go in')
}

$payloadText = $payloadText.Substring(0, $begin) +
               ($statBlock -join "`n") + "`n" +
               $payloadText.Substring($end + $endMarker.Length)

[System.IO.File]::WriteAllText(
    $payloadFile,
    $payloadText,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Output ('stats   : ' + $statA.Count + ' weapons -> esl_weaponStatLine() in _globallogic.gsc')

# -----------------------------------------------------------------------------
#  2d2. the version
#
#  version.txt in the repository root is the single source.  The line below goes
#  into the mod as esl_modVersion(), and the mod is what puts it in the server name
#  and in the boot line of logs\games_mp.log - so a release is one edit here, and
#  the number the game reports cannot disagree with the code, because it is written
#  into that code.
#
#  The format is checked because an empty or malformed file would otherwise ship a
#  server called "v" instead of failing.
# -----------------------------------------------------------------------------
$versionFile = Join-Path $root 'version.txt'

if (-not (Test-Path -LiteralPath $versionFile)) {
    throw ('version.txt is missing: ' + $versionFile)
}

$version = ''

foreach ($line in (Get-Content -LiteralPath $versionFile)) {
    $trimmed = $line.Trim()

    if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

    $version = $trimmed
    break
}

if ($version -notmatch '^\d+\.\d+$') {
    throw ('version.txt: "' + $version + '" is not a version - one line like 1.0, comments start with #')
}

$versionBlock = @()
$versionBlock += '// [esl-version:begin]'
$versionBlock += 'esl_modVersion()'
$versionBlock += '{'
$versionBlock += "`treturn `"$version`";"
$versionBlock += '}'
$versionBlock += '// [esl-version:end]'

$payloadText = Get-Content -LiteralPath $payloadFile -Raw

$beginMarker = '// [esl-version:begin]'
$endMarker   = '// [esl-version:end]'
$begin       = $payloadText.IndexOf($beginMarker)
$end         = $payloadText.IndexOf($endMarker)

if ($begin -lt 0 -or $end -lt $begin) {
    throw ('_globallogic.gsc carries no ' + $beginMarker + ' / ' + $endMarker +
           ' markers - _esl.gsc has to provide them for the version to go in')
}

$payloadText = $payloadText.Substring(0, $begin) +
               ($versionBlock -join "`n") + "`n" +
               $payloadText.Substring($end + $endMarker.Length)

[System.IO.File]::WriteAllText(
    $payloadFile,
    $payloadText,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Output ('version : ' + $version + ' -> esl_modVersion() in _globallogic.gsc')

# -----------------------------------------------------------------------------
#  2e. the vote sound
#
#  Two rawfile trees the engine reads at startup:
#
#      soundaliases\esl_vote.csv     the alias the vote menus play
#      sound\esl\voting_short.wav    the file that alias names
#
#  A sound alias is a rawfile under soundaliases\: the engine loads every
#  soundaliases\*.csv it can find, which is how a mod adds a sound the game's own
#  fastfiles know nothing about.  The columns are positional, so the header line is
#  checked against the one the game's own alias files carry (dumped out of the game
#  with Unlinker - see docs\VOTING.md): a name missing from that line shifts every
#  value of every row, and the file still loads without a complaint.
#
#  Each row names its sound relative to sound\, so the file is looked up in the
#  payload as well.  A typo there is a "Missing soundalias" in the console and
#  silence in game rather than a build error, unless this catches it first.
# -----------------------------------------------------------------------------
$aliasHeader = 'name,sequence,file,vol_min,vol_max,pitch_min,pitch_max,dist_min,dist_max,channel,type,probability,loop,masterslave,loadspec,subtitle,compression,secondaryaliasname,chainaliasname,mixergroup,volumefalloffcurve,startdelay,speakermap,reverb,lfe percentage,center percentage,platform,envelop_min,envelop_max,envelop percentage,velocity_min'

foreach ($tree in @('sound', 'soundaliases', 'tables', 'images')) {
    $from = Join-Path $srcDir $tree
    $to   = Join-Path $payloadDir $tree

    if (-not (Test-Path -LiteralPath $from)) {
        throw ('sound source folder missing: ' + $from)
    }

    if (Test-Path -LiteralPath $to) {
        Remove-Item -LiteralPath $to -Recurse -Force
    }

    Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
}

$soundFileDir = Join-Path $payloadDir 'sound'
$aliasFiles   = @(Get-ChildItem -LiteralPath (Join-Path $payloadDir 'soundaliases') -File -Filter *.csv)

if ($aliasFiles.Count -eq 0) {
    throw ('no sound alias file in src\soundaliases - the vote menus play "esl_vote", ' +
           'which would not exist')
}

foreach ($alias in $aliasFiles) {
    $lines = @(Get-Content -LiteralPath $alias.FullName)

    if ($lines.Count -lt 2) {
        throw ($alias.Name + ' holds a header but no alias')
    }

    if ($lines[0].Trim() -ne $aliasHeader) {
        throw ($alias.Name + ': the header line is not the one the game uses - see docs\VOTING.md')
    }

    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line.Trim() -eq '') { continue }

        # only the first three columns are read, and the format's one quoted field
        # (",$default" in mixergroup) comes far after them
        $columns = @($line.Split(','))

        if ($columns.Count -lt 3 -or $columns[0].Trim() -eq '' -or $columns[2].Trim() -eq '') {
            throw ($alias.Name + ': "' + $line + '" is not an alias row')
        }

        $soundFile = Join-Path $soundFileDir ($columns[2].Trim() -replace '/', '\')

        if (-not (Test-Path -LiteralPath $soundFile)) {
            throw ($alias.Name + ': ' + $columns[0].Trim() + ' names ' + $columns[2].Trim() +
                   ', which is not in the payload')
        }
    }
}

$soundFiles = @(Get-ChildItem -LiteralPath $soundFileDir -Recurse -File)

Write-Output ('sound   : ' + $aliasFiles.Count + ' alias file(s), ' + $soundFiles.Count +
              ' sound file(s) -> soundaliases\, sound\')

# The end-of-match map vote (see docs\MAPVOTE.md).  The menu draws each candidate
# out of tables\esl_mapvote.csv, so those keys and the pool esl_mapVotePool()
# offers have to be the same maps: a candidate the table does not know would draw
# an empty card, and the agreed map ends up in sv_mapRotation - a map the server
# may not even have.
$mapVoteTable = Join-Path $payloadDir 'tables\esl_mapvote.csv'

if (-not (Test-Path -LiteralPath $mapVoteTable)) {
    throw 'tables\esl_mapvote.csv is missing from src\tables'
}

$tableMaps = @(Get-Content -LiteralPath $mapVoteTable |
               Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') } |
               ForEach-Object { $_.Split(',')[0].Trim() })

$voteSource = Get-Content -LiteralPath $payloadFile -Raw
$poolBlock  = [regex]::Match($voteSource, '(?s)esl_mapVoteMaps\(\)\s*\{.*?return maps;')

if (-not $poolBlock.Success) {
    throw '_esl.gsc has no esl_mapVoteMaps() - the map vote cannot offer anything'
}

$poolMaps = @([regex]::Matches($poolBlock.Value, 'maps\[\d+\]\s*=\s*"([^"]+)"') |
              ForEach-Object { $_.Groups[1].Value })

if ($poolMaps.Count -lt 2) {
    throw ('_esl.gsc: esl_mapVoteMaps() holds ' + $poolMaps.Count + ' map(s) - it needs at least 2')
}

$onlyTable = @($tableMaps | Where-Object { $poolMaps -notcontains $_ })
$onlyPool  = @($poolMaps  | Where-Object { $tableMaps -notcontains $_ })

if ($onlyTable.Count -gt 0) {
    throw ('tables\esl_mapvote.csv holds maps the vote never offers: ' + ($onlyTable -join ', '))
}

if ($onlyPool.Count -gt 0) {
    throw ('esl_mapVoteMaps() offers maps tables\esl_mapvote.csv does not have: ' + ($onlyPool -join ', '))
}

Write-Output ('mapvote : ' + $poolMaps.Count + ' maps, esl_mapVoteMaps() and tables\esl_mapvote.csv in step')

# mod.ff - the preview materials the cards draw with - declares 48 image assets, and
# the engine loads all of them when a client connects: an image whose .iwi is nowhere
# in the game's data stops that client with "could not load image '<name>'" before it
# even reaches the menu.  The game ships 46 of the 48 (images\preview_*.iwi, inside
# main\iw_02.iwd and iw4x_01.iwd); the two it does not are the ones src\images holds,
# and the other 46 are listed next to mod.ff so a build can tell the two apart
# without a game install.
$modFfDir   = Join-Path $root 'third_party\sesh_server_v2'
$modFfPath  = Join-Path $modFfDir 'mod.ff'
$modFfZone  = Join-Path $modFfDir 'mod.zone'
$gameImages = Join-Path $modFfDir 'game-provided.txt'

foreach ($need in @($modFfPath, $modFfZone, $gameImages)) {
    if (-not (Test-Path -LiteralPath $need)) {
        throw ('map vote: ' + $need + ' is missing - see docs\MAPVOTE.md')
    }
}

$provided = @(Get-Content -LiteralPath $gameImages | Where-Object { $_.Trim() -ne '' })
$ours     = @(Get-ChildItem -LiteralPath (Join-Path $srcDir 'images') -File -Filter *.iwi |
              ForEach-Object { $_.BaseName })

$declaredImages = @(Select-String -Path $modFfZone -Pattern '^image,(\S+)$' |
                    ForEach-Object { $_.Matches[0].Groups[1].Value })

if ($declaredImages.Count -eq 0) {
    throw 'map vote: mod.zone lists no images - it is not the mod.ff this mod is built around'
}

$uncovered = @($declaredImages | Where-Object { $provided -notcontains $_ -and $ours -notcontains $_ })

if ($uncovered.Count -gt 0) {
    throw ('map vote: mod.ff needs images nothing provides: ' + ($uncovered -join ', ') +
           ' - copy them out of the sesh_server_v2 archive into src\images')
}

Write-Output ('mod.ff  : ' + (Get-Item -LiteralPath $modFfPath).Length + ' bytes, ' +
              $declaredImages.Count + ' preview images (' + $ours.Count + ' shipped here, ' +
              $provided.Count + ' from the game)')

# -----------------------------------------------------------------------------
#  3. sanity checks
# -----------------------------------------------------------------------------
$payload = Get-Content -LiteralPath $payloadFile -Raw

$menusFile = Join-Path $payloadDir 'maps\mp\gametypes\_menus.gsc'
if (-not (Test-Path -LiteralPath $menusFile)) {
    throw "Patched _menus.gsc missing: $menusFile"
}
$menus = Get-Content -LiteralPath $menusFile -Raw

foreach ($check in @(
    @{ Text = "`tesl_init();";             Name = 'esl_init() hook' },
    @{ Text = 'esl_sanitizeStoredClasses'; Name = 'ESL implementation' },
    @{ Text = 'esl_handleCacResponse';     Name = 'create-a-class entry point' }
)) {
    if (-not $payload.Contains($check.Text)) {
        throw ('_globallogic.gsc is missing the ' + $check.Name)
    }
}

# any reference of the form maps\mp\gametypes\_esl:: makes the engine try to load
# _esl.gsc as a separate script, which is exactly what must never happen
if ($payload -match 'maps\\mp\\gametypes\\_esl::') {
    throw 'payload references the maps\mp\gametypes\_esl namespace'
}

# _menus.gsc must own the create-a-class redirect, otherwise the stock five
# custom classes menu opens instead of the ESL class list
if ($menus -notmatch 'esl_handleCacResponse') {
    throw '_menus.gsc does not route the ESL menus to esl_handleCacResponse()'
}

if ($menus -notmatch 'changeclass_marines_mw') {
    throw '_menus.gsc does not point the class menus at the ESL ones'
}

# _class.gsc must keep the ESL classes out of the vanilla playerdata
$classFile = Join-Path $payloadDir 'maps\mp\gametypes\_class.gsc'
if (-not (Test-Path -LiteralPath $classFile)) {
    throw "Patched _class.gsc missing: $classFile"
}
$class = Get-Content -LiteralPath $classFile -Raw

if (([regex]::Matches($class, 'esl_isCacClass\( classIndex \)')).Count -ne 7) {
    throw '_class.gsc does not redirect all seven cac_get*() accessors to the ESL storage'
}

if ($class -notmatch [regex]::Escape('esl_isCacClass( classIndex )')) {
    throw '_class.gsc is missing the ESL classIndex guard'
}

# every "!self isItemUnlocked(...)" clause in giveLoadout() must be skipped for
# the ESL classes, otherwise the player's unlock progress replaces the ESL
# loadout with the stock default class on every spawn
if (([regex]::Matches($class, 'esl_isCacClass\( self\.class_num \)')).Count -ne 13) {
    throw '_class.gsc does not bypass giveLoadout()\''s unlock checks for the ESL classes'
}

# giveLoadout() must ask the ESL class memory first, so a class the engine reset
# between rounds cannot turn into a stock loadout
if (([regex]::Matches($class, 'esl_memoryClassName\( self \)')).Count -ne 1) {
    throw '_class.gsc does not prefer the ESL class memory in giveLoadout()'
}

# and it must resolve an ESL class name without level.classMap, which the engine
# rebuilds without our entries - that is what produced an M4 with a right-looking
# class name after a round transition
if (([regex]::Matches($class, 'esl_indexForClassName\( className \)')).Count -ne 1) {
    throw '_class.gsc does not resolve ESL class names without level.classMap'
}

# the refs the ESL editor offers must survive giveLoadout()\''s own whitelists
foreach ($ref in @('ak74u', 'm40a3', 'deserteaglegold')) {
    if (([regex]::Matches($class, 'case "' + [regex]::Escape($ref) + '":')).Count -ne 1) {
        throw ('_class.gsc does not accept ref ' + $ref)
    }
}

foreach ($accessor in @('esl_cacWeapon', 'esl_cacAttachment', 'esl_cacCamo',
                        'esl_cacPerk', 'esl_cacDeathstreak', 'esl_cacOffhand')) {
    if ($class -notmatch [regex]::Escape($accessor)) {
        throw ('_class.gsc does not redirect to ' + $accessor)
    }
}

# -----------------------------------------------------------------------------
#  3b. every esl_* function that is called must also be defined
#
#  Shipping one script means a call to a helper that was never written compiles
#  to "unknown function" inside the game, and the mod then fails to load - which
#  is exactly what happened to esl_pistolAllowsAttachments().  All three
#  generated scripts share the game's function namespace, so the definitions are
#  collected across all of them.  Comments are stripped first, otherwise a helper
#  that is only mentioned in prose counts as a call site.
# -----------------------------------------------------------------------------
$defined = @{}
$called  = @{}

foreach ($script in @($payload, $menus, $class)) {
    $text = [regex]::Replace($script, '/\*.*?\*/', '', 'Singleline')
    $text = [regex]::Replace($text, '//[^\r\n]*', '')

    foreach ($m in [regex]::Matches($text, '(?m)^(esl_[A-Za-z0-9_]+)\s*\(')) {
        $defined[$m.Groups[1].Value] = $true
    }

    foreach ($m in [regex]::Matches($text, '(?<![\w\\:.])(esl_[A-Za-z0-9_]+)\s*\(')) {
        $called[$m.Groups[1].Value] = $true
    }
}

$undefined = @($called.Keys | Where-Object { -not $defined.ContainsKey($_) } | Sort-Object)

if ($undefined.Count -gt 0) {
    throw ('called but never defined: ' + ($undefined -join ', '))
}

# -----------------------------------------------------------------------------
#  3c. no local is read before it is assigned
#
#  The other half of the same failure mode: a variable that belongs to one
#  function being read in another compiles to "uninitialised variable 'x'".
#  Also a hard error, also only visible after a round trip into a map.
#
#  tools\dev\lint_gsc_locals.ps1 does the check and has a self-test
#  (tools\dev\lint_selftest.ps1) that reintroduces the known bug and asserts it
#  is reported, so a clean run means something.
# -----------------------------------------------------------------------------
$lint = Join-Path $PSScriptRoot 'dev\lint_gsc_locals.ps1'

if (Test-Path -LiteralPath $lint) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $lint

    if ($LASTEXITCODE -ne 0) {
        throw 'GSC lint failed: a local is read before it is assigned (list above)'
    }
}

# -----------------------------------------------------------------------------
#  4. collect the file list (relative, forward slashes)
# -----------------------------------------------------------------------------
$files = Get-ChildItem -LiteralPath $payloadDir -Recurse -File |
         ForEach-Object { $_.FullName.Substring($payloadDir.Length + 1).Replace('\', '/') } |
         Sort-Object

if ($files.Count -eq 0) {
    throw "No files found in $payloadDir"
}

# -----------------------------------------------------------------------------
#  5. package
# -----------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

if (Test-Path -LiteralPath $iwdPath) {
    Remove-Item -LiteralPath $iwdPath -Force
}

# The file list goes through a list file (-T) instead of the command line: with
# the weapon rebalance in the payload there are over a thousand entries, and
# Windows caps a command line at 32767 characters.
#
# Written with LF endings and no BOM - a stray CR would end up inside the entry
# name - and the names are already relative with forward slashes, so the archive
# entries come out exactly as the engine expects them.
$listFile = Join-Path $outDir 'iwd-files.txt'
[System.IO.File]::WriteAllText(
    $listFile,
    (($files -join "`n") + "`n"),
    (New-Object System.Text.UTF8Encoding($false))
)

$tarArgs = @('--format=zip', '-cf', $iwdPath, '-C', $payloadDir, '-T', $listFile)

Write-Output ('tar     : ' + $tarExe + ' --format=zip -cf <out> -C <payload> -T iwd-files.txt (' + $files.Count + ' files)')

& $tarExe $tarArgs

if ($LASTEXITCODE -ne 0) {
    throw "tar.exe failed with exit code $LASTEXITCODE"
}

# -----------------------------------------------------------------------------
#  6. verify the archive
# -----------------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem

$failures = @()

$zip     = [System.IO.Compression.ZipFile]::OpenRead($iwdPath)
$entries = @($zip.Entries | ForEach-Object { $_.FullName })

# The ESL weapon tweaks are applied to the payload, so reading back one file that
# each rule *did* change proves the payload is what got packed.  Values from the
# rule's keep list are allowed to still be there - they were meant to stay.
foreach ($tweak in $tweaks) {
    foreach ($sample in $tweak.Samples) {
        $entry = $zip.GetEntry('weapons/mp/' + $sample)

        if (-not $entry) {
            $failures += ('weapon tweak sample missing from the archive: ' + $sample)
            continue
        }

        $reader = New-Object System.IO.StreamReader($entry.Open())
        $text   = $reader.ReadToEnd()
        $reader.Close()

        foreach ($dvar in $tweak.Dvars) {
            $settled = @([regex]::Matches($text, '\\' + [regex]::Escape($dvar) + '\\([^\\]*)') |
                         ForEach-Object { $_.Groups[1].Value } |
                         Select-Object -Unique)

            $wrong = @($settled | Where-Object { $_ -ne $tweak.Value -and ($tweak.Keep -notcontains $_) })

            if ($wrong.Count -gt 0) {
                $failures += ($sample + ': ' + $dvar + ' is ' + ($wrong -join ', ') +
                              ' in the archive, expected ' + $tweak.Value)
            }
            elseif ($settled -notcontains $tweak.Value) {
                $failures += ($sample + ': ' + $dvar + ' is not ' + $tweak.Value + ' in the archive')
            }
        }
    }
}

# The weapon stats the class editor draws.  The lines checked here are the ones ESL
# sets itself, so a build that lost the generated stats - or the tweaks behind them
# - cannot ship.  They live in _globallogic.gsc as esl_weaponStatLineA/B, and the
# menu reads them out of the client dvars esl_publishWeaponStats() pushes.
$statsEntry = $zip.GetEntry('maps/mp/gametypes/_globallogic.gsc')

if (-not $statsEntry) {
    $failures += 'maps/mp/gametypes/_globallogic.gsc is missing from the archive'
}
else {
    $reader = New-Object System.IO.StreamReader($statsEntry.Open())
    $text   = $reader.ReadToEnd()
    $reader.Close()

    foreach ($check in @(
        @{ Line = 'case "ump45": return "|DMG: 40 - 30  |Head: 1.4x";'; Why = 'the rebalance values, with the SMG head multiplier' },
        @{ Line = 'case "ak47": return "|DMG: 40 - 30  |Head: 1.6x";';   Why = 'head multiplier ESL sets on assault rifles' },
        @{ Line = 'case "cheytac": return "|DMG: 70 - 70  |Head: 2x";';  Why = 'head multiplier ESL sets on sniper rifles' },
        @{ Line = 'case "m40a3": return "|DMG: 70 - 70  |Head: 2x";';   Why = 'the M40A3 is held to the Intervention''s damage and multipliers' },
        @{ Line = 'case "masada": return "|Range: 58 m  |Penetration: medium";';  Why = 'the penetration class, where the rate of fire used to be' },
        @{ Line = 'case "cheytac": return "|Range: 127 m  |Penetration: large";'; Why = 'a sniper rifle''s penetration class' },
        @{ Line = 'case "ak74u": return "|DMG: 40 - 30  |Head: 1.4x";';  Why = 'the AK-74u ESL adds, with its own damage' }
    )) {
        if ($text -notlike ('*' + $check.Line + '*')) {
            $failures += ('weapon stats: _globallogic.gsc does not hold "' + $check.Line +
                          '" (' + $check.Why + ')')
        }
    }

    # The rate of fire was replaced by the penetration class, so an "|RPM:" coming back
    # means the generator and these checks have drifted apart again - which is exactly
    # the failure this block was updated for once already.
    if ($text -like '*|RPM:*') {
        $failures += ('weapon stats: the footer carries a rate of fire again ("|RPM:") - ' +
                      'it shows the penetration class (penetrateType)')
    }

    # The version the archive carries has to be the one version.txt names: this is the
    # number the server name and the boot line report, so a stale or missing one is a
    # server that lies about which build it runs.
    if ($text -notlike ('*return "' + $version + '";*')) {
        $failures += ('_globallogic.gsc does not carry version ' + $version +
                      ' - the server name and the boot line would name the wrong build')
    }

    # The long vote sound is played by the script, at the moment it reveals the
    # cards - not by the menu: the end of a match resets a menu, so the server keeps
    # re-opening this one until it sticks (esl_mapVoteKeepOpen), and a sound in
    # onOpen would restart on every attempt.
    if ($text -notlike '*playLocalSound( "esl_vote_long" )*') {
        $failures += '_globallogic.gsc does not play the long vote sound when the cards appear'
    }
}

# The four vote menus are IW4x's own rawfiles, forked only to play the alias (see
# tools\dev\import_vote_menus.ps1 and docs\VOTING.md).  Missing from the archive, the
# game loads IW4x's copy of that one menu and the vote stays silent; present but
# without its play calls, the fork does nothing - so both are checked.
foreach ($menu in @(
    @{ Path = 'ui_mp/scriptmenus/callvote.menu';       Name = 'callvote';       Plays = 2 },
    @{ Path = 'ui_mp/scriptmenus/changemap.menu';      Name = 'changemap';      Plays = 3 },
    @{ Path = 'ui_mp/scriptmenus/changegametype.menu'; Name = 'changegametype'; Plays = 3 },
    @{ Path = 'ui_mp/scriptmenus/kickplayer.menu';     Name = 'kickplayer';     Plays = 3 }
)) {
    $entry = $zip.GetEntry($menu.Path)

    if (-not $entry) {
        $failures += ('vote menu missing from the archive: ' + $menu.Path)
        continue
    }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    $text   = $reader.ReadToEnd()
    $reader.Close()

    $calls = ([regex]::Matches($text, [regex]::Escape('play "esl_vote";'))).Count

    if ($calls -ne $menu.Plays) {
        $failures += ($menu.Name + ': plays "esl_vote" ' + $calls + ' time(s), expected ' +
                      $menu.Plays)
    }
}

# The end-of-match map vote menu (docs\MAPVOTE.md): it plays the long sound while
# it is open and draws its candidates out of the table.  Both are easy to lose in
# an edit and neither shows up as an error anywhere else.
$mapVoteMenu = $zip.GetEntry('ui_mp/scriptmenus/map_vote.menu')

if (-not $mapVoteMenu) {
    $failures += 'missing entry: ui_mp/scriptmenus/map_vote.menu'
}
else {
    $reader = New-Object System.IO.StreamReader($mapVoteMenu.Open())
    $menuText = $reader.ReadToEnd()
    $reader.Close()

    foreach ($need in @(
        @{ Text = 'tables/esl_mapvote.csv';              Why = 'the table the cards are drawn from' },
        @{ Text = 'scriptMenuResponse      "cast_vote:"'; Why = 'the vote the server counts' },
        @{ Text = 'scriptMenuResponse "menu_opened";';   Why = 'the proof that the client shows the menu' },
        @{ Text = '#define MAP_VOTE_READY';              Why = 'the readiness gate the cards hang on' },
        @{ Text = 'dvarInt( "esl_vote_ready" ) == 1';    Why = 'the dvar esl_vote_ready sets when the vote starts' }
    )) {
        if ($menuText -notlike ('*' + $need.Text + '*')) {
            $failures += ('ui_mp/scriptmenus/map_vote.menu no longer has "' + $need.Text +
                          '" (' + $need.Why + ')')
        }
    }

    # the sound moved to the script, so the menu must not have it back: onOpen runs
    # again every time the server re-opens the menu through the end-of-match reset
    if ($menuText -like '*play "esl_vote_long"*') {
        $failures += 'ui_mp/scriptmenus/map_vote.menu plays the long vote sound itself - ' +
                     'the server plays it once, when the cards appear'
    }
}

# The map vote lives inside the postgame the game's own _gamelogic.gsc provides: the
# fixed 3/6 s wait it used to do there is replaced by the call to the vote, and the
# engine's own exitLevel() below that still rotates the map.  A build that shipped
# the stock end of match - or a patched one with the hook lost - would rotate after
# three seconds whatever the vote is doing, so it is checked for here.
$gameLogicEntry = $zip.GetEntry('maps/mp/gametypes/_gamelogic.gsc')

if (-not $gameLogicEntry) {
    $failures += 'maps/mp/gametypes/_gamelogic.gsc is missing from the archive'
}
else {
    $reader = New-Object System.IO.StreamReader($gameLogicEntry.Open())
    $gameLogicText = $reader.ReadToEnd()
    $reader.Close()

    foreach ($need in @(
        @{ Text = 'maps\mp\gametypes\_globallogic::esl_mapVoteEndgame();';
           Why  = 'the vote runs where the fixed postgame wait was, after the killcam and the defeat screen' },
        @{ Text = 'maps\mp\gametypes\_globallogic::esl_gameLogicLoaded();';
           Why  = 'the boot marker that says this override loaded' },
        @{ Text = 'level notify( "exitLevel_called" );';
           Why  = 'the rotation is still the engine''s own call' }
    )) {
        if ($gameLogicText -notlike ('*' + $need.Text + '*')) {
            $failures += ('_gamelogic.gsc does not hold "' + $need.Text + '" (' + $need.Why + ')')
        }
    }

    # the wait the patch removes has to be gone: with it still in place the engine
    # would rotate the map while the vote is up
    if ($gameLogicText -like '*min( 10.0, 4.0 + level.postGameNotifies )*') {
        $failures += '_gamelogic.gsc still carries the stock postgame wait'
    }

    # and the vote call must not come before the guard, or a re-entrant endGame()
    # would run the vote twice
    $voteIdx  = $gameLogicText.IndexOf('esl_mapVoteEndgame()')
    $stateIdx = $gameLogicText.IndexOf('game["state"] == "postgame"')
    if ($voteIdx -lt 0 -or $stateIdx -lt 0 -or $voteIdx -lt $stateIdx) {
        $failures += '_gamelogic.gsc: the vote call has to come after the endGame() guard'
    }
}

# The vote cannot be *seen* while the game's own post-match scoreboard is up: that
# menu is re-opened every quarter of a second and a menu cannot be raised above one
# that is opened under it, so the vote only flashed through a frame at a time.  The
# menu is opened in _playerlogic::spawnIntermission(), and the guard that skips it
# while a vote runs has to be in the archive's copy of that script.
$playerLogicEntry = $zip.GetEntry('maps/mp/gametypes/_playerlogic.gsc')

if (-not $playerLogicEntry) {
    $failures += 'maps/mp/gametypes/_playerlogic.gsc is missing from the archive'
}
else {
    $reader = New-Object System.IO.StreamReader($playerLogicEntry.Open())
    $playerLogicText = $reader.ReadToEnd()
    $reader.Close()

    if ($playerLogicText -notlike '*!isDefined( level.eslVoteRunning )*') {
        $failures += ('_playerlogic.gsc does not skip the game''s post-match menu while a vote runs - ' +
                      'the vote would stay behind that scoreboard')
    }

    if ($playerLogicText -notlike '*esl_playerLogicLoaded*') {
        $failures += '_playerlogic.gsc has no load marker - nothing would say in the log whether it loaded'
    }

    if ($playerLogicText -notlike '*eslVoteRunning ) )*self.sessionstate = "spectator"*') {
        $failures += ('_playerlogic.gsc still puts the player into the intermission state during a vote - ' +
                      'the client''s end-of-match scoreboard would cover the vote')
    }
}

$zip.Dispose()

$bad = @($entries | Where-Object { $_.Contains('\') })
if ($bad.Count -gt 0) { $failures += ('backslash entry names: ' + ($bad -join ', ')) }

$expected = @(
    'maps/mp/gametypes/_globallogic.gsc',
    'maps/mp/gametypes/_menus.gsc',
    'maps/mp/gametypes/_class.gsc',
    'maps/mp/gametypes/_gamelogic.gsc',
    'maps/mp/gametypes/_playerlogic.gsc',
    'ui_mp/scriptmenus/changeclass_mw.menu',
    'ui_mp/scriptmenus/changeclass_marines_mw.menu',
    'ui_mp/scriptmenus/changeclass_opfor_mw.menu',
    'ui_mp/emzui/cac_ingame.inc',
    'ui_mp/scriptmenus/map_vote.menu',
    'soundaliases/esl_vote.csv',
    'sound/esl/voting_short.wav',
    'tables/esl_mapvote.csv',
    'images/preview_mp_random.iwi',
    'images/preview_custom_map.iwi'
)

foreach ($e in $expected) {
    if ($entries -notcontains $e) { $failures += ('missing entry: ' + $e) }
}

if ($entries -contains 'maps/mp/gametypes/_esl.gsc') {
    $failures += '_esl.gsc must not be shipped as its own script'
}

# the weapon rebalance must be *inside* the archive, not next to it
$weaponCount = @($entries | Where-Object { $_.StartsWith('weapons/mp/') }).Count

if ($weaponCount -ne $weaponFiles.Count) {
    $failures += ('weapon files: expected ' + $weaponFiles.Count + ' (the rebalance archive plus ' +
                  'src\weapons\extra), found ' + $weaponCount)
}

foreach ($e in @(
    'weapons/mp/ump45_mp',
    'weapons/mp/mp5k_mp',
    'weapons/mp/famas_mp',
    'weapons/mp/deserteagle_mp',
    'weapons/mp/ak74u_mp',
    'weapons/mp/m40a3_mp'
)) {
    if ($entries -notcontains $e) { $failures += ('missing weapon file: ' + $e) }
}

$size = (Get-Item -LiteralPath $iwdPath).Length

Write-Output ''
Write-Output ('Built   : ' + $iwdPath)
Write-Output ('Size    : ' + $size + ' bytes')
Write-Output ('Entries : ' + $entries.Count)
foreach ($rel in $entries) {
    if ($rel.StartsWith('weapons/')) { continue }
    Write-Output ('          ' + $rel)
}
if ($weaponCount -gt 0) {
    Write-Output ('          weapons/mp/* (' + $weaponCount + ' files)')
}

if ($failures.Count -gt 0) {
    Write-Output ''
    Write-Output 'FAILED:'
    foreach ($f in $failures) { Write-Output ('  - ' + $f) }
    exit 1
}

Write-Output ''
Write-Output 'Next step: tools\install.ps1'
