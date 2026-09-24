# ESL-MOD — in-game create a class

ESL-MOD ships a create-a-class editor that is used **inside a match**, the way
ProMod does it: no trip to the main menu, and it is reachable while the map is
still loading and while playing.

## How to open it

The class list opens by itself whenever the game asks the player to pick a class
(`_menus::beginClassChoice()`, called after joining or switching sides), and it
can be opened at any time from the pause menu with **Choose Class** — the stock
menu entry is redirected to the ESL menu, the same way ProMod does it.

* The class list appears first: **Assault / SMG / Sniper** (demolitions is
  stripped on purpose — see below). Pick one. The middle entry is only labelled
  `SMG`; the response string behind it is still `specops` and the class type is
  still the game's spec-ops slot (`esl_classTypeSlot()` → 16).
* The editor opens as a popup: `1` primary, `2` primary attachment, `3` side arm,
  `4` lethal, `5` tactical, `6` camo, `7` **Start!** to accept. `Esc` goes back to
  the class list.
* Every popup marks the entry that is currently equipped with a highlighted
  plate, fed by the `loadout_*` dvars ESL-MOD publishes when the editor opens
  (`loadout_lethal` for the lethal, `loadout_primary_attachment` and
  `loadout_secondary_attachment` for the attachments, …).

Accepting the class applies it immediately when the game allows a class change
(grace period / pre-match) and otherwise at the next spawn, exactly like the
stock class menu behaves.

## Class model

ESL plays with **three class types**, and they own their loadouts outright: the
loadouts live in script data on the player (`self.eslClasses`), and the vanilla
custom-class playerdata is never read or written for them. Nothing the player
built in the main-menu create-a-class can leak into an ESL class, and the ESL
editor cannot modify the vanilla classes either.

| Class type | ESL class index | Class name |
|---|---|---|
| `assault` | 15 | `custom_esl_assault` |
| `specops` | 16 | `custom_esl_specops` |
| `sniper` | 17 | `custom_esl_sniper` |

Indices 0–14 are the vanilla classes (`custom1`–`custom10` and `class0`–`class14`
both live in that range), so the ESL types start above them and can never collide
with a class the player owns.

Two details make the stock [`_class::giveLoadout()`](../build/payload/maps/mp/gametypes/_class.gsc:319) apply an ESL class without
the class system being replaced:

* the class names contain **`custom`** — `giveLoadout()` selects its
  custom-class branch with `isSubstr( class, "custom" )`, and that is the branch
  that goes through the `cac_get*()` accessors; and
* the generated `_class.gsc` redirects those seven accessors to
  `esl_cacWeapon()`, `esl_cacAttachment()`, `esl_cacCamo()`, `esl_cacPerk()`,
  `esl_cacOffhand()` and `esl_cacDeathstreak()` when the class index is an ESL
  one, so the reads come from the ESL storage instead of the playerdata.

Each type starts from an ESL default loadout (M4, MP5K or Intervention, a USP
.45, a frag grenade, no perks, no attachments and no camo) the first time it is
used, and every existing ESL rule applies unchanged: perks and killstreaks are
off, and a banned attachment or weapon is rejected in the editor before it is
ever stored.

