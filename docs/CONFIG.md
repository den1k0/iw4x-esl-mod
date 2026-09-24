# ESL-MOD — configuration reference

Every setting is a normal dvar, so it can be changed at any time from the server
console, from a config script, or through the IW4x launcher's server settings —
no rebuild and no restart required. The watchdog re-reads them continuously.

Example file: [`config/ESL-MOD.cfg`](../config/ESL-MOD.cfg:1)

---

## Version

The mod reports its own version, and the number lives in exactly one place:
[`version.txt`](../version.txt:1) in the repository. [`tools/build.ps1`](../tools/build.ps1:1)
reads it into `esl_modVersion()`, and that function is what puts it in

| where | what it looks like |
|---|---|
| the server name | `^2ESL-MOD^7 \| S&D \| 24 rounds ^3v1.0` — appended to whatever `sv_hostname` holds, so the config keeps its own wording. It carries its own colour (`^3`, yellow) so it reads as a stamp rather than as more of the name |
| `logs\games_mp.log` | `ESL-MOD v1.0 boot sd winlimit=13 roundlimit=24 …`, so every session records the build it actually ran |

It is written into the mod rather than configured, which is the point: the name a
player sees cannot disagree with the code that is running. Releasing is three steps:

```
1.  edit version.txt           one line, e.g. 1.0 -> 1.1
2.  tools\install.cmd          rebuilds and installs
3.  tools\server.cmd restart   the name and the log follow
```

The build refuses a `version.txt` that is missing, empty or not `N.N` (an empty one
would otherwise ship a server called `v`), and checks the number really is inside the
packed archive. `esl_stampHostname()` appends it to `sv_hostname` only once per server
run, even though the level start it happens on runs on every map.

## Master switches

| dvar | default | description |
|------|---------|-------------|
| `esl_rules_enable` | `1` | `0` disables all ESL enforcement (vanilla rules). The scripts stay loaded. **Unset counts as enabled** — the server config is not exec'd on every setup, and reading an unset dvar as `0` silently disabled the spawn hook, the watch dog and the class memory while the editor kept working. |
| `esl_notify` | `1` | Show `[ESL-MOD] your class was adjusted…` in the player's console when a class is corrected. |
| `esl_debug` | `0` | `1` prints the active rule set at level load **and** turns on the class diagnostics: an `[ESL]` state line on the HUD and in the client console whenever the class or the loadout changes (`type=`, `cls=`, `exp=`, `cw=`), plus a heartbeat every ten seconds. Silence by default — the layer exists to explain a round transition, and is distracting in play. |
| `esl_sanitize_interval` | `5` | Seconds between class re-checks. `0` = only check on connect and on spawn. Lower values close the edit→spawn window further at the cost of a little more script time. |

## Core rules

| dvar | default | description |
|------|---------|-------------|
| `esl_no_killstreaks` | `1` | Forces `scr_game_hardpoints 0` and clears the stored killstreak slots. |
| `esl_no_deathstreaks` | `1` | Removes the deathstreak perk on every spawn, which neutralises deathstreaks. |
| `esl_deathstreak_clamp` | `0` | Optional extra: also force `self.pers["cur_death_streak"]` to `0`, once per spawn and once per death. **Off by default** — writing player state during level load crashes the engine, see [DIAGNOSTICS.md](DIAGNOSTICS.md). |
| `esl_no_perks` | `1` | Forces `scr_game_perks 0` and clears the stored perk slots. Equipment is kept. |
| `esl_enforce_attachments` | `1` | Apply the attachment whitelist. |
| `esl_enforce_equipment` | `1` | Apply the lethal / tactical whitelist. |
| `esl_enforce_weapons` | `1` | Apply `esl_weapon_denylist`. |
| `esl_keep_classes` | `1` | Keep a player's classes across a **map change and a restart** (the class archive below). `0` = every map starts from the type defaults again. |

> `esl_no_perks 0` allows perks again, but the stored perk slots are left alone
> only for perks 1–3; slots for equipment and the death streak are governed by
> their own switches.

## Attachments

`1` = allowed, `0` = removed from the class. "No attachment" is always allowed.

| dvar | default |
|------|---------|
| `esl_attach_silencer` | `0` |
| `esl_attach_acog` | `0` |
| `esl_attach_reflex` | `0` |
| `esl_attach_eotech` | `0` |
| `esl_attach_thermal` | `0` |
| `esl_attach_grip` | `0` |
| `esl_attach_gl` | `0` |
| `esl_attach_shotgun` | `0` |
| `esl_attach_heartbeat` | `0` |
| `esl_attach_fmj` | `1` |
| `esl_attach_rof` | `0` |
| `esl_attach_xmags` | `1` |
| `esl_attach_akimbo` | `0` |
| `esl_attach_tactical` | `0` |

