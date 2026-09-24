# =============================================================================
#  ESL-MOD development helper - diagnostic probe builds
#
#  Builds and installs three throwaway mods that isolate *why* a modded private
#  match hangs on the loading screen while the vanilla game loads fine:
#
#    ESL-PROBE-A  ships the game's own _globallogic.gsc completely unchanged
#                 (no hook, no extra code).  Answers: "does overriding this
#                 script file at all break loading?"
#
#    ESL-PROBE-B  ships it with one synchronous hook call to a function that
#                 only prints and sets a level variable.  Answers: "does
#                 inserting a call + adding a function break loading?"
#
#    ESL-PROBE-C  same as B but the probe runs in a thread, which is what the
#                 real mod does for everything except two dvar writes.
#
#  If A hangs -> the problem is the raw-script override mechanism itself.
#  If A works but B hangs -> the problem is the hook/insertion or extra function.
#  If B works but C hangs -> the problem is starting a thread from init().
#  If all three work -> the problem is somewhere in the ESL implementation.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\build_probes.ps1
# =============================================================================

[CmdletBinding()]
param(
    [string] $Iw4xPath = 'D:\Games\iw4x'
)

$ErrorActionPreference = 'Stop'

$root     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$baseFile = Join-Path $root '.tmp_reference\base\maps\mp\gametypes\_globallogic.gsc'
$tarExe   = Join-Path $env:SystemRoot 'System32\tar.exe'

if (-not (Test-Path -LiteralPath $baseFile)) {
    throw "Base reference not found: $baseFile (unlink zone\common_mp.ff first)"
}

$baseText = Get-Content -LiteralPath $baseFile -Raw

if ($baseText.Contains("`r`n")) { $eol = "`r`n" } else { $eol = "`n" }

$anchor = "`tregisterDvars();$eol"
if (-not $baseText.Contains($anchor)) { throw 'anchor not found in base script' }

function New-ProbeMod {
    param(
        [string] $Name,
        [string] $Content,
        [string] $Description
    )

    $buildDir = Join-Path $root ('build\' + $Name)
    $scriptDir = Join-Path $buildDir 'maps\mp\gametypes'
    $scriptFile = Join-Path $scriptDir '_globallogic.gsc'

    if (-not (Test-Path -LiteralPath $scriptDir)) {
        New-Item -ItemType Directory -Force -Path $scriptDir | Out-Null
    }

    Set-Content -LiteralPath $scriptFile -Value $Content -NoNewline -Encoding ASCII

    $iwdName = 'z_' + $Name.Replace('-', '') + '.iwd'
    $iwdPath = Join-Path $buildDir $iwdName
    if (Test-Path -LiteralPath $iwdPath) { Remove-Item -LiteralPath $iwdPath -Force }

    $tarArgs = @('--format=zip', '-cf', $iwdPath, '-C', $buildDir, 'maps/mp/gametypes/_globallogic.gsc')
    & $tarExe $tarArgs
    if ($LASTEXITCODE -ne 0) { throw ("tar failed for " + $Name) }

    $modDir = Join-Path $Iw4xPath ('mods\ESL-PROBE-' + $Name.Substring($Name.Length - 1).ToUpper())
    if (-not (Test-Path -LiteralPath $modDir)) {
        New-Item -ItemType Directory -Force -Path $modDir | Out-Null
    }

    Copy-Item -LiteralPath $iwdPath -Destination (Join-Path $modDir $iwdName) -Force

    Write-Output ('probe   : ' + $Name)
    Write-Output ('  what  : ' + $Description)
    Write-Output ('  script: ' + $scriptFile + '  (' + $Content.Length + ' chars)')
    Write-Output ('  mod   : ' + $modDir + '\' + $iwdName)
}

# -----------------------------------------------------------------------------
#  PROBE A - untouched copy of the game's script
# -----------------------------------------------------------------------------
New-ProbeMod -Name 'probe-a' -Content $baseText `
    -Description 'byte-identical base script, no hook at all'

# -----------------------------------------------------------------------------
#  PROBE B - hook + synchronous, side-effect free init
# -----------------------------------------------------------------------------
$hookB = @(
    "`tregisterDvars();"
    ''
    "`t// ESL-PROBE-B hook"
    "`tesl_probe_init();"
) -join $eol
$hookB += $eol

$bodyB = @(
    ''
    ''
    'esl_probe_init()'
    '{'
    '	println( "^2[ESL-PROBE-B] init entered" );'
    '	level.eslProbeRan = true;'
    '	println( "^2[ESL-PROBE-B] init finished" );'
    '}'
) -join $eol

New-ProbeMod -Name 'probe-b' -Content ($baseText.Replace($anchor, $hookB) + $bodyB) `
    -Description 'hook calling a synchronously executed print-only function'

# -----------------------------------------------------------------------------
#  PROBE C - hook + threaded init
# -----------------------------------------------------------------------------
$hookC = @(
    "`tregisterDvars();"
    ''
    "`t// ESL-PROBE-C hook"
    "`tlevel thread esl_probe_init();"
) -join $eol
$hookC += $eol

