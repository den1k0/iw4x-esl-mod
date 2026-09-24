# =============================================================================
#  ESL-MOD development helper - payload generator
#
#  Produces the game scripts the mod overrides:
#
#      build\payload\maps\mp\gametypes\_globallogic.gsc
#          the game's own script, plus one inserted hook call (esl_init();) and
#          the whole of src\maps\mp\gametypes\_esl.gsc appended to it with its
#          #include lines removed.
#
#      build\payload\maps\mp\gametypes\_menus.gsc
#          the game's own script-menu dispatcher, with
#            * game["menu_changeclass*"] pointing at the ESL class menus, and
#            * every response produced by those menus routed to
#              _globallogic::esl_handleCacResponse() instead of the stock chain.
#
#      build\payload\maps\mp\gametypes\_class.gsc
#          the game's own class code, with the ESL class loadouts kept out of the
#          playerdata (see section 3 below).
#
#      build\payload\maps\mp\gametypes\_gamelogic.gsc
#          the game's own end-of-match sequence, with the fixed postgame wait
#          replaced by the end-of-match map vote (see section 3e below).  The
#          engine's own exitLevel() call after it is left alone, so the rotation
#          is still the engine's.
#
#  Why patch scripts the engine already loads instead of shipping new ones?
#      The engine resolves "namespace::func" by loading that script *file*.  A
#      brand new file is therefore a risk: if it cannot be resolved, level
#      initialisation fails and the client hangs on "waiting for response".
#      Both files patched here are scripts the engine loads anyway.
#
#  Why is all the ESL code in one file instead of a second script?
#      Same reason - everything ESL lives in _globallogic.gsc, which every
#      gametype loads through _globallogic::init(), so every esl_* call
#      resolves inside one compile unit.
#
#  The #include lines of _esl.gsc are dropped because _globallogic.gsc already
#  includes common_scripts\utility, maps\mp\_utility and _hud_util; including
#  them a second time would duplicate function definitions.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\build_payload.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$root       = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$baseDir    = Join-Path $root '.tmp_reference\base\maps\mp\gametypes'
$eslFile    = Join-Path $root 'src\maps\mp\gametypes\_esl.gsc'
$payloadDir = Join-Path $root 'build\payload\maps\mp\gametypes'
$globFile   = Join-Path $payloadDir '_globallogic.gsc'
$menusFile  = Join-Path $payloadDir '_menus.gsc'

$baseGlob   = Join-Path $baseDir '_globallogic.gsc'
$baseMenus  = Join-Path $baseDir '_menus.gsc'

foreach ($f in @($baseGlob, $baseMenus, $eslFile)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "Missing input: $f" }
}

if (-not (Test-Path -LiteralPath $payloadDir)) {
    New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null
}

$failures = @()

# Write-Ascii keeps the output as plain ASCII with no BOM and no trailing
# newline handling of its own - the GSC compiler is picky about both.
function Write-Ascii([string] $path, [string] $text) {
    Set-Content -LiteralPath $path -Value $text -NoNewline -Encoding ASCII
}

# -----------------------------------------------------------------------------
#  1. _globallogic.gsc : base script + the esl_init() hook + the ESL code
# -----------------------------------------------------------------------------

$baseText = Get-Content -LiteralPath $baseGlob -Raw
$eslText  = Get-Content -LiteralPath $eslFile  -Raw

# line ending of the base script decides the line ending of the output
if ($baseText.Contains("`r`n")) { $eol = "`r`n" } else { $eol = "`n" }

# --- 1a. drop the #include lines from the ESL source --------------------------
$kept = New-Object System.Collections.Generic.List[string]
foreach ($line in ($eslText -split "`r?`n")) {
    if ($line.TrimStart().StartsWith('#include')) {
        $kept.Add('// [build] removed include (already provided by _globallogic.gsc): ' + $line.Trim())
    } else {
        $kept.Add($line)
    }
}
$eslBody = ($kept -join $eol)

# --- 1b. insert the hook into init() ------------------------------------------
# Every gametype calls _globallogic::init() from its main(), which makes this
# the one place guaranteed to run exactly once per game mode.  The hook is
# deliberately the only code ESL runs synchronously: everything else is started
# as a thread, because writing player state while the level loads faults the
# engine (see docs/DIAGNOSTICS.md).
$anchor = "`tregisterDvars();$eol"

if (-not $baseText.Contains($anchor)) {
    throw 'Anchor "`tregisterDvars();" not found - unexpected base script'
}

$hookBlock = @(
    "`tregisterDvars();"
    ''
    "`t// ---------------------------------------------------------------"
    "`t// ESL-MOD hook.  Every gametype calls _globallogic::init() from its"
    "`t// main() function, which makes this the one place that is guaranteed"
    "`t// to run exactly once for every game mode."
    "`t// ---------------------------------------------------------------"
    "`tesl_init();"
) -join $eol
$hookBlock += $eol