Unknown attachment names are always rejected.

Commonly used competitive sets:

```
// "silencers only"
set esl_attach_silencer 1
set esl_attach_acog 0
set esl_attach_reflex 0

// "no restrictions" (allow everything)
set esl_enforce_attachments 0
```

## Equipment (lethal slot)

| dvar | default |
|------|---------|
| `esl_allow_frag_grenade` | `1` |
| `esl_default_equipment` | `frag_grenade_mp` |
| `esl_allow_semtex` | `1` |
| `esl_allow_throwingknife` | `0` |
| `esl_allow_claymore` | `0` |
| `esl_allow_c4` | `0` |
| `esl_allow_blastshield` | `1` |
| `esl_allow_tacticalinsertion` | `0` |

## Equipment (tactical slot)

| dvar | default |
|------|---------|
| `esl_allow_flash_grenade` | `1` |
| `esl_allow_smoke_grenade` | `1` |
| `esl_allow_concussion_grenade` | `1` |

### Spectating

| dvar | default | meaning |
|------|---------|---------|
| `esl_spectate_team_only` | `1` | `1` = a dead player (or a spectator without a team) may only watch players of their **own** team. |

The game's own setting is `scr_game_spectatetype 2` = "free": every team plus a
free camera, so a dead player can cycle through the enemy — and in S&D that means
watching the surviving defenders defuse a planted bomb. ESL uses `1` = "own team
only" (see the `switch` in `_spectating.gsc::setSpectatePermissions()`).

Getting that to stick needs two extra steps, both in
[`src/maps/mp/gametypes/_esl.gsc`](../src/maps/mp/gametypes/_esl.gsc:1):

* `esl_applySpectateRules()` writes `scr_game_spectatetype 1` at level init, and
  `esl_patchSpectatetype()` writes it a second time after one second. The value is
  not read from the dvar: `_tweakables::registerTweakable()` caches it in
  `level.gameTweaks["spectatetype"].value` while the level starts up, and
  `setSpectatePermissions()` reads that cached copy. Whichever of the two is
  written first, the other one covers it.
* `sd.gsc::checkAllowSpectating()` then opens the other team up anyway: as soon as
  one team is fully dead it sets `level.spectateOverride[team].allowEnemySpectate`
  — the stock "watch the other side while you wait" rule — and nothing ever clears
  it again, so from the first team wipe on that team could watch the enemy for the
  rest of the map. `esl_keepSpectatingOwnTeam()` polls for that flag, replaces the
  override structs and calls `_spectating::updateSpectateSettings()`, which pushes
  the permissions to every player again. The poll interval (0.1 s) is the width of
  the window in which the enemy is briefly viewable.

### Classes across a map change and a restart

The ESL loadouts live in script data, which is per level, so a new map used to
start from the type defaults and every player had to rebuild their class — which
is what the first round of a map was spent on. ESL-MOD now archives the accepted
class in server dvars, the one kind of state that outlives a level:

| dvar | contents |
|------|----------|
| `esl_class_<id>_assault` | the loadout of that class type, fields in `esl_mirrorKeys()` order joined with `|` |
| `esl_class_<id>_specops` | same, for the SMG class |
| `esl_class_<id>_sniper` | same, for the sniper class |
| `esl_type_<id>` | the class type the player committed (`assault` / `specops` / `sniper`) |

`<id>` is the player's guid (the value the game itself logs as `J;<guid>;…`),
lower-cased — a guid is hex, so every character of it is already legal in a dvar
name. A player who has neither a guid nor an xuid falls back to their name, with
everything a dvar name cannot take filtered out. The archive is written when a
class is accepted (`esl_menuAcceptClass()`), and read back by `esl_archiveRead()`
when both the level store and the playerdata are empty — which is exactly the
map-change case. `esl_keep_classes 0` turns it off.

**Across a restart** those dvars die with the process, so a restart used to cost
everybody their class. `tools\server.cmd stop` — and therefore `restart` — now
reads them out of the server *while it is still up* and writes them into
`mods\ESL-MOD\configs\ESL-MOD_classes.cfg`, which the server config exec's at boot:

