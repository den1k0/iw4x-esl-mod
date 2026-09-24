# ESL-MOD — rule reference

This document explains exactly how every rule is implemented, which base game
script it hooks into, and what a player experiences.

All logic lives in [`_esl.gsc`](../src/maps/mp/gametypes/_esl.gsc:1). During the
build that file is appended to the game's own `maps/mp/gametypes/_globallogic.gsc`
(see [tools/dev/build_payload.ps1](../tools/dev/build_payload.ps1:1)), so a single
script is shipped and `esl_init()` is the entry point. Line numbers below refer to
`_esl.gsc`.

---

## 1. No killstreaks

**Native switch**

```gsc
setDvar( "scr_game_hardpoints", 0 );
level.killstreakRewards = 0;
```

The base script `maps/mp/gametypes/_gamelogic.gsc` does:

```gsc
level.killstreakRewards = getDvarInt( "scr_game_hardpoints" );
```

and `maps/mp/gametypes/_class.gsc::giveLoadout()` only reads the player's
killstreak selection when `level.killstreakRewards` is non-zero. With the dvar at
`0` the loadout always receives `none, none, none`.

**Extra measures**

* `level.killstreakRewards` is forced to `0` directly after every game start, in
  case another script re-evaluated it.
* The three stored killstreak slots (`getPlayerData("killstreaks", 0..2)`) are
  reset to `"none"`, so the killstreak menu in create-a-class shows nothing
  selected.
* The stock UI honours `scr_game_hardpoints`, so killstreak selection is disabled
  in the menu.

**Player experience:** no killstreak icons ever appear, no rewards are granted.

---

## 2. No deathstreaks

Deathstreaks are the `perk4` rows of `mp/perktable.csv`:

| Perk | Name | Kills/deaths required |
|------|------|-----------------------|
| `specialty_grenadepulldeath` | Martyrdom | 4 |
| `specialty_c4death` | C4 death | 5 |
| `specialty_combathigh` | Painkiller | 3 |
| `specialty_finalstand` | Final Stand | 4 |
| `specialty_copycat` | Copycat | 4 |

There is no native dvar for deathstreaks, so they are disabled at two levels.

### 2.1 The grant condition

`_class.gsc::giveLoadout()` only grants a deathstreak when the player's counter
has reached the perk's threshold:

```gsc
if ( self.pers["cur_death_streak"] == deathVal )
{
    self thread maps\mp\perks\_perks::givePerk( loadoutDeathStreak );
    ...
}
```

### 2.2 The granted perk is taken away (primary mechanism)

`esl_stripDeathstreaks()` runs just after every spawn and removes each deathstreak
perk — plus the perks a deathstreak can hand out, such as `specialty_pistoldeath`
from Final Stand — using only the perk API (`_hasPerk()` / `_unsetPerk()`). No
player state is written, so this cannot destabilise the engine.

### 2.3 Optional: clamping the counter

`set esl_deathstreak_clamp 1` additionally forces `self.pers["cur_death_streak"]`
to `0` so the grant condition can never become true in the first place. It is
**off by default** and is strictly event driven — once per spawn, once per death,
never a loop.

> **Why it is off by default:** writing `self.pers[...]` while the level is still
> loading crashes the engine (`Error: 0xC0000005`, access violation) and stalls
> the client on *"waiting for response"*. That was the original ESL-MOD bug; see
> [DIAGNOSTICS.md](DIAGNOSTICS.md).

### 2.4 What was there before

**Why removal rather than deletion?** A class whose saved deathstreak slot holds
an invalid value is replaced by the base script with the `CLASS_DEFAULT`
deathstreak (`specialty_copycat`) — so emptying the slot is not enough, the perk
that gets granted has to be taken away.

**Player experience:** the counter never advances, no deathstreak perk is ever
granted.

---

## 3. No perks

This uses native engine support. `maps/mp/perks/_perks.gsc` contains:

```gsc
validatePerk( perkIndex, perkName )
{
    if ( getDvarInt( "scr_game_perks" ) == 0 )
    {
        if ( tableLookup( "mp/perkTable.csv", 1, perkName, 5 ) != "equipment" )
            return "specialty_null";
    }
    return perkName;
}
```

Setting `scr_game_perks 0` therefore:

* replaces **perk 1, perk 2 and perk 3** with `specialty_null` (no perk),
* **keeps the equipment slot** (lethal grenade, claymore, blast shield, …),
* disables Bling — `_class.gsc::buildWeaponName()` drops the second attachment
  when perks are disabled,
* converts One Man Army classes back to a normal secondary.

The stock create-a-class menu reads the same dvar, so the perk rows are disabled
in the UI.

The mod additionally rewrites every stored perk slot to `specialty_null`, so a
class that was saved while perks were still allowed can never leak a perk in.

**Player experience:** the perk section of create-a-class is disabled; no perk
icons, no perk effects.

---

## 4. Restricted attachments

The whitelist is driven by dvars, one per attachment:

```
esl_attach_silencer   0     // banned - ESL runs without silencers
esl_attach_fmj        1     // allowed
esl_attach_xmags      1     // allowed - "Extended Mags"
esl_attach_acog       0     // banned
esl_attach_gl         0     // banned (underbarrel grenade launcher)
```

`esl_sanitizeStoredClasses()` walks all 15 custom classes, reads both attachment
slots of the primary and the secondary weapon and rewrites anything that is not
whitelisted to `"none"`.

When a change affects the actual loadout, `esl_reapplyLoadout()` immediately
re-runs the stock `_class::giveLoadout()` for that player, which is the same code
path used when a player picks a different class mid-game. The player sees:

```
^2[ESL-MOD]^7 your class was adjusted to the ESL rule set
```

Unknown/renamed attachments are **denied** by default (`esl_attachmentAllowed()`
returns `false` for anything it does not know), so a future attachment cannot
silently slip through.

Because the stored class is corrected, the create-a-class menu shows `None` for
the banned slot the next time it is opened, and the correction is pushed to the
client.

---

## 5. Optional weapon limits

```
set esl_weapon_denylist "ak74u,peacekeeper,ak47classic,riotshield,onemanarmy"
```

Comma separated list of **base** weapon names (no `_mp` suffix, no attachments,
lower case, no spaces). A banned weapon is removed from the class — the mod does
not substitute another weapon, the player has to choose a legal one.

Weapons that are commonly banned in competitive MW2 rulesets:
`ak74u`, `peacekeeper`, `ak47classic`, `riotshield`, `onemanarmy`, `rpg`, `at4`,
`stinger`, `javelin`, `m79`, `throwingknife`.

---

## 6. Optional equipment limits

| dvar | weapons affected |
|------|------------------|
| `esl_allow_frag_grenade` | Frag grenade |
| `esl_allow_semtex` | Semtex |
| `esl_allow_throwingknife` | Throwing knife |
| `esl_allow_claymore` | Claymore |
| `esl_allow_c4` | C4 |
| `esl_allow_blastshield` | Blast shield |
| `esl_allow_tacticalinsertion` | Tactical insertion |
| `esl_allow_flash_grenade` | Flash grenade (tactical slot) |
| `esl_allow_smoke_grenade` | Smoke grenade (tactical slot) |
| `esl_allow_concussion_grenade` | Concussion grenade (tactical slot) |

The defaults allow frag/semtex/blast shield and all three tactical grenades, and
ban the throwing knife, claymore, C4 and tactical insertion.

### Substitution instead of deletion

A banned slot is **not** emptied, because the base script replaces an invalid
equipment/offhand value with the `CLASS_DEFAULT` entry of `mp/classtable.csv`
(which is always a frag grenade / concussion grenade). That would silently hand
out an item the server just banned.

Instead the mod substitutes the *first allowed* item of that slot:

| slot | substitution order |
|------|--------------------|
| equipment | semtex → frag → blast shield → claymore → C4 → throwing knife → tactical insertion → `specialty_null` |
| tactical | flash → smoke → concussion → `none` |

Only if *every* item of a slot is banned does the slot fall back to
`specialty_null`/`none`, and the base script's own default then applies — in that
case the server has effectively banned the whole slot anyway.

For a banned **weapon** the slot is emptied on purpose: the base script then
falls back to the default class primary (M4) / secondary (USP), which is always a
legal weapon as long as the default class weapon is not itself denied.

---

## 7. Search & Destroy match format

ESL plays S&D as a **24 round match: first to 13 round wins, sides switch after
the 12th round, 7.5 seconds to defuse**.

