# ESL-MOD

A competitive rule-set mod for **IW4x** (Call of Duty: Modern Warfare 2, 2009).
Built for **Search & Destroy**, but it loads in *every* game type — nothing in the
mod is S&D specific, it only restricts what a player is allowed to bring into a
match.

The version is stated in exactly one place, [`version.txt`](version.txt:1): the build
writes it into the mod, and the mod puts it in the server name and in every session's
log line. To release, bump that file, run `tools\install.cmd` and restart the server —
see [Version](docs/CONFIG.md#version).

It also ships an **in-game create-a-class editor** (ProMod style, no trip to the
main menu) for three class types — assault, spec ops, sniper — with banned items
greyed out in the menu itself. See [docs/INGAME-CAC.md](docs/INGAME-CAC.md).

The **weapon rebalance** is bundled into the same archive — 1194 `weapons/mp/...`
definition files, the 1192 from the standalone `weapon_rebalance` mod plus the
**AK-74u** and the **M40A3** that ESL ships itself — so a single mod entry covers the
rules and the weapon behaviour together. See [docs/WEAPONS.md](docs/WEAPONS.md).

IW4x's **voting** (map restart, next map, change map, change gametype, kick) is silent
in the stock client. The mod forks IW4x's four vote menus so that issuing a vote plays
a short sound. See [docs/VOTING.md](docs/VOTING.md).

```
no killstreaks  •  no deathstreaks  •  no perks  •  restricted attachments
                  optional weapon + equipment limits
```

Everything is enforced **server side**. A player cannot bypass a rule by editing
their config, by saving a class before the rules were enabled, or by tampering
with the create-a-class menu: the server re-checks and re-applies the class.

---

## How it works

IW4x mods live in `mods/<name>/` and are plain `.iwd` archives (ZIP files). Any
file in the archive overrides the matching asset of the base game. As well as the
rule configuration, the user interface and the bundled weapon rebalance, ESL-MOD
overrides four of the game's own scripts:

| File | Purpose |
|------|---------|
| [`_esl.gsc`](src/maps/mp/gametypes/_esl.gsc:1) | The source of all ESL logic: rule configuration, class sanitiser, spawn enforcer, watchdog, and the end-of-match map vote. **Not shipped on its own.** |
| `maps/mp/gametypes/_globallogic.gsc` (generated) | The ESL entry point: the game's own file, plus one inserted `esl_init();` call and the whole of `_esl.gsc` appended below it. Every game type funnels through `_globallogic::init()`, which makes it the one game-mode-independent entry point. |
| `maps/mp/gametypes/_menus.gsc` (generated) | The game's script-menu dispatcher, with the class menus pointed at the ESL ones and their responses routed into the mod — see [docs/INGAME-CAC.md](docs/INGAME-CAC.md). |
| `maps/mp/gametypes/_class.gsc` (generated) | The game's class code, with the ESL loadouts kept out of the playerdata — see [docs/INGAME-CAC.md](docs/INGAME-CAC.md). |
| `maps/mp/gametypes/_gamelogic.gsc` (generated) | The game's end-of-match sequence, whose fixed 3 s / 6 s postgame wait is replaced by the map vote — see [docs/MAPVOTE.md](docs/MAPVOTE.md). |

Each of those four is a file the engine loads anyway. That is deliberate: patching a
script the engine already loads — rather than shipping a brand new script file —
removes any chance of a reference to a new file failing during level initialisation,
an unresolved script call aborts the game type and leaves the client hanging on
*"waiting for response"*.

### Where each rule is enforced

| Rule | Mechanism |
|------|-----------|
| **No killstreaks** | `scr_game_hardpoints 0` → the base script sets `level.killstreakRewards = 0`, so nothing is ever handed out. All three stored killstreak slots are also cleared. |
| **No deathstreaks** | Every deathstreak perk is removed on the spawn that follows (`_unsetPerk`), so no deathstreak can take effect. An optional, event-driven counter clamp is available with `esl_deathstreak_clamp` (off by default — see below). |
| **No perks** | `scr_game_perks 0` is native engine support: `_perks::validatePerk()` replaces every perk (equipment is kept) with `specialty_null`, and the stock class menu disables the perk rows. All stored perk slots are cleared as well. |
| **Restricted attachments** | Whitelist driven by the `esl_attach_*` dvars. A banned attachment is deleted from the stored class and the loadout is rebuilt immediately. |
| **Weapon / equipment limits** | Optional, via `esl_weapon_denylist` and the `esl_allow_*` dvars. |

Because `scr_game_perks` and `scr_game_hardpoints` are the *native* dvars the
stock create-a-class menu already honours, the perk and killstreak sections of
the menu are disabled by the game itself. Attachments and equipment are reverted
by the server, so a player who selects a banned item gets an on-screen notice
and the class is corrected — the menu will read `None` the next time it is
opened.

---

## Install

### Server / host

```bat
tools\install.cmd "D:\Games\iw4x"
```

Then load the mod on your server:

```
set fs_game mods/ESL-MOD
exec configs/ESL-MOD_sd.cfg
```

`exec` paths are resolved **inside the mod folder** (`fs_game`), so it is
`configs/...` and not `mods/ESL-MOD/configs/...` — the longer form is a rawfile
the engine never finds, and the rule dvars then silently stay unset.

For a headless server use the bundled
[`config/ESL-MOD_server.cfg`](config/ESL-MOD_server.cfg:1) plus the `-dedicated`
launcher switch:

```bat
iw4x.exe -dedicated +set net_port 28960 +set fs_game mods/ESL-MOD ^
         +exec configs/ESL-MOD_server.cfg +map_rotate
```

The `-dedicated` **switch** is the part that matters: with only
`+set dedicated 2` the engine still starts the client UI, loads a map and drops
back to the menu, so the server never becomes joinable.

Or skip the command line and use the bundled control scripts —
`tools\server-start.cmd`, `tools\server-stop.cmd` and `tools\server.cmd status` —
which launch the server with the settings in `config\ESL-MOD_server.cfg` and
never touch your game client. Operator guide, including who can join and what a
router or firewall needs: [docs/SERVER.md](docs/SERVER.md).

### Client

Put the archive in the same place and select **ESL-MOD** in the IW4x launcher's
mod list:

```bat
tools\install.cmd "D:\Games\iw4x"
```

Full details, verification steps and troubleshooting: [docs/INSTALL.md](docs/INSTALL.md).

---

## Configuration

All rules are plain dvars, editable at runtime — no rebuild needed:

```
set esl_no_perks            1
set esl_no_killstreaks      1
set esl_no_deathstreaks     1
set esl_attach_silencer     1
set esl_attach_acog         0
set esl_weapon_denylist     "ak74u,peacekeeper,riotshield"
```

> Never write player state (`self.pers`, `setPlayerData`) from a `connected`
> handler or from level init — doing so while the map is still loading crashes
> IW4x with `0xC0000005` and stalls the client on "waiting for response". That was
> this mod's original bug; the full post-mortem is in
> [docs/DIAGNOSTICS.md](docs/DIAGNOSTICS.md:106).

* Example ruleset: [`config/ESL-MOD.cfg`](config/ESL-MOD.cfg:1)
* Recommended S&D match settings: [`config/ESL-MOD_sd.cfg`](config/ESL-MOD_sd.cfg:1)
* Every dvar explained: [docs/CONFIG.md](docs/CONFIG.md)
* Rule-by-rule enforcement details: [docs/RULES.md](docs/RULES.md)
* In-game create a class: [docs/INGAME-CAC.md](docs/INGAME-CAC.md)
* The vote sound: [docs/VOTING.md](docs/VOTING.md)
* Crash logs / troubleshooting: [docs/DIAGNOSTICS.md](docs/DIAGNOSTICS.md)

---

## Build from source

The repository ships the generated scripts, so building only means re-packing:

```bat
tools\build.cmd          rem -> build\z_eslmod.iwd
tools\weapon-sheet.cmd   rem -> docs\weapon-stats.html   (the weapon stat sheet)
```

The build script verifies that the override still contains the `_esl::init()`
hook before packaging.

The shipped script is generated from an unlinked copy of the game's own file, so
it can never drift from the engine:

```
game's _globallogic.gsc  +  esl_init(); hook  +  src\...\_esl.gsc      ->  build\payload\...\_globallogic.gsc
game's _menus.gsc        +  the ESL class menus                        ->  build\payload\...\_menus.gsc
game's _class.gsc        +  the ESL class loadouts                     ->  build\payload\...\_class.gsc
game's _gamelogic.gsc    +  the map vote where the postgame wait was   ->  build\payload\...\_gamelogic.gsc
```

[`tools/dev/build_payload.ps1`](tools/dev/build_payload.ps1:1) does the
concatenation (dropping the `#include` lines, because the host file already
includes the same headers) and verifies the result. To regenerate the unlinked
base copy first, you need `Unlinker.exe` and the game files:

```bat
cd D:\Games\iw4x
Unlinker.exe --include-assets rawfile -o "<repo>\.tmp_reference\base" zone\russian\common_mp.ff
```

---

## Limitations

* The mod only takes effect where it is loaded, and clients that do not download
  the mod will not see the adjusted class menu — the server still enforces every
  rule for them.
* `g_gametype sd` is the recommended game type; the rules also apply to TDM,
  DOM, SAB, etc.
* Attachment/equipment bans are enforced at spawn. Between two lives a player can
  briefly *hold* a banned selection in the menu before the server reverts it.

## Repository layout

```
esl-mod/
├── src/                          readable ESL source
│   └── maps/mp/gametypes/
│       └── _esl.gsc              dvars, sanitiser, monitors
├── build/
│   ├── payload/                  generated: base script + hook + ESL code
│   └── z_eslmod.iwd              the packed mod
├── config/                       example server configs (not packed)
│   ├── ESL-MOD.cfg
│   └── ESL-MOD_sd.cfg
├── docs/
│   ├── INSTALL.md
│   ├── RULES.md
│   ├── CONFIG.md
│   ├── WEAPONS.md
│   ├── DIAGNOSTICS.md
│   └── weapon-stats.html         generated: tools\weapon-sheet.cmd
├── tools/                        build / install / server / stat sheet
└── .tmp_reference/               dev only, gitignored
```

`.tmp_reference/` holds scripts unlinked from the game files on the machine the
mod was developed on. It is used **only** to regenerate
`_globallogic.gsc` and is not required to build, install or run ESL-MOD.

## License

MIT — see [LICENSE](LICENSE).