$bodyC = @(
    ''
    ''
    'esl_probe_init()'
    '{'
    '	println( "^2[ESL-PROBE-C] thread started" );'
    '	level.eslProbeRan = true;'
    '	println( "^2[ESL-PROBE-C] thread finished" );'
    '}'
) -join $eol

New-ProbeMod -Name 'probe-c' -Content ($baseText.Replace($anchor, $hookC) + $bodyC) `
    -Description 'hook starting a thread (same shape as the real mod)'

# -----------------------------------------------------------------------------
#  PROBE D / F / G - the real ESL implementation
#
#    D  full ESL code, hook present, no .cfg files in the mod folder
#       -> if D hangs, the ESL code (not the configs) is at fault
#    F  full ESL code present but esl_init() is never called
#       -> separates "the code does not compile" from "the code hangs when run"
#          F hangs  => the file itself breaks loading/compilation
#          F loads  => the file compiles, the problem is what it does at runtime
#    G  full ESL code + the real .cfg files
#       -> if G loads while the installed ESL-MOD hangs, the .cfg files or the
#          mod folder itself are implicated
# -----------------------------------------------------------------------------
$eslFile = Join-Path $root 'src\maps\mp\gametypes\_esl.gsc'
$eslText = Get-Content -LiteralPath $eslFile -Raw

$kept = New-Object System.Collections.Generic.List[string]
foreach ($line in ($eslText -split "`r?`n")) {
    if ($line.TrimStart().StartsWith('#include')) {
        $kept.Add('// [probe] removed include (host file already includes it): ' + $line.Trim())
    } else {
        $kept.Add($line)
    }
}
$eslBody = ($kept -join $eol)
$banner  = ($eol + $eol + '// ===========================================================' + $eol +
            '//  ESL implementation (probe copy)' + $eol +
            '// ===========================================================' + $eol)

$hookD = @(
    "`tregisterDvars();"
    ''
    "`t// ESL-PROBE-D hook"
    "`tesl_init();"
) -join $eol
$hookD += $eol

New-ProbeMod -Name 'probe-d' -Content ($baseText.Replace($anchor, $hookD) + $banner + $eslBody) `
    -Description 'full ESL implementation + hook, no .cfg files (the real mod, minus configs)'

New-ProbeMod -Name 'probe-f' -Content ($baseText + $banner + $eslBody) `
    -Description 'full ESL implementation present but esl_init() never called (compilation test)'

