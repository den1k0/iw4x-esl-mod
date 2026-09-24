# ESL-MOD — bundled weapon rebalance

ESL-MOD ships a **weapon rebalance** inside `z_eslmod.iwd`. It started life as a
separate mod folder (`mods\weapon_rebalance\` with its own `weapons.iwd`); it is
now part of the ESL-MOD package, so **one mod entry in the launcher is enough**.

## Why it is merged rather than shipped next to the mod

* The archive contains **nothing but `weapons/mp/...` entries** — 1194 weapon
  definition files, no scripts, no UI, no configs. There is therefore no overlap
  with anything else ESL-MOD ships, no load-order question between two `.iwd`
  files, and no chance of the rebalance quietly overriding a file the ESL
  create-a-class menu depends on. (1192 of them come from the rebalance; the
  AK-74u and the M40A3 are ESL's own — see "The weapons ESL adds itself".)
* One archive is one thing to install, one thing joining clients download, and
  one thing to keep in sync.

The merge is otherwise bit-identical to the source archive: the build extracts
`third_party\weapon_rebalance\weapons.iwd` into the payload and re-packs it, and
`tools\build.ps1` fails if the entry count in the archive and on disk disagree, or
if any of its sample weapon files is missing from the packed archive. The files that
differ from the source archive are the ones in the ESL tweak list, plus the weapon
files ESL adds itself — see "ESL tweaks on top of the rebalance" below.

## How a weapon file works

Each `weapons/mp/<name>` is a plain text `WEAPONFILE\...` definition: damage
ranges, penetration, rate of fire, magazine size, ADS speed, recoil, attachment
tags. A mod overrides a weapon simply by shipping a file at the same path.

Attachments are separate files (`ump45_fmj_mp`, `ump45_silencer_xmags_mp`, …), and
every attachment combination has its own entry — which is why changing a handful
of weapons produces well over a thousand files. That is also why the rebalance is
merged wholesale instead of cherry-picking files: a weapon and its attachments
have to stay consistent with each other.

## What it changes

Summarised from `third_party\weapon_rebalance\changelog.txt`.

### Assault rifles
* All assault rifles: ADS movement speed `0.38` → `0.665`.
* FAMAS, SCAR-H, TAR-21, M16A4, AK-47: penetration `medium` → `large`.
* ACR: rate of fire `789` → `750`, but only on the bare weapon and the FMJ
  variant. ESL sets the whole family to `705` — see "ESL tweaks on top of the
  rebalance" below.
* F2000: less recoil (centerspeed `1500` → `1600`, gunkick pitch max `70` → `65`).
* AK-47: no longer gains extra penetration from the holographic sight.

### SMG
* UMP45: minimum damage `35` → `30`, penetration `large` → `medium`, magazine
  `32` → `25`.
* MP5: maximum damage `40` → `45`, penetration `small` → `medium`.
* P90: maximum damage `30` → `35`; no longer has the 1.75 sprint duration with
  extended mags.
* UZI: maximum damage `30` → `35`.

### LMG
* All LMGs: ADS movement speed `0.35` → `0.525`.
* RPD: slightly more recoil (centerspeed `1700` → `1600`, grip `2000`).
* M240: FMJ now increases penetration.

### Sniper
* Intervention: ADS time `400 ms` → `300 ms` and ADS out time `0.6` → `0.45`,
  but both only on the bare weapon and the FMJ variant; ADS idle `60` → `20`.
  ESL sets the whole family to `200 ms` in and `0.3` out (1.5x the in time) —
  see "ESL tweaks on top of the rebalance" below.
* WA2000: FMJ now increases penetration.
* MK14 EBR: loses the neck / upper torso damage multiplier (`1.1x` → `1x`).

### Pistols
* Desert Eagle: less recoil (centerspeed `600` → `1200`); more recoil when akimbo.
* Magnum: more recoil when akimbo.

### Shotguns
* SPAS-12: FMJ now increases penetration.

### Machine pistols
* TMP: magazine `15` → `25` (akimbo `25` → `40`), starting ammo `45` → `75`
  (akimbo `45` → `80`).
* G18: akimbo recoil increased (matching the PP2000 and TMP).
* M93R: akimbo recoil increased.

### Launchers
* AT4: max damage `155` → `110`, min damage `55` → `35`, starting ammo `1` → `2`.
* Thumper: max damage `155` → `110`.
* RPG-7: max damage `160` → `120`, min damage `60` → `40`.

### Attachments and equipment
* Grenade launcher: blast radius `300` → `200` units, minimum damage `25` → `20`.
* Stun grenade: throw speed reduced to the flash grenade's.

## ESL tweaks on top of the rebalance

A few weapon values are ESL's own decision rather than the rebalance's. They live
in [`src/weapons/weapon-tweaks.txt`](../src/weapons/weapon-tweaks.txt:1) instead
of in the weapon files, because the rebalance stays a third-party archive that
can be re-imported at any time:

```
<file pattern>|<dvar>[,<dvar>]|<value>[|<replace from>][|<keep>]
cheytac*_mp|adsTransInTime|0.2|0.3,0.4
ak47*_mp|locHead,locHelmet|1.6|1.4|1
```

* `<file pattern>` is a wildcard over the file names in `weapons\mp`, so
  `cheytac*_mp` covers the Intervention and its 20 attachment variants.
* `<dvar>` may name several dvars, which then always get the same value —
  `locHead,locHelmet` cannot drift apart that way. Every occurrence in every
  matching file is set: one weapon file can hold more than one variant, and each
  variant carries its own copy of the dvars.
* `<replace from>` lists the current values the rule converts. It exists because
  the source data is usually **not** uniform — the rebalance typically reached
  only some of a weapon's files, which is how the Intervention ended up with
  `0.3`/`0.4` and the ACR with `0.076`/`0.08` (see the changelog entries above).
  Omit it to convert anything that is not kept.
* `<keep>` lists values that are expected and deliberately left alone — the
  underbarrel shotgun weapon that lives inside every assault rifle's family of
  files has `locHead 1`, and `masada_shotgun_attach_mp` carries the shotgun's own
  `fireTime 0.33` rather than the rifle's.
* `tools\build.ps1` applies the list **after** extracting the rebalance (step
  2c) and fails when a pattern matches no file, when a matching file does not
  contain the dvar, when a value is neither the target, a source nor a kept one,
  or when a rule changes nothing at all. Each rule is then checked again inside
  the packed archive, so it cannot be silently lost.

The three failure modes are the shape of the bugs this file kept producing:
"the change only reached part of the family" (a rule whose source values moved),
a stale rule (nothing left to change) and a rule pointing at a file that is not
the weapon it thinks it is.

Current list:

| weapon | dvar | rebalance | ESL |
|--------|------|-----------|-----|
| Intervention (`cheytac*_mp`, 21 files) | `adsTransInTime` | `0.3` on the bare weapon, `0.4` on most attachment variants | `0.266` |
| Intervention (`cheytac*_mp`, 21 files) | `adsTransOutTime` | `0.45` on the bare weapon and FMJ, stock `0.6` on the other 19 | `0.4` (1.5x the in time) |
| Assault rifles (`ak47`, `m16`, `m4`, `famas`, `scar`, `tavor`, `fal`, `masada`, `fn2000` — 49 files each) | `locHead`, `locHelmet` | `1.4` on the rifle files, `1` on the `*_shotgun_attach_mp` file | `1.6` (the shotgun attachment stays at `1`) |
| Sniper rifles (`barrett`, `cheytac`, `m21`, `wa2000` — 21 files each, plus the two M40A3 files) | `locHead`, `locHelmet` | `1.5` on the four families; `3` on the M40A3 leftover and `4.5` on the `m40a3_mp` ESL ships | `2` |
| Intervention (`cheytac*_mp`, 21 files) | `locTorsoLower` | `1.1`, against `1.5` for the upper torso | `1.5` — one torso zone, and lethal |
| Pistols (`deserteagle*` — 6 plain files, `coltanaconda*` — 6 files) | `locHead`, `locHelmet` | `1.4` | `2` |
| Golden Desert Eagle (`deserteaglegold_mp`) | `locHead`, `locHelmet` | `1.4`, like the plain pistol it is a variant of | `3.33` — 100 / 30, so a headshot kills at every range of the curve. Its own rule runs before the `deserteagle*` one, which keeps `3.33` so it does not undo it |
| ACR (`masada*_mp`, 49 of the 50 files) | `fireTime` | `0.076` (789 rpm) on 47 files, `0.08` (750 rpm) on the bare weapon and FMJ | `0.0851` (705 rpm) |
| AK-74u (`ak74u_mp`, the file ESL ships itself) | `damage`, `minDamage` | `50`, `5` (ProMod's own values) | `40`, `30` — the UMP45's pair |
| MP5K (`mp5k*_mp`, 36 files) | `damage`, `penetrateType` | `45` / `medium` on the bare weapon and the FMJ variant only; `40` / `small` on the other 34 — so an ACOG or a silencer made the gun *weaker* than the bare one | `45` / `medium` on all 36 |
| UMP45 (`ump45*_mp`, 36 files) | `minDamage`, `penetrateType` | `30` / `medium` on the bare weapon, FMJ and silencer; `35` / `large` on the other 33 | `30` / `medium` on all 36 |
| UZI (`uzi*_mp`, 36 files) | `damage` | `35` on the bare weapon and FMJ only; `30` on the other 34 | `35` on all 36 |
| P90 (`p90*_mp`, 36 files) | `damage` | `35` on the bare weapon, FMJ and the seven extended-mags variants; `30` on the other 25 | `35` on all 36 |
| Kriss (`kriss*_mp`, 36 files: 27 plain, 9 silenced) | `maxDamageRange`, `minDamageRange` | `750` / `1000` on the plain files, `500` / `750` on the silenced ones — the game's own suppressor penalty | `900` / `1200` (23 m / 30 m) on the plain files, `650` / `900` (17 m / 23 m) silenced — the penalty kept between the two |
| Assault rifles (`ak47`, `m16`, `m4`, `famas`, `scar`, `tavor`, `fal`, `masada`, `fn2000` — 50 files each) | `adsMoveSpeedScale` | `1.75` on the bare file and the FMJ variant only, `1` on the other 48 — the ADS movement buff (`0.38` → `0.665` is ×1.75) was gone as soon as any attachment was taken | `1.75` on all of them. The M4 uses the `m4_*_mp` pattern so it does not swallow the M40A3, which keeps `1` |
| AK-47, M16A4, FAMAS, SCAR-H, TAR-21 | `penetrateType` | `large` on the bare file, FMJ and — on the AK, where the holographic sight always gave it — the seven `eotech` variants; `medium` on the other 39–47 | `large` on all of them, the underbarrel shotgun attachment stays `small` |
| F2000 | `adsViewKickCenterSpeed`, `hipViewKickCenterSpeed` | `1600` on the bare file and FMJ against `1500` on the rest, and the scoped groups keep their own offsets | `1600` plain, `1400` thermal, `1200` ACOG — the +100 on all three groups |
| F2000 | `adsViewKickPitchMax`, `hipViewKickPitchMax` | `70` on 47 files, `65` on three | `65` on all of them |
| M40A3 (`m40a3`, `m40a3_mp`) | `damage`, `minDamage` | `400` on the archive's singleplayer-style leftover, `70` on the `m40a3_mp` ESL ships | `70` on both |
| M40A3 (`m40a3`, `m40a3_mp`) | `playerDamage` | `220` on the leftover, `30` on the `m40a3_mp` | `30` on both |
| M40A3 (`m40a3`, `m40a3_mp`) | `adsTransInTime` | `0.4` on the leftover, `0.25` on `m40a3_mp` | `0.233` — a touch faster than the Intervention's `0.266` |
| M40A3 (`m40a3`, `m40a3_mp`) | `adsTransOutTime` | `0.6` on the leftover, `0.4` on `m40a3_mp` | `0.35` — a touch faster than the Intervention's `0.4` |
| M40A3 (`m40a3`, `m40a3_mp`) | `adsIdleAmount` | `20` on the leftover, `0` on `m40a3_mp` | `5` — a quarter of the Intervention's `20` |
| M40A3 (`m40a3`, `m40a3_mp`) | `adsIdleSpeed` | `0` on `m40a3_mp`, the leftover already `1.5` | `1.5` — the Intervention's |
| M40A3 (`m40a3`, `m40a3_mp`) | `locNeck`, `locTorsoUpper` | `2` on the leftover, `4.5` on `m40a3_mp` | `1.5` — the Intervention's value |
| M40A3 (`m40a3`, `m40a3_mp`) | `locTorsoLower` | `1` on the leftover, `4.5` on `m40a3_mp` | `1.4` — just under the Intervention's `1.5`, so a stomach hit survives |
| M40A3 (`m40a3`, `m40a3_mp`) | `locRightArmUpper`, `locLeftArmUpper`, `locRightLegUpper`, `locLeftLegUpper` | `4.5` on `m40a3_mp`, already `1` on the leftover | `1` — arms and legs take body damage |

`fireTime` is the time between shots in seconds, so a rate of fire is
`60 / fireTime`: `0.076` = 789 rpm, `0.08` = 750, `0.0851` = 705.

The sniper aim-down-sights times are the play-tested pair rather than the rebalance's:
the Intervention comes up in `0.266` s and the M40A3 in `0.233` s, each dropping out
of the scope in 1.5x its in time (`0.4` and `0.35`). The M40A3 is a touch faster on
purpose — with the damage difference below, that and the sway are what tell the two
rifles apart.

The `locTorsoLower` row is the one place where a hit location multiplier decides a
duel, because both sniper rifles fire at 70 damage and a player has 100 health:

| | neck, upper torso | lower torso | a stomach hit |
|---|---|---|---|
| Intervention | `1.5` | `1.5` | kills — 105 |
| M40A3 | `1.5` | `1.4` | needs a second shot — 98 |

That is the only hit-location difference between them, and it replaces the stock split
(1.5 upper, 1.1 lower on both), which made the same shot lethal or not depending on
which zone the hitbox happened to report.

`masada_shotgun_attach_mp` is left alone on purpose — it defines the *underbarrel
shotgun* weapon, whose only `fireTime` is the attachment's own `0.33`, not the
rifle's rate. `masada*_mp` matches it too, so that value sits in the rule's keep
list (the fourth field), and the build reports what it changed and what it saw:

```
tweaks  : masada*_mp fireTime = 0.0851  (49/50 file(s) changed, was: 0.076, 0.08, 0.080, 0.33)
```

Both splits mattered, and in the same way: the bare Intervention was the fast one,
so adding an ACOG, extended mags, a heartbeat sensor or a thermal scope made it a
third slower to *aim* and kept the stock `0.6` to drop out of the scope — the
rebalance's own changes only ever reached the bare weapon and the FMJ variant (and
its changelog does not mention `adsTransOutTime` at all). One value for each field
across the whole family keeps the weapon consistent: `0.2` in, and `0.3` out,
which is 1.5x the in time rather than the flat stock `0.6`.

### The M40A3 is held to the Intervention

This is the one weapon where the tweak list is almost the whole weapon. The M40A3 is a
sniper the class editor offers next to the Intervention, and the mod ships ProMod's file
for it (see "The weapons ESL adds itself"), which multiplies **every** hit location by
`4.5`. At `damage 70` that is `315` for a hit on an arm or a leg, so the rifle killed
with one shot anywhere on the body — not the sniper the Intervention is, and not the
choice the editor means to offer. Damage, multipliers and the aim-down-sights times are
therefore set to the Intervention's, and the drift of the scope to a quarter of it:

| location | ProMod's `m40a3_mp` | ESL |
|---|---|---|
| head, helmet | `4.5` | `2` |
| neck, upper torso | `4.5` | `1.5` |
| lower torso | `4.5` | `1.1` |
| upper arms, upper legs | `4.5` | `1` |
| lower arms, lower legs, hands, feet, `locNone` | `1` | unchanged |

The archive's own `weapons/mp/m40a3` leftover is converted as well — it starts from a
`3` / `2` / `1` spread rather than a flat `4.5`, which is why each rule names both
values it replaces:

```
tweaks  : m40a3* locHead,locHelmet = 2  (2/2 file(s) changed, was: locHead=3, locHead=4.5, locHelmet=3, locHelmet=4.5)
tweaks  : m40a3* damage,minDamage = 70  (1/2 file(s) changed, was: damage=400, damage=70, minDamage=400, minDamage=70)
tweaks  : m40a3* adsTransInTime = 0.2  (2/2 file(s) changed, was: 0.25, 0.4)
tweaks  : m40a3* adsTransOutTime = 0.3  (2/2 file(s) changed, was: 0.4, 0.6)
tweaks  : m40a3* adsIdleAmount = 5  (2/2 file(s) changed, was: 0, 20)
tweaks  : m40a3* adsIdleSpeed = 1.5  (1/2 file(s) changed, was: 0, 1.5)
tweaks  : m40a3* locTorsoLower = 1.1  (2/2 file(s) changed, was: 1, 4.5)
```

The aim-down-sights times are matched as well: `0.2 s` to bring the scope up and `0.3 s`
to drop out of it, the same pair the sniper block at the top of this file puts on the
Intervention, so the two snipers come up and go down identically. Nothing in the popup
reads them — they are here so the two choices in the sniper list feel like the same
class of weapon.

**Scope sway** is the one place where ESL gives the M40A3 deliberately *less* than the
Intervention rather than the same. ProMod's file zeroes the aimed idle pair
(`adsIdleAmount` and `adsIdleSpeed`, both `0`), so a scoped M40A3 held perfectly still
where the Intervention drifts — invisible at the hip, immediately obvious down a scope.
ESL gives it a quarter of the Intervention's drift, `20` → `5`, at the Intervention's own
speed `1.5`: a quarter as far, at exactly the same pace. (A quarter of the speed as well
— `0.375` — was tried first and reads as a slow sludgy crawl rather than a smaller
version of the Intervention's drift.)

That pair is the whole of the sway change: the `adsSway*` scales (`2` max angle, `6` lerp
speed, `0` pitch / yaw / horiz / vert) are already the Intervention's, and the hip values
stay ProMod's (`hipIdleAmount 30`, `hipIdleSpeed 1` against the Intervention's `15` / `5`)
because they drive the hip viewmodel, not the scope.

Deliberately **not** aligned: the bolt cycle, which is a rifle difference rather than the
damage question above. `m40a3_mp` rechambers in `1 s` against the Intervention's
`0.865 s` — 60 rounds per minute against the Intervention's 69. The footer used to print
that pair; it shows the penetration class instead now, but the two files kept the
difference.

To read a value back out of a built payload:

```bat
powershell -NoProfile -File tools\dev\weapon-dvar.ps1 -Dvar adsTransInTime -Filter cheytac* -Distinct
```

```
adsTransInTime over 21 file(s) matching "cheytac*":
  0.2  (21)
```

## The weapons ESL adds itself

Two weapons in the mod are not a rebalance of anything: the **AK-74u** and the
**M40A3** are shipped by ESL-MOD. Both popups have listed them since the menus were
imported from ProMod, ProMod is also where both weapon definitions came from, and the
rebalance archive has no `ak74u` file at all — so both entries used to be guns the
engine had nothing to give (picking the AK-74u handed out an M4).

* The files live in the repository at
  [`src/weapons/extra/ak74u_mp`](../src/weapons/extra/ak74u_mp:1) and
  [`src/weapons/extra/m40a3_mp`](../src/weapons/extra/m40a3_mp:1), and the build copies
  everything in that directory into the payload in step **2b2** — before the tweaks
  (2c) and before the stats table (2d), so both reach it. Every file in there must be a
  `WEAPONFILE`, or the build refuses it by name.
* The **AK-74u** gets its damage pair, its hit locations and one range:
  [`weapon-tweaks.txt`](../src/weapons/weapon-tweaks.txt:1) sets the pair to `40` / `30`
  (the UMP45's) instead of ProMod's `50` / `5`, brings the hit locations to the spread
  the game's other SMGs use (`1.4` head and helmet, `1` everywhere else — ProMod's file
  gave the *rifle* upper body: neck and upper torso `1.4`, lower torso `1.2`), and fixes
  `maxDamageRange`, which ProMod's file carried as **`1`**: one inch, so the weapon was
  sliding down the damage curve from 2.5 cm out instead of dealing its damage at range.
  Elsewhere it is ProMod's file as it came — 30-round magazine, `0.078 s` between shots
  (769 rpm), `minDamageRange` 38 m — because the ESL rules for assault rifles, snipers
  and pistols deliberately do not cover SMGs.
* The **M40A3** is shipped for the file name, not for the numbers: multiplayer loads
  `weapons/mp/<name>_mp` and the archive only has the bare `weapons/mp/m40a3`, a
  singleplayer-style leftover with `damage 400` that multiplayer never reads — which is
  why the entry used to hand out an M4. Its damage, its multipliers and its aim times are
  then held to the Intervention's, and its scope sway to a quarter of the Intervention's,
  see "The M40A3 is held to the Intervention" above.
* The archive therefore carries **1194** weapon files instead of 1192, and the build
  fails if either extra file is not in it.

## The stats the class editor reads

The in-game create-a-class editor shows what the selected weapon does (see
[INGAME-CAC.md](INGAME-CAC.md#weapon-stats-under-the-editor)). Those numbers do not come
from the stock `mp/statstable.csv`: that table holds 0–100 values for the menu bars, its
key is in column 4 instead of 0, and it describes the **stock** weapons, so every number
in it would be wrong for this mod.

The build generates them in step **2d** — *after* the extra weapons (2b2) and the tweak
list (2c), so they are read back out of the payload that is about to be packed:

```
stats   : 64 weapons -> esl_weaponStatLine() in _globallogic.gsc
```

What it writes is the body of `esl_weaponStatLineA/B`: one `case` per weapon, holding each
half of the line the editor draws, wording and `|` separators included. The two halves are
joined by `esl_weaponStatLineAll()` into the single line that appears under each slot's
name.

```
case "ak47": return "|DMG: 40 - 30  |Head: 1.6x";
case "ak47": return "|Range: 51 m  |Penetration: large";
```

**Why it goes into the script and not into a table.** A table was tried twice, and both
halves failed in game. **The engine cuts a table cell at a `|`**: a cell holding
`Primary | DMG: 40 - 30 | …` came back as column 1 = `Primary` and column 2 = the damage
pair, which is what "the stats only show Max dmg and Min dmg" turned out to be. And **a
plain cell drawn on its own rendered nothing at all** — the footer's values never
appeared while the literals beside them did. No table in the shipped data carries a `|`
or a `:` in a cell either. Script has no such rules, so the text is composed there and
reaches the menu as a client dvar, which the menu draws with `dvarString(...)`.

The values, in order:

| wording | value | source |
|---|---|---|
| `|DMG: 40 - 30` | maximum and minimum damage | `damage` / `minDamage` |
| `|Head: 1.4x` | head multiplier | `locHead` (`locHelmet` always carries the same value) |
| `|Range: 22 m` | the far end of the damage curve | `minDamageRange` × `0.0254` — the units in a weapon file are inches |
| `|Penetration: large` | what the bullet goes through | `penetrateType` — `none`, `small`, `medium` or `large` |

A magazine field is not in yet.

**Which damage field.** A weapon file carries two damage pairs and only one of them is
the one multiplayer uses:

| field | value on the AK-47 | used |
|---|---|---|
| `damage` / `minDamage` | `40` / `30` | **yes** — three shots at 100 health, and the pair the rebalance edits (the UMP45's `minDamage 35 → 30`) |
| `playerDamage` / `minPlayerDamage` | `100` / `30` | no — the singleplayer/AI values; its `100`, or the Deagle's `150`, would be a one-shot kill in multiplayer |

`Range` is the far end of the damage curve (`minDamageRange`), i.e. the distance at
which the weapon has dropped to its `minDamage`; `maxDamageRange` is where it starts
dropping.

The row key is the part of the file name before the first `_`, so all 21 files of a
weapon collapse into one row; `<base>_mp` is preferred as the file to read. A file
that has no `damage`, `minDamage` or `fireTime`, or whose `damage` is not positive
(the launchers, the killstreak weapons, the underbarrel shotgun attachment), is
skipped. The build fails if fewer than 20 weapons come out, so a broken extraction
cannot ship an empty table.

Current rows, for reference:

| key | damage | head | range | penetration |
|---|---|---|---|---|
| `ak47` | `40 - 30` | `1.6x` | `51 m` | `large` |
| `masada` (ACR) | `30 - 20` | `1.6x` | `58 m` | `medium` |
| `ump45` | `40 - 30` | `1.4x` | `22 m` | `medium` |
| `ak74u` | `40 - 30` | `1.4x` | `38 m` | `medium` |
| `cheytac` (Intervention) | `70 - 70` | `2x` | `127 m` | `large` |
| `m40a3` (M40A3) | `70 - 70` | `2x` | `127 m` | `large` |
| `deserteagle` | `50 - 30` | `2x` | `30 m` | `medium` |
| `coltanaconda` (Magnum) | `50 - 35` | `2x` | `32 m` | `medium` |

**The penetration class.** `penetrateType` is the field the engine uses to decide what
a bullet goes through, and it holds one of four values. The label is spelled out —
`|Penetration: large` — rather than abbreviated: `|Pen: large` shipped first and was read
as a truncated word instead of as a field name.

| value | files in the payload |
|---|---|
| `medium` | 442 |
| `small` | 350 |
| `large` | 340 |
| `none` | 62 |

All 1194 weapon files carry it, so no row is guessed at; a file that somehow had none
would show `-`. It replaced the rate of fire, which was the least useful of the four
numbers: how fast a weapon cycles can be heard, while "does this shoot through the wall
I am behind" is a property of the weapon in hand that nothing else in the editor shows.

The `fireTime` maths that produced the rate of fire — `cycle = max( fireTime,
rechamberBoltTime, rechamberTime if > 0.2 )`, with the bolt-action caveat that a
sniper's `fireTime 0.05` is not its real cycle — is in the repository history if the
number is ever wanted back. `fireTime` itself still gates the table: a file without it
(the launchers, the killstreak weapons, the underbarrel shotgun attachment) is skipped,
which is what keeps those rows out.

### Every entry in the editor resolves

Checked entry by entry against the table: the nine assault rifles (`ak47`, `m16`,
`m4`, `famas`, `scar`, `tavor`, `fal`, `masada`, `fn2000`), the six SMGs it lists
(`mp5k`, `ump45`, `kriss`, `uzi`, `ak74u`, `p90`), the two snipers (`cheytac`,
`m40a3`) and all five side arms (`beretta`, `usp`, `deserteagle`, `deserteaglegold`,
`coltanaconda`).

Two of them did not, until the mod started shipping a file for them: the `ak74u` (the
specops popup has listed it since the menus were imported, but the rebalance archive has
no ak74u file at all) and the `m40a3` (the archive has only the bare file, which
multiplayer never reads, while the editor asks for `m40a3_mp`). Both were weapons the
engine had nothing to give, and neither had a row to read. See
[the weapons ESL adds itself](#the-weapons-esl-adds-itself).

### Rows the editor cannot show, and files that share a row

The table is generated from the **weapon files**, not from the editor's lists, so it
also holds rows the editor can never show — `winchester1200`, an old shotgun, has files
and therefore a row and is simply not referenced by the editor's lists at all. Such a
row is harmless, and it is a reminder that the footer's numbers are the files' numbers
and nothing else.

The reverse case is the M40A3, which has two files and one row. `weapons/mp/m40a3` is
the archive's singleplayer-style leftover (`damage 400`, `playerDamage 220`, `3` head /
`2` neck / `1` limbs) and `weapons/mp/m40a3_mp` is the file ESL ships and multiplayer
loads. Both are keyed `m40a3`, the row is read from the `_mp` file (see the row key rule
above), and the tweak list gives the two files the same damage and multipliers, so the
row and the weapon agree whichever file gets read: before the mod shipped an `_mp` file
the row came from the leftover and read `400 - 400`.

## Relationship to the ESL rules

The two are independent and complementary:

* the **rebalance** changes what the weapons do,
* the **rule set** changes what a player may bring into the match
  (`esl_attach_*`, `esl_allow_*`, `esl_weapon_denylist`, no perks, no
  killstreaks).

Nothing in the rebalance needs a matching rule. It stays within weapons the rules
already allow — the UMP45 nerf is a typical league change and is a weapon file
edit, not a ban.

## Updating it

The build packs the repository copy, never the installed mod, so a fresh clone can
be built without a game install. After editing the rebalance in
`<IW4x>\mods\weapon_rebalance\`:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\import_weapons.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1
```

`import_weapons.ps1` refuses anything that is not a readable ZIP whose entries are
all under `weapons/`, and refuses an archive with suspiciously few files, so a
wrong or corrupt archive cannot reach the payload. It prints what it wrote:

```
Imported weapon rebalance:
  archive      : third_party\weapon_rebalance\weapons.iwd
  weapon files : 1192
  size         : 4823869 bytes
  sha256       : AF09659B27BEA04FA79734411B596A82415FE4AF461629E26F41E1BC3EFF5171
```

The separate `mods\weapon_rebalance\` folder is no longer needed by ESL-MOD — keep
it as the working copy you edit, or drop it. The shipped copy is the one under
`third_party\`.

## The weapon stat sheet

[`docs/weapon-stats.html`](weapon-stats.html) is the whole list as a spreadsheet: one row
per weapon with the damage pair, the curve ranges, the hit location multipliers, the
penetration class, the aim-down-sights pair, the rate of fire and the hits to kill per
hit location.

```bat
tools\build.cmd          rem  or tools\install.cmd - refreshes the payload
tools\weapon-sheet.cmd   rem  -> docs\weapon-stats.html
```

It reads `build\payload\weapons\mp` — the **tweaked** payload, i.e. the files the mod
actually packs — so it cannot drift from the match, but it does have to be run after a
build. The page prints that payload's newest file time, so a stale sheet is visible.

| column group | from | note |
|---|---|---|
| Damage Max / Min | `damage`, `minDamage` | the pair multiplayer uses, not `playerDamage` |
| Range Full / Min | `maxDamageRange`, `minDamageRange` | metres, 1 unit = 1 inch. Full is where the maximum damage holds, Min where it has dropped to `minDamage` |
| Multipliers | `locHead`, `locNeck`, `locTorsoUpper`, `locTorsoLower` | head and helmet always agree; the lower torso pair is what tells the two sniper rifles apart |
| Penetration | `penetrateType` | the same value the editor footer now shows |
| ADS In / Out | `adsTransInTime`, `adsTransOutTime` | seconds |
| RPM | computed | the cycle rule below |
| Hits to kill | computed | `3 &#8594; 4 @ 47 m` reads as "three hits kill up to 47 m, four beyond"; a plain number holds at every range |

**Hits to kill** use the model the file's numbers imply: 100 health, full damage up to
`maxDamageRange`, a straight drop to `minDamage` at `minDamageRange`, constant beyond,
and the hit location's multiplier on every shot. So the Intervention's torso reads `1`
(one shot at any range, 105 damage) while the M40A3's lower torso reads `2` (98 damage)
— exactly the difference those two rows exist to show. A boundary case is worth knowing
about: a Desert Eagle headshot is `50 × 2 = 100`, so one shot kills *only* within the
full-damage range and the sheet prints `1 &#8594; 2 @ 9 m` rather than `1`.

**The rate of fire.** `fireTime` alone is not enough and no single field is — what
limits a weapon differs per class:

```
cycle = max( fireTime, rechamberBoltTime, rechamberTime if > 0.2 )
```

`rechamberTime` is a generic `0.1` on almost every weapon (trusting it alone prints
`600` for everything), so it only counts when it is clearly a real cycle, and a bolt
action keeps its real one in `rechamberBoltTime` — the Intervention's `fireTime 0.05` is
1200 rpm while its bolt takes `0.865 s`. A semi-automatic whose `rechamberTime` is the
`0.1` filler therefore prints the fire cap its file implies, which is the honest answer:
what really limits it is the trigger.

**One trap, in the script.** Every value is parsed and printed with the **invariant**
culture. On a machine whose culture uses `,` as the decimal separator a plain
`[double]"0.266"` is `266` — a `0.085 s` fire time would come out as 1 round per minute.
Anything else that reads a weapon file has to do the same.

## Verifying

* `tools\build.ps1` prints `weapons : 1192 files, ...` for the rebalance itself, then
  `extra : 2 file(s) from src\weapons\extra (ak74u_mp, m40a3_mp) -> 1194 weapon files in
  the payload`, and lists `weapons/mp/* (1194 files)` in its entry summary. It fails the
  build if a sampled weapon file (`ump45_mp`, `mp5k_mp`, `famas_mp`, `deserteagle_mp`,
  `ak74u_mp`, `m40a3_mp`) is not inside the packed archive, if a rule's new value is not
  in it, and if the generated footer line for the M40A3 is not the Intervention's
  (`case "m40a3": return "|DMG: 70 - 70  |Head: 2x";`).
* The build writes `build\iwd-files.txt`, the exact entry list handed to the
  packer, if you want to diff what was shipped.
* `tools\weapon-sheet.cmd` regenerates [`docs\weapon-stats.html`](weapon-stats.html) out
  of that payload. It refuses to write a sheet with fewer than 20 weapons in it, so a
  broken extraction cannot publish a half-empty one.
* In game the quickest single tell is the **UMP45: magazine 25, not 32**.