# NOTE: do not call this $host - PowerShell's $Host is read-only.
$hostText = $baseText.Replace($anchor, $hookBlock)

# --- 1c. append the ESL implementation ---------------------------------------
$banner = @(
    ''
    ''
    '// ==========================================================================='
    '//  ESL-MOD implementation (generated - edit src\maps\mp\gametypes\_esl.gsc and'
    '//  re-run tools\dev\build_payload.ps1, never edit this part by hand).'
    '// ==========================================================================='
    ''
) -join $eol

$globOut = $hostText + $banner + $eslBody

# --- 1d. verify ---------------------------------------------------------------
$anchorPos = $baseText.IndexOf($anchor)

if ($anchorPos -lt 0) {
    $failures += 'anchor not found in base text'
} else {
    if (-not $globOut.StartsWith($baseText.Substring(0, $anchorPos))) {
        $failures += 'payload does not start with the base script head'
    }
    # everything after the anchor line must still be present verbatim
    $tail = $baseText.Substring($anchorPos + $anchor.Length)
    if (-not $globOut.Contains($tail)) {
        $failures += 'payload is missing the base script tail'
    }
}

if (-not $globOut.Contains("`tesl_init();")) {
    $failures += 'payload does not contain the esl_init() hook'
}

if ($globOut -notmatch 'esl_sanitizeStoredClasses') {
    $failures += 'payload does not contain the ESL implementation'
}

if ($globOut -match 'maps\\mp\\gametypes\\_esl::') {
    $failures += 'payload references the maps\mp\gametypes\_esl namespace - the ESL code must stay inline'
}

if ($globOut -match 'self\s+::esl_') {
    $failures += 'payload calls a "::name" function reference as a method (bad syntax)'
}

$defCount = ([regex]::Matches($globOut, '(?m)^esl_init\(')).Count
if ($defCount -ne 1) {
    $failures += ('esl_init() definitions: expected 1, found ' + $defCount)
}

# the base file's own #includes plus the ones we removed must not be duplicated
$baseIncludeCount = ([regex]::Matches($baseText, '(?m)^#include')).Count
$globIncludeCount = ([regex]::Matches($globOut,  '(?m)^#include')).Count
if ($globIncludeCount -ne $baseIncludeCount) {
    $failures += ("#include count changed: base $baseIncludeCount, output $globIncludeCount")
}

Write-Ascii $globFile $globOut

# -----------------------------------------------------------------------------
#  2. _menus.gsc : base script + the create-a-class redirect and dispatch
# -----------------------------------------------------------------------------

$menuBase = Get-Content -LiteralPath $baseMenus -Raw

# --- 2a. point the class menus at the ESL ones -------------------------------
# These are the three assignments in _menus::init().  Without this, the stock
# "Choose Class" button (and beginClassChoice(), which the game calls whenever a
# player has to pick a class) opens the stock five-custom-class menu.  Note the
# lines are inside "if ( !isDefined( game["gamestarted"] ) )", i.e. they run
# once per match, after our _globallogic::init() hook - which is exactly why the
# redirect cannot be done from the hook.
$menuRedirects = [ordered]@{
    'game["menu_changeclass_allies"] = "changeclass_marines";' = 'game["menu_changeclass_allies"] = "changeclass_marines_mw";'
    'game["menu_changeclass_axis"] = "changeclass_opfor";'     = 'game["menu_changeclass_axis"] = "changeclass_opfor_mw";'
    'game["menu_changeclass"] = "changeclass";'                = 'game["menu_changeclass"] = "changeclass_mw";'
}

$menuOut = $menuBase

foreach ($from in $menuRedirects.Keys) {
    $count = ([regex]::Matches($menuOut, [regex]::Escape($from))).Count
    if ($count -ne 1) {
        $failures += ("expected exactly one occurrence of: $from (found $count)")
        continue
    }
    $menuOut = $menuOut.Replace($from, $menuRedirects[$from])
}

# --- 2b. route the ESL menus' responses to the ESL handler -------------------
# onMenuResponse() dispatches by menu *name*, so the two class-list menus and
# the editor are simply claimed before the stock chain runs.  This mirrors what
# ProMod does in its own _menus.gsc.
$waitLine = 'self waittill("menuresponse", menu, response);'