New-ProbeMod -Name 'probe-g' -Content ($baseText.Replace($anchor, $hookD) + $banner + $eslBody) `
    -Description 'full ESL implementation + hook + the real .cfg files'

# G additionally gets the two config files, so it matches the installed mod
$cfgSource = Join-Path $root 'config'
$probeGDir = Join-Path $Iw4xPath 'mods\ESL-PROBE-G'
if (Test-Path -LiteralPath $probeGDir) {
    Copy-Item -Path (Join-Path $cfgSource '*.cfg') -Destination $probeGDir -Force
    Write-Output ('  cfgs  : copied ESL-MOD.cfg / ESL-MOD_sd.cfg into ' + $probeGDir)
}

# -----------------------------------------------------------------------------
#  PROBE H / I - the two native dvar writes in isolation
#
#    H  init() sets scr_game_hardpoints / scr_game_perks synchronously.
#       This is what the real mod does.  If H hangs, changing server dvars during
#       level initialisation is what breaks the client handshake.
#    I  the same writes, but from a thread that waits a second first.
#       If H hangs and I loads, the fix is simply to defer the dvar writes.
# -----------------------------------------------------------------------------
$hookH = @(
    "`tregisterDvars();"
    ''
    "`t// ESL-PROBE-H hook"
    "`tesl_probe_init();"
) -join $eol
$hookH += $eol

$bodyH = @(
    ''
    ''
    'esl_probe_init()'
    '{'
    '	println( "^2[ESL-PROBE-H] setting native dvars" );'
    '	setDvar( "scr_game_hardpoints", 0 );'
    '	level.killstreakRewards = 0;'
    '	setDvar( "scr_game_perks", 0 );'
    '	println( "^2[ESL-PROBE-H] done" );'
    '}'
) -join $eol

New-ProbeMod -Name 'probe-h' -Content ($baseText.Replace($anchor, $hookH) + $bodyH) `
    -Description 'only the two native dvar writes, synchronously in init()'

$hookI = @(
    "`tregisterDvars();"
    ''
    "`t// ESL-PROBE-I hook"
    "`tlevel thread esl_probe_init();"
) -join $eol
$hookI += $eol

$bodyI = @(
    ''
    ''
    'esl_probe_init()'
    '{'
    '	wait 1.0;'
    '	println( "^2[ESL-PROBE-I] setting native dvars (deferred)" );'
    '	setDvar( "scr_game_hardpoints", 0 );'
    '	level.killstreakRewards = 0;'
    '	setDvar( "scr_game_perks", 0 );'
    '	println( "^2[ESL-PROBE-I] done" );'
    '}'
) -join $eol

New-ProbeMod -Name 'probe-i' -Content ($baseText.Replace($anchor, $hookI) + $bodyI) `
    -Description 'the same two dvar writes, deferred into a thread'

# -----------------------------------------------------------------------------
#  PROBE J - full ESL logic, but no playerdata writes
#
#  Everything runs exactly as in the real mod (connect handler, spawn handler,
#  watchdog, class sanitiser, all the getPlayerData() reads) - the only thing
#  removed is the setPlayerData() write, which is replaced by a no-op with seven
#  declared parameters so every call site stays syntactically identical.
#
#    J loads      -> the playerdata writes are what stall the level load, and the
#                    fix is to defer/throttle them (write only well after the
#                    level has started, or only on spawn).
#    J hangs      -> the writes are not the problem; the fault is in the code
#                    itself and PROBE-F tells us whether it even compiles.
# -----------------------------------------------------------------------------
$noWriteBody = $eslBody.Replace('self setPlayerData(', 'self esl_probeDiscardWrite(')

$discard = @(
    ''
    ''
    'esl_probeDiscardWrite( a1, a2, a3, a4, a5, a6, a7 )'
    '{'
    '	// PROBE-J: playerdata writes intentionally disabled'
    '}'
) -join $eol

New-ProbeMod -Name 'probe-j' -Content ($baseText.Replace($anchor, $hookD) + $banner + $noWriteBody + $discard) `
    -Description 'full ESL logic running, but every playerdata write disabled'

Write-Output ''
Write-Output 'Round 1 (done): ESL-PROBE-A, B, C - all load, so the override + hook + thread work.'
Write-Output 'Round 2: test ESL-PROBE-D, then F, then G.'
Write-Output '  D hangs, F loads  -> the ESL code compiles, but hangs while running.'
Write-Output '  D hangs, F hangs  -> the ESL code breaks loading/compilation.'
Write-Output '  D loads, G hangs  -> the .cfg files are the problem.'

