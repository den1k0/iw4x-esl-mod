# ESL-MOD — the dedicated server as a Linux container

A container that runs the ESL-MOD **IW4x dedicated server** on Linux.

`iw4x.exe` is a 32-bit Windows binary, so the server runs under **Wine** inside
the image, launched with the same command line [`tools/server.ps1`](../tools/server.ps1:184)
uses on Windows:

```
wine iw4x.exe -dedicated +set net_port 28960 +set fs_game mods/ESL-MOD \
     +exec configs/ESL-MOD_server.cfg +map_rotate
```

The image carries the **mod**; the **game** is not in it. IW4x and the Modern
Warfare 2 data are copyrighted and are expected to be mounted at `/game`.

---

## What is in the image

| Path | Content |
|------|---------|
| `/opt/esl-mod/z_eslmod.iwd` | The packed mod. **Built on the host** ([`build/z_eslmod.iwd`]). |
| `/opt/esl-mod/mod.ff` | The map-vote preview materials (`third_party\sesh_server_v2`, unmodified). |
| `/opt/esl-mod/configs/` | `config/` — the server, rules and S&D configs. |
| `/opt/esl-mod/docker/` | This folder's scripts (entrypoint, rcon helper). |
| `/game` | The IW4x installation, mounted at runtime. |
| `/wine` | The prepared 32-bit Wine prefix. |

## Before you build: build the mod

The mod is **not** built inside the image. The repository ships the scripts, but
packing them needs the same tooling it uses on Windows (`tar.exe` for IW4x's
zip-based `.iwd`, and the unlinked base scripts under `.tmp_reference\`), so the
supported path is to build it where the project is developed:

```bat
tools\build.cmd
```

That writes `build\z_eslmod.iwd`. The Docker build copies exactly that file, so
`docker build` fails up front if it is missing.

## Build the image

From the repository root:

```bash
docker build -f docker/Dockerfile -t esl-mod-server .
```

or let Compose do it (the context is the repository root, so run it from there):

```bash
docker compose -f docker/docker-compose.yml build
```

## Put the game in place

Create `docker/game/` and copy a working IW4x installation into it, so that
`docker/game/iw4x.exe` exists — the same folder you would pass to
`tools\install.cmd` on Windows:

```
docker/
└── game/
    ├── iw4x.exe
    ├── main/          the Modern Warfare 2 data
    ├── zone/          the .ff files (the maps in sv_mapRotation live here)
    └── ...
```

## Run it

```bash
docker compose -f docker/docker-compose.yml up -d
```

Then follow the deployment as usual:

```bash
docker compose -f docker/docker-compose.yml logs -f
```

A healthy start prints `Server: mp_<map>` and `Sending heartbeat to master`
inside `docker/game/mods/ESL-MOD/console_mp.log`.

### With plain docker

```bash
docker run -d --name esl-mod-server \
    -p 28960:28960/udp -p 28960:28960/tcp \
    -v "$PWD/docker/game:/game" \
    esl-mod-server
```

### Ports

| Port | Why |
|------|-----|
| `28960/udp` | The game connection. |
| `28960/tcp` | IW4x's HTTP endpoint (`/list`, `/file/<name>.iwd`) — a client without the mod fetches it here. Without this the client reports *Failed to download the mod list*. |

Forward both on the router for internet players, exactly as
[docs/SERVER.md](../docs/SERVER.md) describes for the Windows server.

## Configuration

Every setting is an environment variable on the service:

| Variable | Default | Meaning |
|----------|---------|---------|
| `NET_PORT` | `28960` | Game port. Must match the mapping and the config. |
| `FS_GAME` | `mods/ESL-MOD` | The mod folder (the engine's `fs_game`). |
| `SERVER_CFG` | `configs/ESL-MOD_server.cfg` | Config exec'd at boot, resolved **inside `fs_game`**. |
| `MAP` | *(empty)* | Start on one map instead of `+map_rotate`. |
| `RCON_PASSWORD` | *(from the cfg)* | Overrides `rcon_password` from the config. |
| `EXTRA_ARGS` | *(empty)* | Anything else, e.g. `+set sv_lan 1`. |
| `USE_XVFB` | `1` | Start Xvfb when there is no `DISPLAY`. |
| `CONFIG_DIR` | `/config` | Optional mount whose `*.cfg` files win over the image's. |

Edit the server settings the normal way — in `config/ESL-MOD_server.cfg` and
`config/ESL-MOD_sd.cfg` ([docs/SERVER.md § Changing the server](../docs/SERVER.md))
— then rebuild the image. To keep editing without rebuilding, mount the
repository `config` folder and change values there:

```yaml
    volumes:
      - ./game:/game
      - ../config:/config:ro
```

A directory mounted at `/config` is re-applied on every start, so a restart
picks up the new values.

## Sending commands (rcon)

The bundled `esl-rcon` is the Python counterpart of
[`tools/rcon.ps1`](../tools/rcon.ps1:1):

```bash
docker exec esl-mod-server esl-rcon sv_hostname     # read a dvar
docker exec esl-mod-server esl-rcon fast_restart    # same map again
docker exec esl-mod-server esl-rcon map_rotate      # next map
docker exec esl-mod-server esl-rcon "map mp_terminal"
docker exec esl-mod-server esl-rcon kick <player>
```

The password comes from `rcon_password` in the installed server config, so this
works out of the box. Silence is not failure: IW4x only answers when a command
produces output (`sv_hostname` answers, `fast_restart` does not).

## ESL classes across a restart

On Windows [`tools/server.ps1`](../tools/server.ps1:144) reads the class dvars
back out of the live server on the way out, so the classes survive. The
container does the same thing: on `SIGTERM`/`SIGINT` (which is what
`docker compose stop`/`down` sends) the entrypoint runs

```
esl-rcon --archive
```

before stopping the server. It writes
`/game/mods/ESL-MOD/configs/ESL-MOD_classes.cfg`, the file the server exec's at
boot — the identical result to `tools\server.cmd stop` on Windows. Keep the stop
grace period (default `30s`) long enough for it to finish.

A `docker kill` (SIGKILL) bypasses the entrypoint, so the classes are lost —
right, the same as killing the Windows server from Task Manager.

## Logs

| File | Content |
|------|---------|
| `docker/game/mods/ESL-MOD/console_mp.log` | The engine console: map loads, config execs, errors. |
| `docker/game/mods/ESL-MOD/logs/games_mp.log` | Joins, kills, round and game start/end. |

Both live inside the mounted `/game`, so they are ordinary files on the host.

## Health check

The image declares a health check against IW4x's own endpoint:

```
curl -fsS http://127.0.0.1:28960/info
```

`docker ps` then shows the container as `healthy` once the server answers, and
Compose can restart it if it stops responding.

## Notes and limits

* **Headless.** The container starts Xvfb because Wine creates windows even for
  a `-dedicated` server; there is no desktop in the image. Set `USE_XVFB=0` and
  provide your own `DISPLAY` if you already have an X server.
* **The MSVC runtime** (`vcrun2019`) is fetched by `winetricks` at image build
  time and needs network access then. If that step fails the build still
  succeeds, but the server may then need that runtime supplied another way.
* **Architecture.** The Wine prefix is `win32` because `iw4x.exe` is 32-bit. On
  an ARM host (e.g. Apple silicon, a Raspberry Pi) this needs x86 emulation,
  which the image does not set up.
* **Not the client.** This is the dedicated server only. The in-game
  create-a-class menus, the vote sound and the map vote are still delivered to
  players by the mod, but you cannot join from inside this container.