| dvar | value | pushed into the game type as |
|------|-------|------------------------------|
| `esl_sd_winlimit` | `13` | `scr_sd_winlimit` |
| `esl_sd_roundlimit` | `24` | `scr_sd_roundlimit` |
| `esl_sd_roundswitch` | `12` | `scr_sd_roundswitch`, then `level.roundswitch` |
| `esl_sd_defusetime` | `7.5` | `scr_sd_defusetime` |

The match ends on the win limit (the 13th round win) or on the round limit,
whichever arrives first: `isLastRound()` compares `roundsPlayed` against
`roundlimit - 1` and ends the match once round 24 is decided. With `winlimit 13`
and `roundlimit 24` a 12-12 match is therefore a **draw** — the round limit stops
it one round short of a 13th win. `esl_sd_roundlimit 25` (or `0`, which means no
round limit) gives a deciding 25th round instead. Note that it is the round limit,
not the win limit, that makes round 12 a *halftime* rather than a plain
intermission — `displayRoundSwitch()` only calls it halftime when
`roundsPlayed * 2` equals the round limit, and 12 * 2 = 24.

`esl_applySdRules()` runs synchronously from `_esl::init()`, which the S&D game
type reaches from the top of its own `main()` — before it registers its dvars and
before `updateGametypeDvars()` reads `defusetime` into `level.defuseTime`. The
block is skipped outside S&D and when `esl_sd_rules` is `0`.

### Why the round switch needs a second pass

`sd.gsc` registers the switch as
`registerRoundSwitchDvar( level.gameType, 3, 0, 9 )` — note the `9`. That helper
in `_utility.gsc` clamps the dvar into 0..9 and caches the clamped value in
`level.roundswitch`. The call happens *after* `_esl::init()`, so a plain
`scr_sd_roundswitch 12` would give a 9 round half: sides would switch at round 9,
and the screen would read "intermission" rather than "halftime" (9 * 2 is not the
round limit). `esl_patchRoundSwitch()` waits one second and writes the field
again; `checkRoundSwitch()` reads it only when a round ends, so the round 12
halftime still happens at the right time. No other code writes that field, and
nothing handles the `update_roundswitch` notify, so the correction holds for the
rest of the map.

---

## 8. Spectating: own team only

`esl_spectate_team_only` (default `1`) limits a dead player — and a spectator
without a team — to the players of their own team.

The stock setting is `scr_game_spectatetype 2` = "free": every team plus a free
camera. That makes a dead player a second pair of eyes for the enemy, and in S&D
the round often continues after they die (a planted bomb is still ticking), so it
is information the teams should not get.

Two things have to happen for the rule to hold:

1. `scr_game_spectatetype` has to be `1` ("team/player only"). Writing the dvar is
   not enough on its own, because `_tweakables::registerTweakable()` caches the
   value in `level.gameTweaks["spectatetype"].value` while the level is starting
   and `_spectating.gsc::setSpectatePermissions()` reads the cached copy.
   `esl_applySpectateRules()` therefore writes the dvar at level init *and*
   `esl_patchSpectatetype()` raises the cached copy one second later.
2. The game type's own exception has to be undone.
   `sd.gsc::checkAllowSpectating()` sets
   `level.spectateOverride[team].allowEnemySpectate` as soon as one whole team is
   dead — the stock "watch the other side while you wait" rule — and nothing
   clears it again, so from the first team wipe on, that team could watch the
   enemy for the rest of the map. `esl_keepSpectatingOwnTeam()` notices the flag
   (0.1 s poll), replaces both override structs and calls
   `_spectating::updateSpectateSettings()` to push the permissions to every player
   again. GSC has no member delete, which is why the structs are replaced rather
   than the fields cleared.

The cost of the rule is that a player whose whole team is dead watches their own
dead team-mates until the round ends. That is the price of not leaking the bomb
site; `esl_spectate_team_only 0` restores the stock behaviour.

---

## Enforcement timing

| Moment | Action |
|--------|--------|
| Level load | `_esl::init()` registers dvars, applies the native dvars, writes the S&D match format, starts the monitors. |
| Player connects | Stored classes are sanitised immediately. |
| Every spawn | Deathstreaks are stripped; stored classes are sanitised; if the loadout changed, it is rebuilt on the spot. |
| Every `esl_sanitize_interval` seconds (default 5) | Native dvars are re-asserted and all stored classes of all active players are re-checked. This closes the gap between a player editing a class and their next spawn. |

The spawn handler fires on `spawned_player`, which in Search & Destroy means once
per round, and once per life in respawn game types.