# =============================================================================
#  ROUND 3 - PROBE K / L / M / N
#
#  Findings so far: the override + hook + thread work (A/B/C), the two native
#  dvar writes are fine (H), the ESL code compiles (F), and the hang persists
#  with all playerdata writes disabled (J).  So the hang comes from one of the
#  things that keep running.
#
#    K  only esl_registerDvars()  (40x setDvarIfUninitialized, incl. an
#       empty-string value for esl_weapon_denylist)
#    L  the same without the empty-string esl_weapon_denylist default
#    M  only the death streak guard (writes self.pers["cur_death_streak"])
#    N  only the class sanitiser with all writes disabled (reads only)
# =============================================================================

function Extract-Func {
    param([string] $Text, [string] $Name)
    # parameter-agnostic: matches "name()" as well as "name( a, b, c )"
    $pattern = '(?ms)^' + [regex]::Escape($Name) + '\s*\([^\r\n]*\)\s*\r?\n\{.*?^\}'
    $m = [regex]::Match($Text, $pattern)
    if (-not $m.Success) { throw ("could not extract function " + $Name) }
    return $m.Value
}

$fnRegister  = Extract-Func $eslBody 'esl_registerDvars'
$fnGuard     = Extract-Func $eslBody 'esl_deathstreakGuard'
$fnSanitize  = Extract-Func $eslBody 'esl_sanitizeStoredClasses'
$fnAccessors = @('esl_getStoredAttachment', 'esl_setStoredWeapon', 'esl_setStoredAttachment',
                 'esl_setStoredPerk', 'esl_setStoredOffhand') |
               ForEach-Object { Extract-Func $eslBody $_ }
$fnLookups   = @('esl_attachmentAllowed', 'esl_equipmentAllowed', 'esl_offhandAllowed',
                 'esl_weaponBanned', 'esl_defaultEquipment', 'esl_defaultOffhand') |
               ForEach-Object { Extract-Func $eslBody $_ }

# the sanitiser must not write while we are only testing whether it runs
$fnSanitize = $fnSanitize.Replace('self setPlayerData(', 'self esl_probeDiscardWrite(')

$discardFn = @(
    'esl_probeDiscardWrite( a1, a2, a3, a4, a5, a6, a7 )'
    '{'
    '	// PROBE: playerdata writes disabled'
    '}'
) -join $eol

$hookK = @(
    "`tregisterDvars();"
    ''
    "`t// ESL-PROBE-K hook"
    "`tesl_probe_init();"
) -join $eol
$hookK += $eol

$initK = @(
    'esl_probe_init()'
    '{'
    '	println( "^2[ESL-PROBE-K] registering dvars" );'
    '	esl_registerDvars();'
    '	println( "^2[ESL-PROBE-K] done" );'
    '}'
) -join $eol

New-ProbeMod -Name 'probe-k' -Content ($baseText.Replace($anchor, $hookK) + $eol + $eol + $fnRegister + $eol + $eol + $initK) `
    -Description 'only esl_registerDvars() (all 40 setDvarIfUninitialized calls)'

# L: same but the empty-string default for esl_weapon_denylist is dropped
$fnRegisterNoEmpty = (($fnRegister -split "`r?`n") | Where-Object { $_ -notmatch 'esl_weapon_denylist' }) -join $eol

New-ProbeMod -Name 'probe-l' -Content ($baseText.Replace($anchor, $hookK) + $eol + $eol + $fnRegisterNoEmpty + $eol + $eol + $initK) `
    -Description 'esl_registerDvars() without the empty-string esl_weapon_denylist default'

# M: only the death streak guard
$hookM = @(
    "`tregisterDvars();"
    ''
    "`t// ESL-PROBE-M hook"
    "`tlevel thread esl_probe_init();"
) -join $eol
$hookM += $eol