$waitCount = ([regex]::Matches($menuOut, [regex]::Escape($waitLine))).Count
if ($waitCount -ne 1) {
    $failures += ("expected exactly one menuresponse waittill (found $waitCount)")
} else {
    $dispatch = @(
        $waitLine
        ''
        '		// --- ESL-MOD: in-game create-a-class ---------------------------------'
        '		// Weapon, attachment, camo and grenade picks are made in the editor''s'
        '		// *popup* menus, which have their own menu names - so they are matched'
        '		// on the response text alone ("loadout_primary:ak47", ...), the same'
        '		// way ProMod does it.  Only distinguishing on the menu name here would'
        '		// drop every item the player picks.'
        '		if ( isDefined( response ) && isSubStr( response, "loadout" ) )'
        '		{'
        '			self maps\mp\gametypes\_globallogic::esl_processLoadoutResponse( response );'
        '			continue;'
        '		}'
        ''
        '		// The class list greys every entry out until the availability dvars'
        '		// are set, so push them before the stock chain opens the menu.'
        '		if ( response == "changeclass_marines" || response == "changeclass_opfor" )'
        '			self maps\mp\gametypes\_globallogic::esl_prepareClassMenu();'
        ''
        '		// Responses produced by the three ESL menus are handled in'
        '		// _globallogic.gsc, so the stock chain below never sees them.'
        '		if ( menu == "changeclass_marines_mw" || menu == "changeclass_opfor_mw" || menu == "changeclass_mw" )'
        '		{'
        '			self maps\mp\gametypes\_globallogic::esl_handleCacResponse( menu, response );'
        '			continue;'
        '		}'
        '		// ---------------------------------------------------------------------'
    ) -join $eol

    $menuOut = $menuOut.Replace($waitLine, $dispatch)
}

# --- 2c. refresh the availability before the automatic class choice -----------
# beginClassChoice() is what the game calls whenever a player has to pick a class
# after joining or switching sides - the path that opens the class list without
# any button press.  Same reason as above: the entries are greyed out until the
# allies_allow_*/axis_allow_* dvars exist.
# NOTE: the whole line is matched, leading tab included.  Matching only the
# "openpopupMenu( ... )" part would leave the "self " receiver of the original
# line in front of the inserted comment ("self // ESL-MOD: ..."), which is a
# syntax error.
$openClassLine = "`t" + 'self openpopupMenu( game[ "menu_changeclass_" + team ] );'

$openCount = ([regex]::Matches($menuOut, [regex]::Escape($openClassLine))).Count
if ($openCount -ne 1) {
    $failures += ("expected exactly one class-list open call in beginClassChoice (found $openCount)")
} else {
    $patched = @(
        '	// ESL-MOD: set the availability dvars before the class list is drawn'
        '	self maps\mp\gametypes\_globallogic::esl_prepareClassMenu();'
        ''
        $openClassLine
    ) -join $eol

    $menuOut = $menuOut.Replace($openClassLine, $patched)
}

if ($menuOut -notmatch 'esl_handleCacResponse') {
    $failures += '_menus.gsc does not route the ESL menus to esl_handleCacResponse()'
}

if ($menuOut -notmatch 'esl_prepareClassMenu') {
    $failures += '_menus.gsc does not refresh the class availability before opening the class list'
}

# item picks come from the editor's popup menus, so they must be dispatched on
# the response text and not on the menu name
if ($menuOut -notmatch 'esl_processLoadoutResponse') {
    $failures += '_menus.gsc does not route the item picks to esl_processLoadoutResponse()'
}

# guard against a substring substitution that swallowed the receiver of a method
# call and left something like "self // comment" behind
if ($menuOut -match 'self\s+//') {
    $failures += '_menus.gsc contains "self //..." - a substitution ate a method receiver'
}

# the original class-list open call must still be there, intact
if ($menuOut -notmatch [regex]::Escape($openClassLine)) {
    $failures += '_menus.gsc lost the original class-list open call in beginClassChoice'
}

if ($menuOut -match '"menu_changeclass_allies"\] = "changeclass_marines";') {
    $failures += '_menus.gsc still points menu_changeclass_allies at the stock menu'
}

$menuIncludeCount = ([regex]::Matches($menuOut, '(?m)^#include')).Count
$menuBaseInclude  = ([regex]::Matches($menuBase, '(?m)^#include')).Count
if ($menuIncludeCount -ne $menuBaseInclude) {
    $failures += ("_menus.gsc #include count changed: base $menuBaseInclude, output $menuIncludeCount")
}

Write-Ascii $menusFile $menuOut