```
set esl_class_bbdb7963f59fc1ec_sniper "cheytac|usp|none|none|none|none|none|none|frag_grenade_mp|specialty_null|specialty_null|specialty_null|specialty_null|flash_grenade"
set esl_type_bbdb7963f59fc1ec "sniper"
```

[`tools/class-archive.ps1`](../tools/class-archive.ps1:1) is what does it (the
server script simply calls it), so it can also be run by hand against a server
that is already up. It refuses to write when the server has nothing to give — a
server that is not running yet must not cost anybody a class — which is what
`-Prune` overrides (`... -Prune` writes the file even when it is empty, the way to
drop what is in it on purpose). Delete
[`config/ESL-MOD_classes.cfg`](../config/ESL-MOD_classes.cfg:1) to start everybody
from the type defaults.

### Time to pick a class at the start of a map

Even with the archive there is a window before the first round of every map. On PC
the stock script takes the `scr_game_playerwaittime` branch for it
(`_gamelogic.gsc` sets `level.prematchPeriod` from it, then counts down
`scr_game_matchstarttime` seconds); the `scr_game_graceperiod` next to it is the
*console* branch of the same code and is inert here. ESL ships **20 s** plus a 5 s
countdown:

| dvar | example | meaning |
|------|---------|---------|
| `scr_game_playerwaittime` | `20` | wait before the first round of every map |
| `scr_game_matchstarttime` | `5` | countdown at the end of that wait |

## Weapons

| dvar | default | description |
|------|---------|-------------|
| `esl_weapon_denylist` | *(empty)* | Comma separated base weapon names that are banned, lower case, no spaces, no `_mp` suffix. |

Example:

```
set esl_weapon_denylist "ak74u,peacekeeper,ak47classic,riotshield,onemanarmy,rpg,at4,stinger,javelin,m79,throwingknife"
```

Valid base names (the primary/secondary part of the weapon asset, without
attachments and without `_mp`):

```
m16  ak47  m4  famas  scar  tavor  fal  masada  fn2000
mp5k uzi   ump45 kriss ak74u p90
spas12 m1014 ranger model1887 striker aa12
cheytac m40a3 barrett wa2000 m21 dragunov
rpd sa80 mg4 m240 aug peacekeeper ak47classic
beretta usp deserteagle coltanaconda glock beretta393 pp2000 tmp
m79 rpg at4 stinger javelin
riotshield onemanarmy deserteaglegold
```

## Native dvars ESL-MOD sets

These belong to the base game. ESL-MOD sets them according to the switches above;
set them yourself only if you disable the matching switch.

| dvar | set to | why |
|------|--------|-----|
| `scr_game_perks` | `0` when `esl_no_perks 1` | native "no perks" support |
| `scr_game_hardpoints` | `0` when `esl_no_killstreaks 1` | killstreak rewards off |
| `scr_game_spectatetype` | `1` when `esl_spectate_team_only 1` | own team only; the game type caches this, hence the second pass |

## ESL S&D match format

ESL plays Search & Destroy as a **best-of style 24 round match: first to 13
round wins, sides switch after the 12th round, 7.5 seconds to defuse**.  Both
halves are 12 rounds, so a match that is 12-12 after round 24 is a draw.  Those
numbers are what [`config/ESL-MOD_sd.cfg`](../config/ESL-MOD_sd.cfg:1) sets, and
the mod also pushes them into the game type by itself, so the format holds even
when the config is never exec'd:

| dvar | default | meaning |
|------|---------|---------|
| `esl_sd_rules` | `1` | `0` = leave the match format alone |
| `esl_sd_winlimit` | `13` | rounds needed to win the match |
| `esl_sd_roundlimit` | `24` | rounds in the match; `0` = no round limit |
| `esl_sd_roundswitch` | `12` | sides switch after N rounds (halftime) |
| `esl_sd_defusetime` | `7.5` | seconds to defuse |

The match ends on whichever limit arrives first:

* the **win limit** — the 13th round win, at the earliest in round 13 (7-6) and at
  the latest in a deciding round 25 *if* there were no round limit;
* the **round limit** — `isLastRound()` compares `roundsPlayed` against
  `roundlimit - 1` and ends the match once round 24 is decided.  With
  `winlimit 13` that means a 12-12 match is a **draw**: the round limit stops it
  one round before a 13th win could be scored.  Set `esl_sd_roundlimit 25` (or
  `0`, which means no round limit at all) if you want a deciding 25th round
  instead.