$initM = @(
    'esl_probe_init()'
    '{'
    '	println( "^2[ESL-PROBE-M] watching connects" );'
    '	for ( ;; )'
    '	{'
    '		level waittill( "connected", player );'
    '		player thread esl_deathstreakGuard();'
    '	}'
    '}'
) -join $eol

New-ProbeMod -Name 'probe-m' -Content ($baseText.Replace($anchor, $hookM) + $eol + $eol + $fnGuard + $eol + $eol + $initM) `
    -Description 'only the death streak guard loop (self.pers writes)'

# N: only the sanitiser, reads only
$initN = @(
    'esl_probe_init()'
    '{'
    '	println( "^2[ESL-PROBE-N] watching connects" );'
    '	for ( ;; )'
    '	{'
    '		level waittill( "connected", player );'
    '		player thread esl_sanitizeStoredClasses();'
    '	}'
    '}'
) -join $eol

$bodyN = ($eol + $fnSanitize + $eol + $eol + ($fnAccessors -join ($eol + $eol)) + $eol + $eol +
          ($fnLookups -join ($eol + $eol)) + $eol + $eol + $discardFn + $eol + $eol + $initN)

New-ProbeMod -Name 'probe-n' -Content ($baseText.Replace($anchor, $hookM) + $bodyN) `
    -Description 'only the class sanitiser, all playerdata writes disabled (reads only)'

Write-Output ''
Write-Output 'Round 3: test ESL-PROBE-K, L, M, N - report which of them hang.'

# =============================================================================
#  ROUND 4 - PROBE O / P
#
#  Round 3 results: K (registerDvars) loads, L loads, N (sanitiser, reads only)
#  loads.  PROBE-M failed to compile - that was a bug in the probe itself (its
#  guard calls esl_enabled(), which was not included), and importantly it proved
#  the engine *shows* compile errors, so the real mod's silent hang is not a
#  compile error.
#
#  That leaves exactly two pieces of the real mod that have never run on their
#  own:
#
#    O  the death streak guard - a loop that writes
#       self.pers["cur_death_streak"] every 0.25s for every player
#    P  the watchdog - re-applies the native dvars and re-checks every player
#       every esl_sanitize_interval seconds, forever
# =============================================================================
$fnEnabled    = Extract-Func $eslBody 'esl_enabled'
$fnApply      = Extract-Func $eslBody 'esl_applyNativeDvars'
$fnWatchdog   = Extract-Func $eslBody 'esl_watchdog'

# --- PROBE O : the guard, with esl_enabled() this time ------------------------
$initO = @(
    'esl_probe_init()'
    '{'
    '	println( "^2[ESL-PROBE-O] watching connects" );'
    '	for ( ;; )'
    '	{'
    '		level waittill( "connected", player );'
    '		player thread esl_deathstreakGuard();'
    '	}'
    '}'
) -join $eol

New-ProbeMod -Name 'probe-o' -Content ($baseText.Replace($anchor, $hookM) + $eol + $eol +
    $fnEnabled + $eol + $eol + $fnGuard + $eol + $eol + $initO) `
    -Description 'only the death streak guard loop (self.pers writes), esl_enabled() included'

# --- PROBE P : the watchdog ---------------------------------------------------
$initP = @(
    'esl_probe_init()'
    '{'
    '	println( "^2[ESL-PROBE-P] starting watchdog" );'
    '	level thread esl_watchdog();'
    '}'
) -join $eol

$bodyP = ($eol + $fnEnabled + $eol + $eol + $fnApply + $eol + $eol + $fnWatchdog + $eol + $eol +
          $fnSanitize + $eol + $eol + ($fnAccessors -join ($eol + $eol)) + $eol + $eol +
          ($fnLookups -join ($eol + $eol)) + $eol + $eol + $discardFn + $eol + $eol + $initP)

New-ProbeMod -Name 'probe-p' -Content ($baseText.Replace($anchor, $hookM) + $bodyP) `
    -Description 'only the watchdog loop (re-applies dvars, re-checks players forever)'

Write-Output ''
Write-Output 'Round 4: test ESL-PROBE-O and ESL-PROBE-P - report which hang.'