# -----------------------------------------------------------------------------
#  3. _class.gsc : base script + the ESL class accessors
#
#  The ESL class types must not be influenced by the main-menu create-a-class.
#  They are kept in script data (self.eslClasses, see _esl.gsc) instead of the
#  playerdata the vanilla classes use, and this is the whole patch needed:
#
#      * _class::giveLoadout() picks its custom-class branch with
#        isSubstr( class, "custom" ), which is why the ESL class names are
#        "custom_esl_assault" and friends; and
#      * for that branch the only playerdata reads are the seven cac_get*()
#        one-liners below, so redirecting those to the ESL storage takes the ESL
#        classes out of the playerdata completely.
#
#  The accessors are keyed on the class *index*, and the ESL types use 15/16/17
#  (0-14 belong to the vanilla classes), so the vanilla path is untouched.
# -----------------------------------------------------------------------------
$baseClass = Join-Path $baseDir '_class.gsc'
$classFile = Join-Path $payloadDir '_class.gsc'

if (-not (Test-Path -LiteralPath $baseClass)) { throw "Missing input: $baseClass" }

$classBase = Get-Content -LiteralPath $baseClass -Raw
if ($classBase.Contains("`r`n")) { $classEol = "`r`n" } else { $classEol = "`n" }

$classOut = $classBase

$cacRedirects = [ordered]@{
    'cac_getWeapon'              = 'esl_cacWeapon( classIndex, weaponIndex )'
    'cac_getWeaponAttachment'    = 'esl_cacAttachment( classIndex, weaponIndex, 0 )'
    'cac_getWeaponAttachmentTwo' = 'esl_cacAttachment( classIndex, weaponIndex, 1 )'
    'cac_getWeaponCamo'          = 'esl_cacCamo( classIndex, weaponIndex )'
    'cac_getPerk'                = 'esl_cacPerk( classIndex, perkIndex )'
    'cac_getDeathstreak'         = 'esl_cacDeathstreak( classIndex )'
    'cac_getOffhand'             = 'esl_cacOffhand( classIndex )'
}

foreach ($fn in $cacRedirects.Keys) {
    # matches "name( args )" plus its opening brace, in either line ending;
    # $1 puts the original text back in front of the inserted guard
    $pattern = '(?m)^(' + [regex]::Escape($fn) + '\([^\)]*\)\s*\r?\n\{\s*\r?\n)'

    $hits = ([regex]::Matches($classOut, $pattern)).Count
    if ($hits -ne 1) {
        $failures += ("expected exactly one $fn definition (found $hits)")
        continue
    }

    $guard = '	if ( maps\mp\gametypes\_globallogic::esl_isCacClass( classIndex ) )' + $classEol +
             '		return self maps\mp\gametypes\_globallogic::' + $cacRedirects[$fn] + ';' + $classEol + $classEol

    $classOut = [regex]::Replace($classOut, $pattern, ('$1' + $guard))
}

$guardCount = ([regex]::Matches($classOut, 'esl_isCacClass')).Count
if ($guardCount -ne $cacRedirects.Count) {
    $failures += ("_class.gsc ESL guards: expected $($cacRedirects.Count), found $guardCount")
}

# -----------------------------------------------------------------------------
#  3b. _class.gsc - the two gates giveLoadout() runs before it hands anything to
#      _giveWeapon(), both of which replace what they do not like with table
#      row 10 - the stock default class, an M4 and a USP.
#
#  * the weapon whitelists are older than this build: isValidPrimary() has no
#    ak74u and no m40a3, isValidSecondary() no deserteaglegold, while the newer
#    copy of the same file (zombies) lists all three and the game's own zone
#    source ships "weapon,deserteaglegold_mp".  Picking the gold Deagle gave the
#    default pistol, which is what "gold Deagle + FMJ gives me a USP" was.
#
#  * every "isCustomClass && !self isItemUnlocked(...)" clause is skipped for the
#    ESL classes.  The ESL loadout belongs to the mod, not to the player's unlock
#    progress, and consulting it swapped any weapon or attachment the profile
#    has not unlocked for the default one - which is what "my class resets to an
#    M4" actually was.
# -----------------------------------------------------------------------------

$classRefAdds = [ordered]@{
    'isValidPrimary'   = @('ak74u', 'm40a3')
    'isValidSecondary' = @('deserteaglegold')
}

