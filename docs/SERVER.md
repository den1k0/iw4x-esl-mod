# ESL-MOD — running the dedicated server

Everything a server needs is in the archive: the rule set, the S&D match format
and the weapon rebalance live inside `z_eslmod.iwd`. The server config is
`mods\ESL-MOD\configs\ESL-MOD_server.cfg` (source copy:
[`config/ESL-MOD_server.cfg`](../config/ESL-MOD_server.cfg:1)).

## Turn it on and off

| What | Command |
|------|---------|
| Start | `tools\server-start.cmd` (double-click friendly) or `tools\server.cmd start` |
| Stop | `tools\server-stop.cmd` or `tools\server.cmd stop` |
| Status | `tools\server.cmd status` |
| Restart | `tools\server.cmd restart` |

`start` prints the process id, the map it loaded, whether the port is listening
and the join line. `status` shows the same for an already running server plus the
last sessions from the game log.

`stop` and `restart` save the ESL class archive on the way out: the classes a
player committed live in server dvars, which die with the process, so
[`tools/class-archive.ps1`](../tools/class-archive.ps1:1) reads them out of the
running server and writes `mods\ESL-MOD\configs\ESL-MOD_classes.cfg`, which the
server exec's at boot. A stop that bypasses these scripts — Task Manager, a crash
— skips the save and the classes are gone. See
[CONFIG.md § Classes](CONFIG.md#classes-across-a-map-change-and-a-restart).

The plain equivalent, if you would rather not use the scripts:

```bat
cd /d D:\Games\iw4x
iw4x.exe -dedicated +set net_port 28960 +set fs_game mods/ESL-MOD ^
         +exec configs/ESL-MOD_server.cfg +map_rotate
```

Two details that break the server if you get them wrong — a map loads and the
server still ends up unjoinable:

* **`-dedicated` is a launcher switch, not a dvar.** With only
  `+set dedicated 2` the engine starts the client UI, loads a map, drops back to
  the menu and repeats `InitGame`/`ShutdownGame` forever.
* **`exec` paths are resolved inside the mod folder**, so it is
  `configs/ESL-MOD_server.cfg`, never
  `mods/ESL-MOD/configs/ESL-MOD_server.cfg` — that form makes the engine wait a
  few seconds and print `couldn't exec`, leaving the server with no rotation.

## Who can join

1. **This PC** — in the console: `connect 127.0.0.1:28960`
2. **Other PCs on your LAN** — `connect <server-pc-ip>:28960`, e.g.
   `192.168.31.148:28960` (`ipconfig` shows the address). Windows Firewall
   already carries an inbound allow rule for `iw4x.exe` from the IW4x install:
   ```powershell
   Get-NetFirewallRule | Where-Object DisplayName -like '*IW4x*'
   ```
3. **Over the internet** — forward **UDP 28960** to this PC (see the next
   section). As soon as the port is reachable the server also shows up in the
   IW4x server browser, because it registers with the master list.

Everyone joining needs the same mod: `fs_game mods/ESL-MOD`. IW4x serves mod
files from the server, and because the ESL rules are enforced server side, a
client that has not downloaded them is still restricted.

## Opening the port for internet players

Two ways to get **UDP 28960** pointed at this PC.

### Option 1 — let the helper script do it (UPnP)

With UPnP enabled on the router:

```bat
tools\forward-port.cmd            REM show the current mapping and the router's WAN IP
tools\forward-port.cmd -Add       REM create the forward
tools\forward-port.cmd -Remove    REM remove it again
```

The script finds the router over SSDP, asks it for its WAN address, and adds or
refreshes the mapping through the router's own UPnP service. Nothing else on the
router is touched. If UPnP is switched off it says so and you use option 2.

If it reports *no gateway found* while UPnP is definitely enabled on the router,
the culprit is usually Windows, not the router: SSDP discovery works by a reply
coming **back** to an inbound UDP packet, and on a network Windows classifies as
**Public** the inbound SSDP rule is disabled by default — `NETDIS-SSDPSrv-In-UDP`,
profile `Domain, Public`, `Enabled False`. Either switch the network to
**Private** (Settings → Network & Internet → Ethernet → Network profile) or allow
it once from an **elevated** PowerShell:

```powershell
Set-NetFirewallRule -Name 'NETDIS-SSDPSrv-In-UDP' -Enabled True
```

Note also that games create their own UPnP mapping when hosting, so a router's
UPnP list can already show the game while a *fixed* forwarding rule is still
missing. Check the external port of that entry: if it is `UDP 28960` → this PC,
the port is open; if it is some random high port, add a rule for `28960` as below
(or tell players to use the port the router picked).

### A UPnP mapping can point at the wrong PC

This one fails silently and is worth checking before anything else, because the
router keeps forwarding to **whatever address the game had when it created the
mapping**. When this PC's DHCP lease changes — say from `192.168.31.147` to
`192.168.31.148` — the entry still reads `UDP 28960`, but the packets are handed
to an address nobody owns and simply vanish. The port *looks* forwarded and
nothing connects, and the server never appears in the IW4x list either, because
the master list cannot reach it.

So compare the entry's **internal IP** with this PC's current address:

```powershell
Get-NetIPConfiguration | Select-Object InterfaceAlias,IPv4Address,IPv4DefaultGateway
```

If they differ:

1. add a **manual** forwarding rule for `UDP 28960` → the address this PC has now,
2. delete the stale UPnP entry if the router offers a delete button,
3. give this PC a DHCP reservation so the address cannot move under it.

Deleting the stale entry is optional on most routers — a manual rule normally wins
over a UPnP one — and some router UIs only offer an on/off switch for UPnP rather
than a delete button.

On at least one Xiaomi firmware that assumption does **not** hold. With an old
UPnP mapping still in place, the internet-facing path kept using the stale UPnP
entry (pointing at a dead address) while a test from inside the LAN was answered
through the manual rule. The result looks impossible: loopback and LAN clients
work, every internet client times out, and the master list never shows the
server. The fix was to switch UPnP **off** and reboot the router, leaving the
manual rule as the only mapping.

So if you see that exact split — LAN joins fine, internet times out — suspect a
shadowing UPnP entry rather than the rule itself.

Confirmed on a Xiaomi router: with the stale entry in place, an internet client
timed out while the LAN worked; after switching UPnP off and rebooting the router,
the same client connected from a mobile-carrier address
(`Client 0 connecting ... from 46.131.85.181` in `console_mp.log`, followed by the
join in `games_mp.log`). Nothing else had to change.

Restarting the server also refreshes it on its own: IW4x asks the router for a
mapping again, this time for the address it is actually running on. That is the
quick test — delete the stale entry, run `tools\server.cmd restart`, and see
which address the router lists afterwards.

### Option 2 — add the rule by hand

1. Find the router's address — it is the default gateway:
   ```powershell
   Get-NetIPConfiguration | Select-Object InterfaceAlias,IPv4Address,IPv4DefaultGateway
   ```
   The web UI answers there, e.g. `http://192.168.31.1`.
2. Log in and open the port forwarding page. The name varies: **Port
   Forwarding**, **Virtual Server**, **NAT Forwarding** (Xiaomi / Mi routers:
   *Advanced settings → Port forwarding*; in the Mi WiFi app: *Toolbox → Port
   forwarding*).
3. Add a rule:

   | Field | Value |
   |-------|-------|
   | Name | `ESL-MOD server` |
   | Protocol | `UDP` (choose `TCP+UDP` if that is the only option) |
   | External / WAN port | `28960` |
   | Internal IP | this PC's LAN address |
   | Internal port | `28960` |

4. Save, then restart the server: `tools\server.cmd restart`.

### Give the machine a stable LAN IP first

`Get-NetIPConfiguration` also reports whether the address is from DHCP. If it is,
the router can hand out a different one after a reboot and the forward would then
point at nothing — add a DHCP reservation / static lease for this PC in the
router (Xiaomi: *Advanced settings → DHCP static IP binding*) or give the PC a
fixed address.

### "My server is not in the browser any more"

This is what that drift looks like from the player's side, and it is worth
recognising because nothing in the game says "your port forward is stale":

* the server is running, players already connected can stay, `tools\server.cmd status`
  says it is listening, `http://127.0.0.1:28960/info` answers
* the server even prints `Sending heartbeat to master: dp.iw4x.io:20810`
* but the server browser shows nothing to click, and internet players cannot join

The address the router forwards 28960 to is the one the PC had when the rule was
created. After a DHCP change the PC answers on a different address, so nothing
answers the master (and nothing answers players) — the server is simply not
listed. The same happened once with a UPnP mapping left behind by the router.

One command collects the whole picture:

```powershell
powershell -NoProfile -File tools\dev\check-master-list.ps1
```

It prints this machine's IPv4 addresses (the forwards must point at one of them),
the public IP, whether `/info` and `/list` answer, and whether the server appears
in the list the IW4x client last fetched — the same data the browser draws, read
from `<game>\players\server_cache.json`:

```
== this machine ==
  192.168.31.147/24  Ethernet  (Dhcp)
  public IP: 91.146.92.67

== server ==
  /info ok    : ^2ESL-MOD^7 | S&D | 24 rounds
  map         : mp_favela   gametype: sd   players: 0/18
  /list ok    : z_eslmod.iwd  4978845 bytes  sha256 39537599E74CC71D...

== master list (as cached by the IW4x client) ==
  age         : 0.3 minutes, 125 servers
  RESULT      : LISTED
    91.146.92.67:28960  ^2ESL-MOD^7 | S&D | 24 rounds
```

To fix it: in the router, point the **UDP and TCP 28960** rules at the address
this machine actually has, then add a DHCP reservation for it so it cannot move
again. In the meantime a local player can always get in with
`connect 127.0.0.1:28960` (same PC) or `connect <LAN IP>:28960`, both of which
stay inside the network and never touch the router.

### "UDP 28960 is already in use" — the client and the server on one PC

The game client is `iw4x.exe` too, and it binds UDP 28960 at startup exactly like the
dedicated server does. Two programs cannot share one UDP port, so whichever starts first
owns it and the other reports the port as taken:

```
ESL-MOD server: starting (pid 6396)
UDP 28960 is already in use by another program - the server may fail to bind.
```

`tools\server.cmd status` names the holder, which is the part that matters:

```
Port    : NOT listening - UDP 28960 is held by the game client (pid 22148)
```

A server in that state is up but **deaf**: nobody can join it, and the port forwarded by
the router leads to the client's socket rather than to the server. Two ways out:

* **close the game before starting the server** — `tools\server.cmd start`; or
* **give the client a port of its own**, which is what you want if you play and host on
  the same machine. Start the game with

  ```
  +set net_port 28961
  ```

  (the launcher's extra-arguments field, or a shortcut with that appended). The client
  still connects out to `28960`; only its own listening socket moves, so it cannot
  collide with the server again.

### Check for a second router in front

Some fibre and DSL setups leave the ISP's modem in router mode ahead of your own
router, and then forwarding on one device is not enough. Compare the router's WAN
address (its status page, or the `router WAN IP` line that
`tools\forward-port.cmd` prints) with the address the internet sees:

```powershell
Invoke-RestMethod https://api.ipify.org
```

If the two differ, the outer device is doing NAT as well: forward there too, or
put your router into bridge / DMZ mode.

### Telling people where to connect

Friends can either find the server in the **IW4x server browser** (the console
prints `Sending heartbeat to master: dp.iw4x.io:20810` once it is reachable) or
join straight away with `connect <your public IP>:28960`. Home connections
usually get a changing public IP, which is another reason to let the browser do
the work for them.

The port is now open to the internet, so change `rcon_password` in
`ESL-MOD_server.cfg` from the default before you leave it running.

If a LAN player cannot connect while `127.0.0.1` works, the network may be
classified **Private** while the IW4x firewall rule only covers **Public**. Fix
it from an **elevated** PowerShell:

```powershell
New-NetFirewallRule -DisplayName "IW4x ESL-MOD server" -Direction Inbound `
    -Protocol UDP -LocalPort 28960 -Action Allow
```

## Logs

| File | Contents |
|------|----------|
| `mods\ESL-MOD\logs\games_mp.log` | Game log: joins (`J;`), kills (`K;`), round and game start/end. |
| `mods\ESL-MOD\console_mp.log` | Engine console: map loads, config execs, errors. |

## What "stop" does

It ends the dedicated process. Classes a player saved live in playerdata, so
nothing important is lost beyond the round in progress; when the last player
leaves, the server shuts the game down on its own (the log then shows
`ShutdownGame:`).

Only the **dedicated** process is touched. Your game client is also `iw4x.exe`,
so the scripts look for `-dedicated` on the command line and stop nothing else —
hosting and playing on the same PC works.

## Sending commands to the server (rcon)

The dedicated server has no console window, so commands go over IW4x's rcon on the
game port:

```bat
tools\rcon.cmd sv_hostname            REM read a dvar - proves the connection works
tools\rcon.cmd fast_restart           REM end the match, restart the same map
tools\rcon.cmd map_rotate             REM end the match, load the next map
tools\rcon.cmd map mp_terminal        REM end the match, jump to a map
tools\rcon.cmd kick <player>
tools\rcon.cmd tempBanUser <player>
```

The password is taken from `rcon_password` in
`mods\ESL-MOD\configs\ESL-MOD_server.cfg`.

Four things worth knowing:

* **There is no command that ends a single round.** The engine's granularity is
  the match: `fast_restart` replays the same map, `map_rotate` and
  `map <name>` move to another one. A round-only end would have to be a mod
  feature (the game type's round end is `sd_endGame()` /
  `_gamelogic::endGame()`).
* **Silence is not failure.** IW4x only answers when a command produces output:
  `sv_hostname` answers, `fast_restart` does not. `tools\rcon.ps1` says so
  instead of pretending the command failed.
* The protocol is IW4x's own: `FF FF FF FF` + `rcon <password> <command>` + NUL
  sent to the game port over UDP, answered with `FF FF FF FF` + `print "<output>"`.
  `tools\rcon.ps1` implements that, so nothing else (launcher remote console,
  extra tooling) is needed.
* **Typing a command in game needs the `/rcon` prefix** - `/rcon map_rotate`, not
  `map_rotate`. Without it the line goes to the client's own console and nothing
  is ever sent to the server, which looks exactly like "the command did nothing"
  or "the rotation is stuck".

## Changing the server

Edit `mods\ESL-MOD\configs\ESL-MOD_server.cfg` and restart (or edit
`config\ESL-MOD_server.cfg` in the repository and run `tools\install.cmd`, which
copies it into place again).

| Setting | dvar |
|---------|------|
| Name in the browser | `sv_hostname` |
| Port (must match the router and firewall) | `net_port` |
| Player slots | `sv_maxclients` |
| Remote console password | `rcon_password` |
| Which maps, in which order | `sv_mapRotation` |
| Pick the next map at random | `sv_randomMapRotation` (1) |

`sv_randomMapRotation 1` is enough for a random next map - it was verified on a
live server, two `map_rotate` commands in a row went `mp_terminal` ->
`mp_favela` -> `mp_crash_tropical` while the rotation list itself stayed
unchanged. The mod does not touch the rotation, so nothing can fight the
engine's own randomiser.

The server's live settings are also served by the game server itself - handy to
confirm a config actually applies:

```powershell
Invoke-WebRequest http://127.0.0.1:28960/info
```

That returns JSON with `sv_hostname`, `sv_maxclients`, `scr_game_allowkillcam`,
`scr_team_fftype`, the map rotation and everything else the server advertises.

Every map named in `sv_mapRotation` must exist as a `zone\*.ff` in the install —
a missing one stops the rotation. To start on a single map instead:

```bat
tools\server-start.cmd -Map mp_terminal
```

Rule switches (no perks, no killstreaks, attachment / equipment limits, weapon
denylist) and the S&D format live in `ESL-MOD.cfg` and `ESL-MOD_sd.cfg` in the
same folder — see [docs/CONFIG.md](CONFIG.md).


## Giving the mod to players

A client without the mod cannot join. IW4x detects the server's mod and fetches
it over **HTTP on the game port** (`src/Components/Modules/Download.cpp` in
`iw4x/iw4x-client`):

1. it asks the game server for the mod list:
   `GET http://<server>:28960/list` for mods, `/map` for usermaps
2. the server answers with a small JSON manifest - on this setup:

   ```json
   [{"hash":"86E9418B...","name":"z_eslmod.iwd","size":4977706}]
   ```

3. it downloads each entry, either from the game server itself
   (`GET http://<server>:28960/file/z_eslmod.iwd`) or, when `sv_wwwDownload` is
   `1`, from `sv_wwwBaseUrl` instead. HTTPS is refused
   (`HTTPS not supported for downloading!`), and the client takes both dvars from
   the server info, so they have to be published to clients - the mod does that
   in `esl_publishDownloadInfo()`.

The trap is step 1: it is **TCP**. Forwarding only UDP 28960 (which is all the
game connection needs) leaves the client with `Failed to download the mod list!`
while **not a single request reaches the machine** - nothing in the game log,
nothing in any web server log, which makes it look like a client-side problem.

So the router needs **TCP 28960 in addition to UDP 28960**. With
`sv_wwwDownload 0` (the default in `ESL-MOD_server.cfg`) that is the entire
requirement: the game server serves its own mod files.

Check the endpoint from the server PC:

```powershell
Invoke-WebRequest http://127.0.0.1:28960/list
```

### Handing out a zip instead

If you would rather not open another port, or a player cannot use the download:

```bat
tools\pack-mod.cmd
```

`build\ESL-MOD.zip` contains `mods\ESL-MOD\...`. Players extract it into their
IW4x folder, select **ESL-MOD** in the launcher and join.

### Offloading the transfer (sv_wwwDownload 1)

Setting `sv_wwwDownload 1` together with
`sv_wwwBaseUrl "http://<host>:<port>"` moves only the *file transfer* to another
HTTP server; `tools\publish-mod.cmd -Serve` stages and serves one. The list still
comes from the game server on TCP 28960, so that port has to be open either way,
and the base url needs its own TCP port open too. Worth it only if you expect
many new players at once.