`roundlimit 24` is also what the stock `displayRoundSwitch()` measures against:
it only calls a round switch at the halfway point when `roundsPlayed * 2` equals
the round limit, and 12 * 2 = 24, so round 12 is treated and announced as the
halftime.  (The win limit path does the same check as `roundsPlayed ==
winlimit - 1`, which with 13 is also round 12.)

`esl_applySdRules()` runs from `esl_init()`, i.e. from the top of the game type's
`main()` (`sd.gsc` calls `_globallogic::init()` before it registers its own dvars
and before `updateGametypeDvars()` reads `planttime` / `defusetime` /
`bombtimer`).  Setting the values there is early enough for the whole match — and
it has to be synchronous, because `defusetime` is read exactly once into
`level.defuseTime`.

### The round switch clamp

The stock game type registers the round switch as
`registerRoundSwitchDvar( level.gameType, 3, 0, 9 )` — note the `9`.  That helper
in `_utility.gsc` clamps `scr_sd_roundswitch` and stores the clamped value in
`level.roundswitch`.  It runs *after* ESL-MOD's level init, so setting
`scr_sd_roundswitch 12` on its own gives a 9 round half: sides would switch at
round 9 — and, since 9 * 2 is not the round limit, the screen would say
"intermission" rather than "halftime".  ESL-MOD therefore starts one short thread
(`esl_patchRoundSwitch()`) that waits one second and writes
`level.roundswitch = 12` again.  `checkRoundSwitch()` only reads the field when a
round ends, so a one second delay is harmless, and nothing else writes it —
the `update_roundswitch` notify is not handled anywhere — so the correction
sticks for the rest of the map.

The native dvars the script writes at level init:

| dvar | set to | why |
|------|--------|-----|
| `scr_sd_winlimit` | `esl_sd_winlimit` | match win condition |
| `scr_sd_roundswitch` | `esl_sd_roundswitch` | halved by the clamp above, repaired afterwards |
| `scr_sd_defusetime` | `esl_sd_defusetime` | read once into `level.defuseTime` |
| `scr_sd_roundlimit` | `esl_sd_roundlimit` | match length; the match ends on round 24 |

## Recommended S&D match dvars

See [`config/ESL-MOD_sd.cfg`](../config/ESL-MOD_sd.cfg:1) for a ready-to-use file.
The most relevant ones, with the ESL values from that file:

| dvar | example | meaning |
|------|---------|---------|
| `g_gametype` | `sd` | game type |
| `scr_sd_roundlimit` | `24` | rounds in the match (`0` = until the win limit) |
| `scr_sd_winlimit` | `13` | rounds needed to win the match |
| `scr_sd_timelimit` | `2.5` | round length in minutes |
| `scr_sd_roundswitch` | `12` | swap sides after N rounds |
| `scr_sd_planttime` | `5` | seconds to plant |
| `scr_sd_defusetime` | `7.5` | seconds to defuse |
| `scr_sd_bombtimer` | `45` | seconds until the bomb explodes |
| `scr_sd_multibomb` | `0` | `1` = both bomb sites active |
| `scr_game_graceperiod` | `15` | seconds before the round starts |
| `scr_tispawndelay` | `5` | tactical insertion respawn delay |
| `scr_game_allowkillcam` | `0` | `1` = show killcams |
| `scr_game_spectatetype` | `1` | spectating: `0` off, `1` own team only, `2` free |
| `scr_team_fftype` | `1` | team damage: `0` off, `1` on, `2` reflect, `3` shared |
| `sv_maxclients` | `18` | player slots |
| `sv_randomMapRotation` | `1` | pick the next map from the rotation at random |

## Verifying the rules are active

1. Start a server with the mod loaded and run `esl_debug 1`, then change the map.
   The console prints the full active rule set.
2. In game, open the server console and check:
   ```
   scr_game_perks
   scr_game_hardpoints
   scr_game_spectatetype
   ```
   The first two must be `0`, the spectate type must be `1`. Die in a round with
   the other team still alive and you should only be able to cycle through your
   own team.
3. Still in the console, check the match format:
   ```
   scr_sd_winlimit
   scr_sd_roundlimit
   scr_sd_roundswitch
   scr_sd_defusetime
   ```
   Those must read `24`, `24`, `12` and `7.5`.  `scr_sd_roundswitch` is registered by
   the game with a 0..9 clamp, so the value that actually matters is
   `level.roundswitch`; if the sides switch at round 9 instead of 12 the repair
   thread did not run, and `esl_debug 1` prints one line about it at level start.
3. Try to save a class with a banned attachment, then respawn. The server prints
   the notice to you and the class is corrected.