foreach ($fn in $classRefAdds.Keys) {
    # anchor on the switch inside the function, so the new cases land in the list
    $pattern = '(?m)(' + [regex]::Escape($fn) + '\( refString \)\s*\r?\n\{\s*\r?\n\tswitch \( refString \)\s*\r?\n\t\{)'

    $hits = ([regex]::Matches($classOut, $pattern)).Count
    if ($hits -ne 1) {
        $failures += ("expected exactly one $fn switch (found $hits)")
        continue
    }

    $cases = ''
    foreach ($ref in $classRefAdds[$fn]) {
        $cases += $classEol + "`t`tcase `"$ref`":"

        if (([regex]::Matches($classOut, 'case "' + [regex]::Escape($ref) + '":')).Count -ne 0) {
            $failures += ("$fn already lists $ref")
        }
    }

    $classOut = [regex]::Replace($classOut, $pattern, ('$1' + $cases))
}

foreach ($ref in @('ak74u', 'm40a3', 'deserteaglegold')) {
    if (([regex]::Matches($classOut, 'case "' + [regex]::Escape($ref) + '":')).Count -ne 1) {
        $failures += ("_class.gsc does not list $ref exactly once")
    }
}

$unlockNeedle = '(isCustomClass && !self isItemUnlocked('
$unlockHits   = ([regex]::Matches($classOut, [regex]::Escape($unlockNeedle))).Count

if ($unlockHits -ne 13) {
    $failures += ("_class.gsc unlock clauses: expected 13, found $unlockHits")
}

# self.class_num, not the local class_num: the copycat branch only ever writes
# the field, so a read of the local in this block is "uninitialised variable
# 'class_num'" at compile time - which is how the first version of this patch
# broke the whole mod's load.
$classOut = $classOut.Replace($unlockNeedle,
    '(isCustomClass && !maps\mp\gametypes\_globallogic::esl_isCacClass( self.class_num ) && !self isItemUnlocked(')

$unlockPatched = ([regex]::Matches($classOut, 'esl_isCacClass\( self\.class_num \)')).Count
if ($unlockPatched -ne $unlockHits) {
    $failures += ("_class.gsc ESL unlock bypasses: expected $unlockHits, found $unlockPatched")
}

# -----------------------------------------------------------------------------
#  3c. _class.gsc - the ESL class memory wins over the class handed in
#
#  giveLoadout( team, class, allowCopycat ) is called with whatever the engine
#  believes the current class is, and after a round transition that can be a
#  reset or stale value: the player then spawns on a stock loadout even though
#  the ESL memory is intact.  Asking the memory first makes every spawn build the
#  class the player actually chose, whatever the engine thinks.
# -----------------------------------------------------------------------------
$givePattern = '(?m)^(giveLoadout\( team, class, allowCopycat \)\s*\r?\n\{\s*\r?\n)'

$giveHits = ([regex]::Matches($classOut, $givePattern)).Count
if ($giveHits -ne 1) {
    $failures += ("expected exactly one giveLoadout() definition (found $giveHits)")
}
else {
    $prologue = $classEol +
        '	// ESL-MOD: the class memory on the player wins over the class handed in, so' + $classEol +
        '	// a class the engine reset between rounds cannot produce a stock loadout.' + $classEol +
        '	eslMemoryClass = maps\mp\gametypes\_globallogic::esl_memoryClassName( self );' + $classEol +
        $classEol +
        '	if ( eslMemoryClass != "" )' + $classEol +
        '		class = eslMemoryClass;' + $classEol +
        $classEol

    $classOut = [regex]::Replace($classOut, $givePattern, ('$1' + $prologue))
}

$memoryHits = ([regex]::Matches($classOut, 'esl_memoryClassName')).Count
if ($memoryHits -ne 1) {
    $failures += ("_class.gsc ESL class memory check: expected 1, found $memoryHits")
}

# -----------------------------------------------------------------------------
#  3d. _class.gsc - resolve an ESL class name without level.classMap
#
#  getClassIndex() reads level.classMap, which is a stock level variable the
#  engine rebuilds: the stock entries come back and ours do not.  giveLoadout()
#  then falls into its class-table branch while the class name still looks right,
#  and the player gets the class table's default class - an M4 and a USP after a
#  round transition, with a healthy heartbeat and no error anywhere.
# -----------------------------------------------------------------------------
$indexPattern = '(?m)^(getClassIndex\( className \)\s*\r?\n\{\s*\r?\n)'

$indexHits = ([regex]::Matches($classOut, $indexPattern)).Count
if ($indexHits -ne 1) {
    $failures += ("expected exactly one getClassIndex() definition (found $indexHits)")
}
else {
    $indexPrologue = $classEol +
        '	// ESL-MOD: the ESL classes are resolved here, not through level.classMap,' + $classEol +
        '	// which the engine rebuilds without them.' + $classEol +
        '	eslIndex = maps\mp\gametypes\_globallogic::esl_indexForClassName( className );' + $classEol +
        $classEol +
        '	if ( eslIndex >= 0 )' + $classEol +
        '		return eslIndex;' + $classEol +
        $classEol

    $classOut = [regex]::Replace($classOut, $indexPattern, ('$1' + $indexPrologue))
}

$indexGuard = ([regex]::Matches($classOut, 'esl_indexForClassName')).Count
if ($indexGuard -ne 1) {
    $failures += ("_class.gsc ESL class index check: expected 1, found $indexGuard")
}

$classIncludeBase = ([regex]::Matches($classBase, '(?m)^#include')).Count
$classIncludeOut  = ([regex]::Matches($classOut,  '(?m)^#include')).Count
if ($classIncludeOut -ne $classIncludeBase) {
    $failures += ("_class.gsc #include count changed: base $classIncludeBase, output $classIncludeOut")
}

Write-Ascii $classFile $classOut

# -----------------------------------------------------------------------------
#  3e. _gamelogic.gsc : the end-of-match map vote owns the postgame
#
#  endGame() is the game's own end-of-match sequence: it shows the scoreboard,
#  puts the players into intermission and then, after a fixed wait of 3 or 6
#  seconds, calls exitLevel( false ) - which is the call that makes the engine
#  rotate to the next map.  That wait is the only time a vote could live, and it
#  is far too short for one.  It is also the reason the vote used to be cut off
#  ("the screen showed up and the map changed five seconds later") and, once the
#  rotation was held instead, the reason the whole server shut down:
#
#      "Not performing map rotation as sv_dontRotate is true"
#      ----- Server Shutdown -----
#
#  The patch replaces exactly that wait with one call into the ESL code, so the
#  vote runs where the wait was and everything around it is untouched: the map
#  rotation is still the engine's own exitLevel() call, and the vote only decides
#  what sv_mapRotation holds when it happens.  Nothing sets sv_dontrotate and
#  nothing ends the level from script.
#
#  The same file gets a one-line marker at the top of Callback_StartGameType(),
#  which code calls once per level (see _callbacksetup.gsc): it tells _esl.gsc
#  that this override is the one that loaded, so a fork that did not take effect
#  is visible in the server log at boot instead of only at the end of a match.
# -----------------------------------------------------------------------------
$baseGame = Join-Path $baseDir '_gamelogic.gsc'
$gameFile = Join-Path $payloadDir '_gamelogic.gsc'

if (-not (Test-Path -LiteralPath $baseGame)) { throw "Missing input: $baseGame" }

$gameBase = Get-Content -LiteralPath $baseGame -Raw
if ($gameBase.Contains("`r`n")) { $gameEol = "`r`n" } else { $gameEol = "`n" }

$gameOut = $gameBase

# --- 3e-1. the load marker ----------------------------------------------------
$startPattern = '(?m)^(Callback_StartGameType\(\)\s*\r?\n\{\s*\r?\n\s*maps\\mp\\_load::main\(\);\s*\r?\n)'

$startHits = ([regex]::Matches($gameOut, $startPattern)).Count
if ($startHits -ne 1) {
    $failures += ("expected exactly one Callback_StartGameType() opening in _gamelogic.gsc (found $startHits)")
}
else {
    $marker = $gameEol +
        '	// ESL-MOD: tells _esl.gsc that this patched file is the one that loaded;' + $gameEol +
        '	// without that line the map vote says so in the log instead of silently' + $gameEol +
        '	// never running.' + $gameEol +
        '	maps\mp\gametypes\_globallogic::esl_gameLogicLoaded();' + $gameEol

    $gameOut = [regex]::Replace($gameOut, $startPattern, ('$1' + $marker))
}

# --- 3e-2. the postgame wait becomes the vote ---------------------------------
# Everything from the "game ended" comment down to (but not including) the
# exitLevel_called notify is the wait the vote replaces.  That point in endGame() is
# the one a map vote belongs at: after the killcam and after the victory/defeat
# screen, and before the engine rotates the map.  Running the vote earlier - which
# is what a first attempt at this did - cuts both of those off entirely.
#
# The notify itself is kept: the lookahead does not consume it, so the line keeps its
# own indentation and everything that waits for "exitLevel_called" still sees it.
$waitPattern = '(?s)\t//logString\( "game ended" \);\r?\n' +
               '\tif\( !nukeDetonated && !level\.postGameNotifies \).*?' +
               '[ \t]*\r?\n(?=\t?level notify\( "exitLevel_called" \);)'

$waitHits = ([regex]::Matches($gameOut, $waitPattern)).Count
if ($waitHits -ne 1) {
    $failures += ("the endGame() postgame wait was not found exactly once in _gamelogic.gsc (found $waitHits)")
}
else {
    $voteBlock =
        '	// ESL-MOD: the end-of-match map vote takes the place of the fixed' + $gameEol +
        '	// postgame wait that used to sit here (6 s, or 3 s on a one-round' + $gameEol +
        '	// match) - i.e. after the killcam and the victory/defeat screen, and' + $gameEol +
        '	// before the rotation.  It returns when its window is over; the lines' + $gameEol +
        '	// below are unchanged, so the engine still rotates the map itself - to' + $gameEol +
        '	// whichever map the vote put into sv_mapRotation.' + $gameEol +
        '	maps\mp\gametypes\_globallogic::esl_mapVoteEndgame();' + $gameEol +
        $gameEol

    $gameOut = [regex]::Replace($gameOut, $waitPattern, $voteBlock)
}

# --- 3e-3. verify -------------------------------------------------------------
$voteCalls = ([regex]::Matches($gameOut, 'esl_mapVoteEndgame\(\)')).Count
if ($voteCalls -ne 1) {
    $failures += ("_gamelogic.gsc map vote calls: expected 1, found $voteCalls")
}

$markerCalls = ([regex]::Matches($gameOut, 'esl_gameLogicLoaded\(\)')).Count
if ($markerCalls -ne 1) {
    $failures += ("_gamelogic.gsc load markers: expected 1, found $markerCalls")
}

if (-not $gameOut.Contains('level notify( "exitLevel_called" );')) {
    $failures += '_gamelogic.gsc no longer notifies exitLevel_called - the level would never rotate'
}

# the wait the patch removes has to be gone: with it still in place the engine
# would rotate while the vote is up
if ($gameOut.Contains('min( 10.0, 4.0 + level.postGameNotifies )')) {
    $failures += '_gamelogic.gsc still carries the stock postgame wait'
}

# and the call must sit *after* the guard, or a re-entrant endGame() would run the
# vote twice
$voteIdx  = $gameOut.IndexOf('esl_mapVoteEndgame()')
$stateIdx = $gameOut.IndexOf('game["state"] == "postgame"')
if ($voteIdx -lt 0 -or $stateIdx -lt 0 -or $voteIdx -lt $stateIdx) {
    $failures += '_gamelogic.gsc: the vote call has to come after the endGame() guard'
}

$gameExitsBase = ([regex]::Matches($gameBase, 'exitLevel\( false \);')).Count
$gameExitsOut  = ([regex]::Matches($gameOut,  'exitLevel\( false \);')).Count
if ($gameExitsOut -ne $gameExitsBase) {
    $failures += ("_gamelogic.gsc exitLevel() calls changed: base $gameExitsBase, output $gameExitsOut")
}

$gameIncludeBase = ([regex]::Matches($gameBase, '(?m)^#include')).Count
$gameIncludeOut  = ([regex]::Matches($gameOut,  '(?m)^#include')).Count
if ($gameIncludeOut -ne $gameIncludeBase) {
    $failures += ("_gamelogic.gsc #include count changed: base $gameIncludeBase, output $gameIncludeOut")
}

Write-Ascii $gameFile $gameOut

# -----------------------------------------------------------------------------
#  3f. _playerlogic.gsc : the game's post-match scoreboard stands down for the vote
#
#  spawnIntermission() opens the game's own post-match menu - the scoreboard with
#  the kills, the deaths and the XP/level bar - and, when there is a promotion or a
#  challenge to show, re-opens it every quarter of a second for several seconds.
#
#  That is what the vote was losing to: a script menu cannot be raised above a menu
#  that is re-opened underneath it (the client ignores an openMenu for a menu that
#  is already open), so the vote - which has to be opened while the round is still
#  ending, or the client shows it not at all - only ever flashed through for a
#  single frame between two of those re-opens ("the voting menu flashes for one
#  frame every half second or so").
#
#  Holding the two fields that gate that menu at 0 does not win the race: _rank
#  sets them well after the "game_ended" notify, and the check runs before the next
#  pass of the vote's own loop.  So the check itself is patched: while a vote is
#  running, the game's post-match screen is skipped altogether.
# -----------------------------------------------------------------------------
$basePlayer = Join-Path $baseDir '_playerlogic.gsc'
$playerFile = Join-Path $payloadDir '_playerlogic.gsc'

if (-not (Test-Path -LiteralPath $basePlayer)) { throw "Missing input: $basePlayer" }

$playerBase = Get-Content -LiteralPath $basePlayer -Raw
if ($playerBase.Contains("`r`n")) { $playerEol = "`r`n" } else { $playerEol = "`n" }

$playerOut = $playerBase

# --- 3f-1. the load marker ----------------------------------------------------
# Same purpose as the one in _gamelogic.gsc: it says in the log that this override
# is the one that loaded.  Callback_PlayerConnect() is the per-level entry point in
# this file (see _callbacksetup.gsc), so the marker reaches the log on every level.
$connectPattern = '(?m)^(Callback_PlayerConnect\(\)\s*\r?\n\{\s*\r?\n)'

$connectHits = ([regex]::Matches($playerOut, $connectPattern)).Count
if ($connectHits -ne 1) {
    $failures += ("expected exactly one Callback_PlayerConnect() opening in _playerlogic.gsc (found $connectHits)")
}
else {
    $connectMarker = $playerEol +
        '	// ESL-MOD: tells _esl.gsc that this patched file is the one that loaded -' + $playerEol +
        '	// the vote depends on the guard further down.' + $playerEol +
        '	maps\mp\gametypes\_globallogic::esl_playerLogicLoaded();' + $playerEol

    $playerOut = [regex]::Replace($playerOut, $connectPattern, ('$1' + $connectMarker))
}

# --- 3f-2. the post-match menu stands down for the vote -----------------------

$postMatchGate  = 'if ( level.rankedMatch && ( self.postGamePromotion || self.pers["postGameChallenges"] ) )'
$postMatchGuard = 'if ( !isDefined( level.eslVoteRunning ) && level.rankedMatch && ( self.postGamePromotion || self.pers["postGameChallenges"] ) )'

$gateHits = ([regex]::Matches($playerOut, [regex]::Escape($postMatchGate))).Count
if ($gateHits -ne 1) {
    $failures += ("the post-match menu gate was not found exactly once in _playerlogic.gsc (found $gateHits)")
}
else {
    $playerOut = $playerOut.Replace($postMatchGate, $postMatchGuard)
}

$gateGuardHits = ([regex]::Matches($playerOut, [regex]::Escape($postMatchGuard))).Count
if ($gateGuardHits -ne 1) {
    $failures += ("_playerlogic.gsc map vote guard: expected 1, found $gateGuardHits")
}

$playerIncludeBase = ([regex]::Matches($playerBase, '(?m)^#include')).Count
$playerIncludeOut  = ([regex]::Matches($playerOut,  '(?m)^#include')).Count
if ($playerIncludeOut -ne $playerIncludeBase) {
    $failures += ("_playerlogic.gsc #include count changed: base $playerIncludeBase, output $playerIncludeOut")
}

$playerBraceBase = ([regex]::Matches($playerBase, '\{')).Count - ([regex]::Matches($playerBase, '\}')).Count
$playerBraceOut  = ([regex]::Matches($playerOut,  '\{')).Count - ([regex]::Matches($playerOut,  '\}')).Count
if ($playerBraceOut -ne $playerBraceBase) {
    $failures += ("_playerlogic.gsc brace balance changed: base $playerBraceBase, output $playerBraceOut")
}

# --- 3f-3. no intermission state while a vote runs ----------------------------
# The scoreboard the vote was being hidden behind is not a menu that could be
# closed - the server side log proved the menu guard above was in effect and the
# scoreboard still appeared.  It is the client's own end-of-match draw, and the
# client takes it from its sessionstate: spawnIntermission() below sets it to
# "intermission", which is what makes the client draw that scoreboard over
# everything, menus included.
#
# While a vote is running the player is made a spectator instead, so the vote is
# what is on the screen.  Nothing else reads the state for the few seconds that
# are left of the level.
$statePattern = '(?m)^\tself\.sessionstate = "intermission";'

$stateGuard = @(
    "`t// ESL-MOD: the client draws its own end-of-match scoreboard from this state,",
    "`t// and no menu can be drawn over it.  While a vote runs the player is a",
    "`t// spectator instead, so the vote is what is on the screen.",
    "`tif ( isDefined( level.eslVoteRunning ) )",
    "`t`tself.sessionstate = ""spectator"";",
    "`telse",
    "`t`tself.sessionstate = ""intermission"";"
) -join $playerEol

$stateHits = ([regex]::Matches($playerOut, $statePattern)).Count
if ($stateHits -ne 1) {
    $failures += ("expected exactly one `"intermission`" sessionstate in _playerlogic.gsc (found $stateHits)")
}
else {
    $playerOut = [regex]::Replace($playerOut, $statePattern, $stateGuard)
}

$stateOutHits = ([regex]::Matches($playerOut, 'eslVoteRunning')).Count
if ($stateOutHits -ne 2) {
    $failures += ("_playerlogic.gsc vote guards: expected 2, found $stateOutHits")
}

Write-Ascii $playerFile $playerOut

# -----------------------------------------------------------------------------
#  4. report
# -----------------------------------------------------------------------------
Write-Output ('globallogic : ' + $globFile)
Write-Output ('              ' + $globOut.Length + ' chars')
Write-Output ('menus       : ' + $menusFile)
Write-Output ('              ' + $menuOut.Length + ' chars')
Write-Output ('class       : ' + $classFile)
Write-Output ('              ' + $classOut.Length + ' chars')
Write-Output ('playerlogic : ' + $playerFile)
Write-Output ('              ' + $playerOut.Length + ' chars')

if ($failures.Count -gt 0) {
    Write-Output ''
    Write-Output 'FAILED:'
    foreach ($f in $failures) { Write-Output ('  - ' + $f) }
    exit 1
}

Write-Output ''
Write-Output 'Payload generated and verified.'