**Where a class is stored:** per player, under a key built by
[`esl_storeId()`](../src/maps/mp/gametypes/_esl.gsc:1268) — the engine's
per-client **guid** first (the value the game itself logs as `J;<guid>;…`), then
the XUID, then the player name. That key indexes the durable copies on the level
(`level.eslStore[id][slot]`, `level.eslType[id]`). Two players who share a key
share those copies, and then one player's committed class is what the watchdog
hands to the other — the "somebody picked a class and it changed for everyone"
report. The key is therefore made unique by construction: a second user of the
same id gets an `#<entitynumber>` suffix, and every join logs the key it settled
on (`ESL-MOD join <name> id=…`), which is the first thing to compare in such a
report. See [DIAGNOSTICS.md](DIAGNOSTICS.md#the-class-diagnostics-channel-actually-works-now).

**Consequence:** within a match the loadouts are kept across round transitions.
`_playerlogic::spawnPlayer()` builds the loadout from `self.class` (not from
`pers["class"]`), and a round-based game type re-runs the class selection between
rounds, so [`esl_keepClass()`](../src/maps/mp/gametypes/_esl.gsc:348) re-asserts
the class on `spawned_player` and `esl_reapplyLoadout()` rebuilds the loadout when
it had been dropped. See
[DIAGNOSTICS.md § 8](DIAGNOSTICS.md#8-reading-the-class-reset-diagnostics) for the
log lines that tell which of the two was lost.

**Across a map change** the classes are restored from the *class archive*: the
accepted class is packed into a server dvar per class type
(`esl_class_<id>_<type>`, fields in `esl_mirrorKeys()` order joined with `|`) plus
one dvar for the committed type (`esl_type_<id>`). Server dvars are the only state
that outlives a level, so without this every new map began with the type defaults
— an M4 for assault, an MP5K for the SMG class — and the first round was spent
rebuilding classes. `esl_archiveRead()` seeds the working copy from it when both
the level store and the playerdata are empty, which is exactly the map-change
case. `esl_keep_classes 0` disables it.

**Across a restart** the dvars go away with the process, so the same class was
lost again — "after a server restart classes don't save". `tools\server.cmd stop`
and `restart` therefore read the archive out of the running server *before*
stopping it and write it into `mods\ESL-MOD\configs\ESL-MOD_classes.cfg`, which
the server exec's at boot ([`tools/class-archive.ps1`](../tools/class-archive.ps1:1)).
A stop that skips that — Task Manager, a crash, a hard power-off — still loses the
classes. See
[CONFIG.md § Classes](CONFIG.md#classes-across-a-map-change-and-a-restart).

**Pickups are not a rule violation.** The per-second enforcement
(`esl_enforceClass()`) repairs a wrong *loadout* only within three seconds of a
spawn — that is when the engine has just built it, so a mismatch at that moment
means it built the wrong one (the class-table fallback). Later in a round a weapon
that is not part of the class is a **pickup**: a team-mate's or the enemy's gun,
which the rules allow. It used to be "repaired" like a fault, which took the
weapon away and re-gave the class weapons — the report "I picked up a UMP as the
sniper class and it restored my class". Pickups are now left alone; the class
itself is still re-asserted on every pass whenever the engine has reset it. Each
skip is logged once per life, so the log shows it:

```
ESL-MOD pickup: holding ump45_mp on custom_esl_sniper - left as it is
```

## Weapon stats under the editor

The editor draws four lines under the buttons — two for the primary, two for the side
arm — showing what the weapon currently selected actually does:

```
Primary     |DMG: 40 - 30  |Head: 1.6x
            |Range: 51 m  |Penetration: large
Secondary   |DMG: 50 - 30  |Head: 2x
            |Range: 30 m  |Penetration: medium
```

They exist because the ESL ruleset is not the stock game: head multipliers, the ACR's
rate of fire and the Intervention's ADS time are all ESL's own values, and a player
coming from public matches has no way to know them. The lines are **numbers only** — no
bars, no sliders, nothing to interpret. A magazine field is not in yet.

| wording | meaning | source |
|---|---|---|
| `|DMG: 40 - 30` | maximum and minimum damage | `damage` / `minDamage` |
| `|Head: 1.6x` | head multiplier | `locHead` (identical to `locHelmet`) |
| `|Range: 51 m` | the far end of the damage curve | `minDamageRange`, 1 unit = 1 inch |
| `|Penetration: large` | what the bullet goes through | `penetrateType` — `none`, `small`, `medium` or `large` |

**Why the text is not a table.** Feeding a menu from a table is the obvious route and
this one tried it twice. **The engine's parser cuts a table cell at a `|`**: a cell
holding `Primary | DMG: 40 - 30 | …` came back as column 1 = `Primary` and column 2 =
the damage pair, which is what "the stats only show Max dmg and Min dmg" turned out to
be. And **a plain cell drawn on its own rendered nothing at all** — the footer's values
never appeared while its literals did. No table in the shipped data carries a `|` or a
`:` in a cell either.

So the text is composed where a string is just a string, and reaches the menu the way
every other value the editor shows does — as a client dvar, one per slot:

```
esl_stats_primary     |DMG: 40 - 30  |Head: 1.6x  |Range: 51 m  |Penetration: large
esl_stats_secondary   |DMG: 50 - 30  |Head: 2x    |Range: 30 m  |Penetration: medium
```

`esl_publishWeaponStats()` in [`_esl.gsc`](../src/maps/mp/gametypes/_esl.gsc:3018) fills
those two when the editor opens and again on every weapon pick, so the lines follow the
selection, and `esl_weaponStatLineAll()` joins the two generated halves into the single
line each slot shows. The weapon → numbers mapping behind them — `esl_weaponStatLineA/B`
— is generated by [`tools/build.ps1`](../tools/build.ps1:293) step 2d **out of the tweaked
weapon payload**, so the lines show what the match uses, and a change to
[`weapon-tweaks.txt`](../src/weapons/weapon-tweaks.txt:1) moves them with it. The build
asserts three of the generated cases inside the packed archive, so stale or missing
stats cannot ship. The generation and the penetration class are described in
[WEAPONS.md](WEAPONS.md#the-stats-the-class-editor-reads).

**How the UI draws it.** Two items in
[`cac_ingame.inc`](../src/ui_mp/emzui/cac_ingame.inc:156), one per slot, at y 350 and 374
beside the slot's name, each a `dvarString()` in a box 440 px wide. With the field spelled
out as `|Penetration: large` the longest line is 57 characters, ~400 px at the game's text
size — inside the box, but not by much, which is why the label is written out in full
(`|Pen:` shipped first and was read as a truncated word) and why a fifth field would not
fit. The width matters because a text item *wraps* at its box width and the wrapped part is
drawn over the line below. They sit under the `Max dmg` / `Min dmg` readout that the editor
itself draws around y 262–322; that readout is a stock part of the class screen, not
something this mod produces.

The key in the table is the **weapon file base name** (`ump45`, `ak47`, `cheytac`),
which is what those dvars already hold, so no translation is needed. Column 1 is the
damage pair, 2 the head multiplier, 3 the range, 4 the rate of fire and 5 the magazine;
a weapon with no magazine value leaves column 5 empty, and then nothing is drawn after
`|Mag:` for it.

Every entry the editor offers has a row. The one that used not to — the **AK-74u**,
listed by the specops popup since the menus were imported but with no ESL weapon file
behind it — is now shipped by the mod itself, see
[WEAPONS.md § the weapons ESL adds itself](WEAPONS.md#the-weapons-esl-adds-itself).

## What the editor sends

The UI talks to the server purely with `scriptMenuResponse` strings, which
[`_esl.gsc`](../src/maps/mp/gametypes/_esl.gsc:1) handles in
`esl_handleCacResponse()`:

| Response | Meaning |
|---|---|
| `assault` / `specops` / `sniper` | class type chosen |
| `loadout_primary:<weapon>` | primary weapon |
| `loadout_primary_attachment:<group>:<attachment>` | primary attachment |
| `loadout_secondary:<weapon>` | side arm |
| `loadout_secondary_attachment:<group>:<attachment>` | side arm attachment |
| `loadout_grenade:<grenade>` | tactical grenade |
| `loadout_lethal:<lethal>` | lethal (frag or throwing knife) |
| `loadout_camo:<camo>` | camo |
| `start` | accept the class |
| `go` | UI redraw request |
| `back` | cancel |

The item picks (`loadout_*`) are made in the editor's *popup* menus — the weapon,
attachment, camo and grenade lists are separate menus with names of their own — so
the generated `_menus.gsc` matches them on the **response text alone**
(`isSubStr( response, "loadout" )`), before it looks at the menu name. Dispatching
purely by menu name silently drops every item the player picks. ProMod draws the
same distinction.

When the editor opens, ESL-MOD publishes that type's own stored loadout into the
dvars the editor reads (`loadout_primary`, `loadout_secondary`,
`loadout_primary_attachment`, `loadout_secondary_attachment`, `loadout_grenade`,
`loadout_lethal`, `loadout_camo`), so the editor always opens showing what the ESL
class actually holds and never a vanilla class.

## How the routing works

Two things have to line up for the ESL menus to be used at all, and neither can
be done from the ESL code, because both live in the game's own
[`_menus.gsc`](../build/payload/maps/mp/gametypes/_menus.gsc:1):

1. **The redirect.** `_menus::init()` assigns `game["menu_changeclass_allies"]`,
   `game["menu_changeclass_axis"]` and `game["menu_changeclass"]`. It is started
   as a *thread* from `_gamelogic.gsc`, i.e. **after** `_globallogic::init()`, so
   assigning those keys from the ESL hook is pointless — it is overwritten. They
   have to be changed in `_menus.gsc` itself, which is why the build patches that
   file:

   ```gsc
   game["menu_changeclass_allies"] = "changeclass_marines_mw";
   game["menu_changeclass_axis"]   = "changeclass_opfor_mw";
   game["menu_changeclass"]        = "changeclass_mw";
   ```

2. **The dispatch.** `_menus::onMenuResponse()` routes responses by *menu name*.
   The generated `_menus.gsc` claims the three ESL menus before its stock chain
   runs, so the class-type responses never reach the stock handler:

   ```gsc
   if ( menu == "changeclass_marines_mw" || menu == "changeclass_opfor_mw" || menu == "changeclass_mw" )
   {
       self maps\mp\gametypes\_globallogic::esl_handleCacResponse( menu, response );
       continue;
   }
   ```

Everything else in the in-game menus is untouched stock behaviour, and the other
menu callbacks (`level.allies`, `level.axis`, …) keep their stock handlers.

## Leaving a screen: ESC and the Back button

Both screens have a Back button at the bottom of the screen and both answer ESC,
but they get there in completely different ways — which is worth knowing, because
it is easy to fix one and not the other:

| | class list | editor |
|---|---|---|
| Back button | `action { close self; }` in [`navcontrols.inc`](../src/ui_mp/navcontrols.inc:21) — closes the menu in UI script, the server is not involved | same |
| ESC | `onEsc { scriptMenuResponse "back"; }` in the menu file — the response goes to the server | same |

The ESC path is the one that depends on the server, and the dispatch above is
where it goes wrong if it is not handled: `onMenuResponse()` claims every
response of the three ESL menus *before* its own stock chain, and the stock chain
is where `"back"` means "close the popup and the in-game menu". A response the ESL
handler does not recognise is therefore dropped, not passed on — ESC then does
nothing at all while the Back button keeps working.

`esl_handleCacResponse()` handles both:

```gsc
// class list
if ( response == "back" )            // ESC: leave the list
{
    self.eslEditorOpen = false;
    self closepopupMenu();
    self closeInGameMenu();
    return;
}

// editor
if ( response == "back" )            // ESC: back to the class list
{
    self closepopupMenu();
    self closeInGameMenu();
    self thread esl_openClassList();
    return;
}
```

The two do different things on purpose: from the editor, ESC is a step *up* to the
class list; from the class list there is nothing above it, so it leaves the menu.

## Menu-level restriction (the greying out)

The UI greys out anything it may not offer, driven by client dvars. They have to
be set **before the class list is drawn** — the list greys every entry out and
refuses to action it until `allies_allow_<type>` exists — which is why the
generated `_menus.gsc` calls `esl_prepareClassMenu()` both from
`beginClassChoice()` and before handling the "changeclass_marines" /
"changeclass_opfor" responses. `esl_pushAvailability()` then refreshes the rest
when the editor opens:

| dvar family | source |
|---|---|
| `weap_allow_<weapon>` | `esl_weapon_denylist` |
| `attach_allow_<group>_<attachment>` | the `esl_attach_*` switches |
| `allies_allow_<type>` / `axis_allow_<type>` | always `1` (unrestricted) |

So a banned weapon or attachment is now **not selectable at all**, instead of
being silently reverted at spawn.

A weapon added to a popup has to be added to the `weap_allow_*` list in
`esl_pushAvailability()` in the same breath: an entry whose dvar does not exist is drawn
greyed out and its button does nothing, which reads as "the popup does not have that
weapon". That is exactly how the **P90** was missing — the rules allowed it, the popup did
not list it, and no `weap_allow_p90` was pushed; it is entry 6 of the SMG popup now, and
the same list is mirrored in `esl_uiWeapons()` for reference.

## Keeping the class across a round transition

The per-player monitors used to be started from the `connected` notify, which
fires once per client — not once per entity. A round transition can hand the
player a new entity, and then the monitors were gone: the first spawn announced
itself and every later one did nothing (no `[ESL]` line at all after a respawn),
and nothing re-asserted the class. `esl_onPlayerSpawned()` is a **level** thread -
not attached to any player - that re-arms them on every `player_spawned` notify,
and `esl_attachPlayerLogic()` makes that idempotent per entity via a flag on the
entity itself.

`self.eslClassType` and `self.eslClasses` are script fields on the player entity,
so they last exactly as long as the entity does. A round transition brought the
class back as the **type default** — a UMP45 and a gold Deagle came back as an
MP5K and a USP, the specops defaults — while everything within a round worked.
Playerdata keys the engine does not know about did not survive a round either,
so the working copy cannot be the only one:

* the durable copy lives on the **level**, keyed by `clientid`, which outlives
  rounds inside the map: `level.eslType[clientid]` for the class type and
  `level.eslStore[clientid][classIndex][field]` for the loadout
  ([`esl_storeSet()`](../src/maps/mp/gametypes/_esl.gsc:823) and friends);
* it is refreshed by `esl_mirrorClass()` from every storage writer, and by
  `esl_mirrorActiveClass()` when the editor opens or the class is accepted.
  Playerdata is written as well — it costs nothing and it is the one thing the
  engine itself carries across rounds;
* [`esl_cacPrepare()`](../src/maps/mp/gametypes/_esl.gsc:744) **seeds a missing
  working copy from the durable one instead of from the defaults**, so the very
  first access after a round transition already sees the class the player chose;
* [`esl_restoreActiveClass()`](../src/maps/mp/gametypes/_esl.gsc:958) rebuilds the
  type memory and the working copy at the start of every spawn, and
  [`esl_memoryClassName()`](../src/maps/mp/gametypes/_esl.gsc:2331) is called at
  the top of `giveLoadout()` — so **every** spawn builds the class the player
  chose even if the engine hands in a stale or reset class name;
* `esl_keepClass()` reads the durable type, not the entity field, for the same
  reason.

[`tools/build.ps1`](../tools/build.ps1:125) asserts the `giveLoadout()` prologue
is present, so the memory cannot stop being consulted in a rebuild.

### Which copy survives what

Measured on the target setup, because a level change turned out to be the case
that mattered even for a plain round transition:

| copy | lives as long as | role |
|---|---|---|
| `self.eslClasses` | the player entity | the working copy every accessor reads |
| `level.eslStore` / `level.eslType` | the level | fast lookup and the watchdog's source |
| `pers["esl_type"]` / `pers["esl_<slot>_<field>"]` | the playerdata, i.e. across levels | **the authority**: it is what brought the committed type back after a level reload. The keys are per slot — a single set of keys for "the class in use" made seeding a fresh type copy the equipped class into it, so the sniper editor opened showing the UMP45 equipped in specops |

`esl_restoreActiveClass()` prefers the playerdata copy and writes it back into the
level store, `esl_cacPrepare()` seeds a fresh working copy from either, and
`esl_onPlayerSpawned()` seeds **at the spawn notify** — the engine calls
`giveLoadout()` a few lines later in the same frame, so that is the last moment at
which the working copy can be filled before the class is built. Seeding any later
left the first spawn of a new level on the type defaults: no camo and no tactical.

`esl_applyLoadoutNow()` is the last resort under all of it: it applies the class
with `takeAllWeapons()` / `_giveWeapon()` / `buildWeaponName()` directly, so the
repair does not depend on `giveLoadout()` having run at all.

Because a rebuild briefly takes every weapon away, the enforcement refuses to run
while the player is busy with the objective — `isPlanting` / `isDefusing` are
checked, and a weapon whose name contains `bomb` or `briefcase` counts as
"nothing to check". Without those guards the per-second pass saw the bomb (a
weapon that belongs to no class) as the wrong weapon and rebuilt the loadout
mid-plant, which cancels the plant — reported as "I can't plant the bomb, it says
class adjusted".

The same guard exists for a **deferred class change**: picking a class while alive
is meant to apply at the next spawn (that is what the stock menu does, and the
"change class next spawn" message says so). `esl_menuAcceptClass()` sets
`eslPendingClass` in that case, the enforcement skips while it is set, and the next
spawn clears it — otherwise the new class was applied mid-life, reported as
"choosing sniper while alive gives me a sniper immediately". A five second
throttle on top means no repair can repeat at a rate the player would notice.

## What the engine does to a loadout before the player gets it

[`_class::giveLoadout()`](../build/payload/maps/mp/gametypes/_class.gsc:297) does
not trust the class it is handed. It runs every item through its own whitelists
and through `isItemUnlocked()`, and replaces whatever it does not like with
`classTable` row 10 — the stock default class, an M4 and a USP. Both gates were
silently rewriting the ESL loadout, and both are handled in the generated
`_class.gsc`:

| gate | what the player saw | fix |
|---|---|---|
| `isValidPrimary()` / `isValidSecondary()` are older than this build: no `ak74u`, no `m40a3`, no `deserteaglegold` | picking the gold Deagle handed out the default pistol — "gold Deagle + FMJ gives me a USP" — and the AK-74u and M40A3 came out as an M4 | the three refs are added to the switches, matching the newer copy of the same file and the zone source that ships `weapon,deserteaglegold_mp` |
| `isCustomClass && !self isItemUnlocked( … )`, 13 clauses | any weapon **or attachment** the profile has not unlocked is swapped for the default one on every spawn, which is what "my class resets to an M4" actually was | each clause now also requires `!esl_isCacClass( class_num )`: the ESL loadout belongs to the mod, not to the player's unlock progress |

[`tools/build.ps1`](../tools/build.ps1:112) asserts that all three refs are listed
exactly once and that exactly 13 clauses carry the bypass, so neither can quietly
disappear in a rebuild.

## Attachments and equipment the ESL ruleset allows

ESL bans the silencer and replaces it with **FMJ** and **Extended Mags**, so each
attachment popup offers `None / FMJ / Extended Mags` and nothing else. What a
weapon can actually take differs per group, so the popups are separate menus and
the allowed set is published per group
(`attach_allow_<group>_none/fmj/xmags`, groups `assault`, `specops`, `sniper`,
`pistol`):

| group | allowed |
|---|---|
| `assault`, `specops` | None, FMJ, Extended Mags |
| `sniper` (Intervention) | None, FMJ, Extended Mags |
| `sniper` (M40A3) | None only — the weapon takes no attachment |
| `pistol` (Deagle, Magnum, USP, M9) | None, FMJ |
| `pistol` (gold Desert Eagle) | None only |

The **gold Desert Eagle takes no attachment at all** in this game. Equipping one
made the class invalid, and the engine then replaced the side arm with the default
pistol — which is what "gold Deagle + FMJ gives me a USP with FMJ" was. Its entry
therefore routes straight to `LOCAL_SIDEARM_ACTION()` (which forces the attachment
to `none` and never opens the attachment popup), while the Deagle, the Magnum, the
USP and the M9 go through `LOCAL_SIDEARM_ACTION2()` and offer FMJ.
[`esl_pistolAllowsAttachments()`](../src/maps/mp/gametypes/_esl.gsc:1951) is the
single source of that rule: the script clears a stored attachment the new side arm
cannot take and gates `attach_allow_pistol_fmj` / `attach_allow_pistol_xmags` on
it, so the UI cannot offer an illegal combination in the first place. The hotkeys
are declared once at popup level for the same reason — a per-item `execKey` would
let the gold Deagle's `1` open the attachment popup again.

The **M40A3** accepts no attachment either, and is handled the same way rather than
being left out of the sniper popup: when `loadout_primary` is `m40a3`, its
`2. Primary Attachment` and `6. Camo` entries are the greyed `*_DBUTTON*` variants, so
neither hotkey does anything and no attachment can be picked for it.
[`esl_sniperAllowsAttachments()`](../src/maps/mp/gametypes/_esl.gsc:3537) is the single
source of that rule — it returns `0` for the M40A3 and `1` otherwise, the script clears
a stored attachment the weapon cannot take, and `attach_allow_sniper_fmj` /
`attach_allow_sniper_xmags` are gated on it (so do the popup's own entries fall back to
grey if it is opened anyway).
[`esl_sniperAllowsXmags()`](../src/maps/mp/gametypes/_esl.gsc:3549) narrows that one
step further, to the Intervention alone: of the two snipers, only it takes Extended
Mags. The Intervention therefore takes FMJ and Extended Mags and the M40A3 takes
neither, which is the choice the popup offers.

The **lethal slot** is its own popup offering `Frag` and `Throwing Knife`. The
equipment *slot value* carries the `_mp` suffix (`frag_grenade_mp`,
`throwingknife_mp`) while the stats table used for the icon and the description is
keyed without it (`frag_grenade`, `throwingknife`) — `esl_lethalStatsRef()` does
that translation, which is why the popup keeps a `statsRef` (icon) and an
`equipRef` (slot value) per entry.

## Adding a class type back (for example demolitions)

1. In [`changeclass_marines_mw.menu`](../src/ui_mp/scriptmenus/changeclass_marines_mw.menu:50)
   and [`changeclass_opfor_mw.menu`](../src/ui_mp/scriptmenus/changeclass_opfor_mw.menu:51)
   re-add a `BUTTON_DBUTTON*(3,"Demolitions","demolitions")` line and the matching
   `execKey`.
2. In [`cac_ingame.inc`](../src/ui_mp/emzui/cac_ingame.inc:44) re-add
   `OPENMENUONDVAR(loadout_class,demolitions,ocd_popup_cac_demolitions)` — the
   demolitions popup definitions were kept, so nothing else is needed there.
3. In [`_esl.gsc`](../src/maps/mp/gametypes/_esl.gsc:835) add the type to
   `esl_classTypes()`, give it an index in `esl_classTypeSlot()`
   (`demolitions` → 18), widen `esl_isCacClass()` to include it, register the
   name in `esl_ensureCacClasses()`, and give it a default primary in
   `esl_cacDefaults()`. `esl_handleCacResponse()` needs no change — it accepts
   every type `esl_classTypeSlot()` maps to an index.
4. Rebuild: `tools\build.cmd`.

## Where the UI comes from, and credits

The 12 menu files in `src/ui` and `src/ui_mp` are the create-a-class menus from
**ProMod**, which are themselves edited descendants of the stock MW2 menus.
[`tools/dev/import_ui.ps1`](../tools/dev/import_ui.ps1:1) imports exactly the
files reachable from the three `changeclass_*_mw.menu` roots, and deliberately
filters out every ProMod-specific menu (quickpromod, shoutcast, demo, clientcmd,
echo …), so nothing but the editor and its dependencies is shipped.

Only two changes were made to them:

* the **demolitions** class type was removed from the class lists;
* both files gained a comment marking that change.

Everything else — layout, colours, keys — is ProMod's original work and should be
credited as such if this mod is ever published.
