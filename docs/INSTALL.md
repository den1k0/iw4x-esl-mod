# ESL-MOD — installation

## Requirements

* IW4x installed (`D:\Games\iw4x` in the examples below).
* For hosting: a working IW4x dedicated server, or the in-game host menu.
* Nothing else — ESL-MOD is raw script, UI and weapon files, no compiled `.ff`
  files and no mod tools required.

## 1. Build / obtain the archive

The repository ships the generated scripts, so you only need to re-pack them:

```bat
tools\build.cmd
```

This produces `build\z_eslmod.iwd`. The script refuses to build if the
`_globallogic.gsc` override is missing the `_esl::init()` hook, so a broken
package cannot be produced silently.

The archive holds the two patched scripts, the create-a-class UI, the example
configs and the bundled **weapon rebalance** (1194 `weapons/mp/...` files: the 1192
merged from the standalone `weapon_rebalance` mod, plus the **AK-74u** and the
**M40A3** ESL ships itself). The build takes the rebalance from
`third_party\weapon_rebalance\weapons.iwd`, so a fresh clone builds without a game
install — refresh that copy with `tools\dev\import_weapons.ps1` after editing the
rebalance. See [docs/WEAPONS.md](WEAPONS.md).

It also carries the vote sound: `soundaliases/esl_vote.csv` (the alias) and
`sound/esl/voting_short.wav` (the file it names), plus ESL's copies of IW4x's four
vote menus, which are what play it. See [docs/VOTING.md](VOTING.md).

## 2. Install

```bat
tools\install.cmd "D:\Games\iw4x"
```

which is equivalent to:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1 -Iw4xPath "D:\Games\iw4x"
```

Afterwards the game folder looks like this:

```
D:\Games\iw4x\
└── mods\
    └── ESL-MOD\
        ├── z_eslmod.iwd
        └── configs\
            ├── ESL-MOD.cfg
            └── ESL-MOD_sd.cfg
```

The examples live in a `configs` sub-folder on purpose — a `.cfg` sitting
directly in the mod folder could be picked up by the engine, and these are meant
to be exec'd deliberately.

Manual installation is also fine: create `mods\ESL-MOD\`, copy
`build\z_eslmod.iwd` into it and the two `.cfg` files from `config\` into
`mods\ESL-MOD\configs\`.

## 3. Load the mod

### In the launcher (client or listen server)

Select **ESL-MOD** in the IW4x launcher's mod list. The launcher sets
`fs_game mods/ESL-MOD` for you.

### Dedicated server

Start it with the `-dedicated` switch. A ready-made config is installed as
`mods\ESL-MOD\configs\ESL-MOD_server.cfg`:

```bat
cd /d D:\Games\iw4x
iw4x.exe -dedicated +set net_port 28960 +set fs_game mods/ESL-MOD ^
         +exec configs/ESL-MOD_server.cfg +map_rotate
```

Players join with `connect <server-ip>:28960` (`127.0.0.1` from the same PC). With
`sv_lan 0` the server also registers with the IW4x list.

Two things that are easy to get wrong:

* **`-dedicated` is a launcher switch, not a dvar.** With only
  `+set dedicated 2` the engine still starts the full client UI: it loads a map
  and immediately drops back to the menu, so the log repeats
  `InitGame`/`ShutdownGame` every few seconds and the server is never joinable.
  With the switch it comes up headless — `Server: mp_<map>`,
  `Sending heartbeat to master`, and none of the client-side menu errors.
* **`exec` paths are resolved inside the mod folder** (`fs_game`), so the argument
  is `configs/ESL-MOD_server.cfg`, never
  `mods/ESL-MOD/configs/ESL-MOD_server.cfg`. The longer form sends the engine
  looking for a rawfile that does not exist: it waits a few seconds, prints
  `couldn't exec`, and the server is left with no map rotation.

`fs_game` must be set **before** the map loads; a `map_rotate` is required for a
change to take effect on a running server.

### Day to day control

The repository ships wrappers around the launch line above:

| Action | Command |
|--------|---------|
| Start | `tools\server-start.cmd` or `tools\server.cmd start` |
| Stop | `tools\server-stop.cmd` or `tools\server.cmd stop` |
| Status | `tools\server.cmd status` |
| Restart | `tools\server.cmd restart` |

They read the config from the mod folder, report the process id, the map and
whether the port is listening, and stop **only** the `-dedicated` process — your
game client is `iw4x.exe` as well, so hosting and playing on one PC works. Full
operator guide, including who can join and what a router or firewall needs:
[docs/SERVER.md](SERVER.md).

### Clients joining a modded server

A client **must have the mod**. IW4x detects which mod the server runs and refuses
to continue without it: a client that does not have it fails with
`Failed to download the mod list`, because IW4x's automatic mod download needs an
HTTP file server configured on the server side (see [docs/SERVER.md](SERVER.md)).

The reliable way to hand the mod out is a zip:

```bat
tools\pack-mod.cmd
```

That writes `build\ESL-MOD.zip` containing `mods\ESL-MOD\...`. Players extract it
into their IW4x folder, select **ESL-MOD** in the launcher and join.

## 4. Verify

1. Load a map. The server console prints:
   ```
   [ESL-MOD] rule set loaded
   ```
2. Run `esl_debug 1` and change the map. The console prints the active rules.
3. In game, check that the perk and killstreak sections of create-a-class are
   disabled and that no killstreak icons appear.

## Updating

Re-run `tools\install.cmd`. The old archive is overwritten. Existing config files
next to it are replaced as well, so keep your own settings in a separate file if
you customised them.

Note: the mod folder path (`mods/ESL-MOD`) and the archive name (`z_eslmod.iwd`)
should stay as they are — the `z_` prefix makes sure the archive is mounted after
the base game's own iwd files.

## Uninstall

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File tools\uninstall.ps1 -Iw4xPath "D:\Games\iw4x"
```

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `[ESL-MOD] rule set loaded` never appears | The archive is not mounted. Check `fs_game mods/ESL-MOD` and that `z_eslmod.iwd` is inside `mods\ESL-MOD\`. |
| Perks still selectable in the menu | `scr_game_perks` was not `0`. Check `esl_no_perks` and `esl_rules_enable`, then run `scr_game_perks` in the console — it must read `0`. |
| A banned attachment still spawns on a weapon | The class was re-saved by a client after the check. Lower `esl_sanitize_interval` (e.g. `1`) and respawn; the mod corrects the loadout on spawn. |
| Killstreak menu still visible but no rewards are given | Expected for clients that do not run the mod: the server denies the rewards, only the menu is client side. |
| Script errors about `_esl` in the console | The build is incomplete — rebuild with `tools\build.cmd` and reinstall. |
| Mod does not appear in the launcher list | The mod folder must contain the `.iwd`; restart the launcher after installing. |

## Uninstalling without losing your settings

`esl_rules_enable 0` disables every rule while leaving the scripts loaded, which
is useful for testing a vanilla class setup on a modded server.
