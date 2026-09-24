# ESL-MOD — diagnostics: where IW4x keeps logs and crash evidence

IW4x has **no dedicated crash-log file**. When the game dies, the evidence ends up
in three different places, and only one of them is inside the game folder.

## 1. Inside the game folder

| Path | What it is | When it has content |
|------|-----------|---------------------|
| `<iw4x>\main\games_mp.log` | the engine console log for a **normal** (non-modded) session | only while the `logfile` dvar is `1` |
| `<iw4x>\mods\<mod>\logs\games_mp.log` | the engine console log for a session started with `fs_game mods/<mod>` | only while `logfile` is `1` |
| `<iw4x>\cache\launcher_<date>_<time>.log` | IW4x launcher log (updates, component sync, launch of `iw4x.exe`) | always |
| `<iw4x>\players\iw4x_config.cfg` | dvars saved on exit — its timestamp tells you the game shut down **gracefully** | always |
| `<iw4x>\userraw\console_mp.log` (+ `.00N` rotations) | the **client console** log — script compile errors, missing menus and unknown functions land here | always |

Script errors, unknown functions, missing assets and GSC compile errors all go to
`games_mp.log` — but **only if logging is enabled**. A mod session that produced a
0-byte `mods\<mod>\logs\games_mp.log` means logging was off, not that nothing
happened.

### Enabling script logging (do this before debugging)

```
set logfile 1
set developer 1
```

Put those lines in `iw4x_config.cfg`, or in a config you exec at startup, or pass
them on the command line:

```
iw4x.exe +set logfile 1 +set developer 1 +set fs_game mods/ESL-MOD
```

`developer 1` prints script errors on screen as well, so a failing spawn/consume
is visible immediately. After a session, read:

```
<iw4x>\mods\ESL-MOD\logs\games_mp.log
```

Things to look for in that file:

| Message | Meaning |
|---------|---------|
| `[ESL-MOD] loading` in the log | the hook ran: the mod's script is being loaded and executed |
| `Script compile error: ... unknown function ... esl_init` | the shipped script is incomplete — rebuild with `tools\build.cmd` |
| `Could not find script 'maps/mp/gametypes/_globallogic.gsc'` | the `.iwd` is not mounted, or an archive entry name is malformed |
| `script runtime error` / `uninitialised variable` | a bug in the ESL code; the line number is included. Everything except the two dvar writes runs in a thread precisely so this cannot abort level loading |
| `unknown dvar` | harmless, a typo in a config |

## 2. Windows side (this is where crashes/hangs actually land)

| Source | How to open it |
|--------|----------------|
| **Event Viewer → Windows Logs → Application** | filter for `Application Error` (id **1000**), `Application Hang` (id **1002**), `Windows Error Reporting` (id **1001**) |
| WER reports | `%LOCALAPPDATA%\Microsoft\Windows\WER\ReportArchive` and `\ReportQueue` |
| Crash dumps | `%LOCALAPPDATA%\CrashDumps` (only if dumps are enabled) |

`Application Error` = the process faulted (a real crash, with a faulting module).
`Application Hang` = the process stopped responding and Windows closed it. IW4x on
Windows 11 frequently logs a **hang on exit**, i.e. after the game already saved
its config — that is a UI-shutdown hang, not a mid-game crash, and it looks
identical in the log whether or not a mod is loaded.

## 3. One-shot collector

[`tools/dev/collect_crash_info.ps1`](../tools/dev/collect_crash_info.ps1:1) gathers
all of the above in one pass:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\collect_crash_info.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\collect_crash_info.ps1 -GamePath "C:\Games\iw4x" -RecentHours 6
```

It prints the launcher logs, every per-mod session log (flagging empty ones), WER
reports, dumps, the relevant event-log entries, and every file the game wrote in
the last N hours — the last part is usually enough to tell a clean shutdown
(config + stat files) from a crash (no config write, dump written).

### Reading the client console log

The per-mod `games_mp.log` frequently stays **0 bytes** even with `logfile 1`, so
it is not a reliable channel. The one that always has the diagnostics is the
client console log at `<iw4x>\userraw\console_mp.log` (rotated as
`console_mp.00N.log`). A failed script compile looks like this there:

```
[     26722] Script scripts/_aimassist.gsc loaded successfully.
[     26876] Error:
[     26876] ******* script compile error *******
[     26876] Error: bad syntax
[     26876] ************************************
[     26971] ********************
ERROR: script compile error
bad syntax
(see console for details)
********************
```

[`tools/dev/console_errors.ps1`](../tools/dev/console_errors.ps1:1) prints the
newest log with context around every error-looking line:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\console_errors.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\console_errors.ps1 -Tail 60
```

## 4. What was found on this machine

| Time (local) | Evidence | Mod loaded? |
|--------------|----------|-------------|
| 12:10:14 | Application Error (iw4x.exe) | no |
| 15:23:52 / 15:23:58 | Application Error + WER | no |
| 17:31:47 | Application Hang | no |
| 21:34:22 | Application Error + WER | no |
| 22:04:50 | Application Hang | no |
| 22:42:25 | launcher started `iw4x.exe`, `players\mods\esl-mod\iw4x.stat` written at 22:43:56 | **yes** |
| 22:44:06 | `players\iw4x_config.cfg` written → the game exited **gracefully** | yes |
| 22:44:09 | `mods\ESL-MOD\logs\games_mp.log` created, **0 bytes** (`logfile` was off) | yes |
| 22:44:35 | Application Hang (iw4x.exe 4.2.0.0) | yes |

Reading: the game ran for ~100 seconds with ESL-MOD, saved its config (a graceful
shutdown), and was then closed by Windows with a hang — the same pattern that
already occurred at 22:04:50, 17:31:47 and with application errors at 12:10 and
15:23, all **before ESL-MOD was installed** (22:33). No crash dumps were written.

## 5. Isolating whether ESL-MOD is involved

1. Enable logging (`logfile 1`, `developer 1`) and reproduce. Read
   `mods\ESL-MOD\logs\games_mp.log`.
2. If the log shows no script error but the game still hangs, disable the mod's
   logic without unloading it:
   ```
   set esl_rules_enable 0
   set esl_sanitize_interval 0
   ```
   `esl_rules_enable 0` stops every rule (no dvar writes, no playerdata writes,
   no threads doing work) while the scripts stay loaded. If the hang disappears,
   the mod is implicated; if it does not, it is not.
3. If you suspect the watchdog, `esl_sanitize_interval 0` limits the mod to a
   single check per connect and per spawn.
4. To rule the mod out completely, run with the mod folder renamed
   (`mods\ESL-MOD` → `mods\ESL-MOD.off`); nothing else in the game is changed by
   installing it, so the vanilla behaviour is exactly restored.

## 6. Case study: the "waiting for response" hang (solved)

Symptom: vanilla starts a private match fine; with ESL-MOD the loading screen
sits on *"waiting for response"* forever, and tabbing out kills the game.

How it was isolated — this is the method worth reusing, since it needs no
compiler and no log file. Each step ships the game's own `_globallogic.gsc` with
one thing added, and the only question asked is "loads or hangs?":

| # | Probe contained | Result | Conclusion |
|---|---|---|---|
| A | the base script, byte-identical | loads | raw `.gsc` overrides work at all |
| B | + a hook calling a print-only function | loads | inserting a call/function is fine |
| C | + a thread started from `init()` | loads | threads from init are fine |
| H | + only the two native dvar writes | loads | `setDvar` at init is fine |
| F | + the whole ESL implementation, never called | loads | **the code compiles**, no syntax/name errors |
| N | + only the class sanitiser, writes disabled | loads | reading playerdata is fine |
| K/L | + only `esl_registerDvars()` | loads | 40 new dvars are fine |
| **O** | + only the deathstreak guard loop | **crash** `0xC0000005` | **found it** |
| D/J | full implementation | hangs | consistent with O |

Root cause: the deathstreak guard wrote `self.pers["cur_death_streak"]` in a
4 Hz loop as soon as `connected` fired — i.e. **while the level was still
loading**. Writing player state at that moment faults the engine
(`Error: 0xC0000005`, access violation) or stalls the game type start, which the
client renders as "waiting for response".

Fix (all four are in the current build):

1. the guards wait for `spawned_player` before touching anything, so **no player
   state is written during loading**;
2. counter clamping became opt-in (`esl_deathstreak_clamp`, default `0`) and
   event driven instead of a loop;
3. deathstreaks are now neutralised by removing the perk on spawn (perk API only);
4. the class sanitiser no longer runs on `connected`, and the watchdog waits 10 s
   before its first pass.

Guidelines that follow from this:

* Never write `self.pers[...]` or `setPlayerData(...)` from a `connected` handler
  or from `_globallogic::init()`.
* Prefer writing from `spawned_player` / `death`, where the engine itself writes.
* Keep the synchronously executed part of the hook to `getDvar`/`setDvar` only.

The probe generator lives in
[`tools/dev/build_probes.ps1`](../tools/dev/build_probes.ps1:1) — it builds and
installs all of the probes above into `mods\ESL-PROBE-*`, which makes the whole
table above reproducible on any machine in a few minutes.

## 7. Case study: the GSC syntax errors hit while adding the in-game CAC

The generate step ([`tools/dev/build_payload.ps1`](../tools/dev/build_payload.ps1:1))
builds `build\payload\maps\mp\gametypes\_globallogic.gsc` by concatenating the
game's own script with `src\maps\mp\gametypes\_esl.gsc`. That concatenation is
where all three compile failures so far came from — none of them were in the ESL
rules themselves.

| `console_mp.log` says | Cause | Fix |
|---|---|---|
| `bad syntax: (file '...\_globallogic.gsc', line 1327)` | `self.closepopupMenu();` — a **dot** instead of a space. In GSC `self.x(...)` is field access; a method call is `self x(...)` | replaced every `self.<name>(` with `self <name>(` |
| `Script compile error: unknown function` | calling `maps\mp\gametypes\_esl::esl_init()` — the engine resolves a `namespace::func` by loading that **script file**, and `_esl.gsc` is never shipped on its own | single-file architecture: the ESL code is appended to `_globallogic.gsc`, `#include` lines dropped, and everything calls locally |
| `Error:` (no location) + `Error: bad syntax` | the callback redirect was applied to the **whole merged file** instead of the base part only, so the ESL body's forwarding calls became `self ::esl_menuClass( response );` | scope the substitution to the base text; `::name` is a **function reference**, legal in `level.class = ::esl_menuClass;` but not as the callee of a call |
| `unknown function: esl_pistolAllowsAttachments` | the helper was **called but never written** — `_globallogic.gsc` compiles as one unit, so this is a hard error and the mod does not load at all | define it, and let `tools\build.ps1` catch the whole class of mistake: step 3b collects every `esl_*` definition across the three generated scripts and fails the build for any `esl_*` that is called without one |
| `uninitialised variable 'class_num'` | one of the generated patches made `giveLoadout()` read the **local** `class_num`, which the copycat branch only ever writes as a field (`self.class_num = …`). GSC's flow analysis rejects a read on any path where the local was never assigned | read the field instead (`self.class_num`), and let the build pin the form: `tools\build.ps1` asserts the exact string `esl_isCacClass( self.class_num )` 13 times, so a patch that injects the local fails the build instead of the map load |

Rules of thumb for GSC, learned here:

* `self func()` to call, `self.field` to read/write a field — the dot form of a
  call is a parse error, not a runtime error.
* `::name` is a function *value* (used all over the stock
  `SetupCallbacks()`), it cannot be invoked as `x ::name( args )`.
* Put the `case` body on the line **below** the `case` label; the stock scripts
  never put a statement on the same line as `case`.
* Array literals are not allowed in `return [ ... ];` — assign to a variable
  with explicit indices and return it.
* A script the engine has to *load by name* must actually exist in the `.iwd`.
  Prefer appending to a script the engine already loads.

[`tools/dev/inspect_payload.ps1`](../tools/dev/inspect_payload.ps1:1) checks the
generated payload for exactly this class of mistake before the game ever runs:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\inspect_payload.ps1
```

It reports the first/last byte (BOM, missing final newline), the seam where the
ESL body was appended, brace/paren/`#include`/comment-block balance, and any
line using a same-line `case`, a brace on its own line, a `self.<name>(` call or
a dangling operator.

The build itself now refuses to produce an archive that will not compile:

| check | in | catches |
|---|---|---|
| entry list, hook presence, `#include` counts | [`tools/build.ps1`](../tools/build.ps1:79) | a payload that no longer matches the architecture |
| every called `esl_*` is defined | [`tools/build.ps1`](../tools/build.ps1:127) | `unknown function` at map load (`esl_pistolAllowsAttachments`) |
| no local is read before it is assigned | [`tools/dev/lint_gsc_locals.ps1`](../tools/dev/lint_gsc_locals.ps1:1) | `uninitialised variable` at map load (`attachOk`, `xmagsOk`) |
| same-line `case`, `self.<name>(`, comment inside a continued `#define` | [`tools/dev/inspect_payload.ps1`](../tools/dev/inspect_payload.ps1:1), [`tools/dev/diff_ui.ps1`](../tools/dev/diff_ui.ps1:1) | the menu-definition traps |

[`tools/dev/lint_selftest.ps1`](../tools/dev/lint_selftest.ps1:1) reintroduces the
known `attachOk` bug in a throwaway copy and asserts that the lint reports it, so
a clean lint run means something.

## 8. Reading the class-reset diagnostics

A round transition is the one place where the game can silently take the player's
class away, and there is nothing to breakpoint. ESL-MOD therefore prints plain
`println` lines — not `iprintln`, which only reaches the game chat and only when
`esl_notify` is on — straight into `console_mp.log`, so a single round says which
of the three possible losses happened:

| `console_mp.log` line | Reading |
|---|---|
| `ESL-MOD [spawn]: pers.class=… self.class=… type=… loadout=…` | the state **before** ESL-MOD touches anything. `type=-` → the class-type memory is gone; `loadout=NO-STORAGE` → the player's ESL storage is gone; a weapon other than the chosen one in `loadout` → the storage was rewritten |
| `ESL-MOD [spawn-done]: …` | the same values **after** the keep-and-rebuild step, so the two lines can be compared |
| `ESL-MOD: spawn class was 'X', restored to Y` | the game had put the class back to `X`; the spawn rebuilt `Y` |
| `ESL-MOD: rebuilding loadout from …` | `esl_reapplyLoadout()` ran. It also re-asserts `self.class`, which is the value `_playerlogic::spawnPlayer()` actually hands to `giveLoadout()` |
| `ESL-MOD: class N slot S weapon 'W' is not allowed - cleared` | the sanitiser rewrote the class the player is **currently** using |
| `ESL-MOD: class N attachment 'A' is not allowed - cleared` | same, for an attachment |
| `ESL-MOD: class N equipment 'E' is not allowed - reset to …` | same, for the lethal |
| `ESL-MOD: class N perkP 'SPEC' removed` | same, for a perk |
| `ESL-MOD: class N tactical 'T' is not allowed - reset to …` | same, for the tactical |

Read them all with:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\grep_console.ps1 -Pattern "ESL-MOD" -Context 1
```

The sanitiser prints are deliberately asymmetric: a rule change made mid-match
rewrites **every** stored class, but only a change to the class *in use* justifies
rebuilding the loadout and telling the player. Warning about a class the player is
not carrying reads as a bug ("the mod adjusted my class" with nothing different in
hand), which is why the other 17 classes are cleaned silently.

### The class diagnostics channel actually works now

`esl_log()` writes with `logPrint()`.  It used to call `logString()`, and that
builtin turned out to write **nowhere** on this setup: a whole session's worth of
class diagnostics was missing from `logs\games_mp.log`, while the engine's own
`D;` / `K;` / `Weapon;` lines — which come from `logPrint()` — were all there.
Until this was fixed, the mod's state could not be reconstructed after a match at
all, which is why a class report had no evidence to work from.

Two lines are now written unconditionally — one per level, one per player:

```
ESL-MOD v1.0 boot sd winlimit=13 roundlimit=24 roundswitch=12 defusetime=7.5 spectatetype=1
ESL-MOD join FELIX id=bbdb7963f59fc1ec guid=bbdb7963f59fc1ec xuid=...
```

The `boot` line pins down the rule set the match actually ran with (the dvars the
config asked for and the ones the mod enforced are not always the same thing), and
the version in front of it names the build that ran — the same number the server
name carries, see [Version](CONFIG.md#version).
The `id=` in the `join` line is the key that player's classes are stored under
(`level.eslStore[id]` and `level.eslType[id]`), and it is the thing to compare
first in any "my class changed"/"everyone's class changed" report: **two players
with the same `id=`, who are online at the same time, share their class storage**,
and then the watchdog hands one of them the other's class.
`esl_storeId()` prevents that (guid first, and a second user of an id gets an
`#<entitynumber>` suffix), so the log line is the proof: with two players
connected, no two `id=` values may be equal.

#### What it found (the "everyone's class changed" bug)

The first session that could be read back settled it — on this setup `getXuid()`
returns `"0"` for **every** client:

```
ESL-MOD join FELIX id=bbdb7963f59fc1ec guid=bbdb7963f59fc1ec xuid=0
```

The XUID was the *first* choice for the storage key, so the key was the string
`"0"` for all players at once. They shared `level.eslType["0"]` and
`level.eslStore["0"]`: the committed class type was simply whoever had committed
last, and the per-second watchdog (`esl_enforceClass()`) handed that type - and
its loadout - to everybody. That is the whole of "somebody picked a class and it
changed for everyone", and it also explains why it looked fine when the whole
team had been told to take the same class: the shared copy matched anyway.

With the key fixed, the same log also carries a line whenever a class comes back
from the archive after a map change:

```
ESL-MOD archive: specops restored (14 fields)
```

#### The archive id (why a class did not survive a restart)

The archive is keyed on the same guid, and it prints both ends of it:

```
ESL-MOD archive: sniper saved as esl_class_bbdb7963f59fc1ec_sniper
ESL-MOD archive: type sniper saved as esl_type_bbdb7963f59fc1ec
```

`<id>` has to be the **whole** guid, and it was not: the guid
`bbdb7963f59fc1ec` produced `esl_class_b_sniper`, one character, so two players
whose guids began with the same character shared one archive dvar and the second
one to commit a class overwrote the first one's.

The cause is an engine detail that is easy to get wrong, because **every** use of
it in the stock scripts is written in a way that fits both readings: `getSubStr`'s
third argument is an **end index**, not a length, so a one-character slice is
`getSubStr( s, i, i + 1 )`.

```
getSubStr( "abcdef", 0, 1 ) == "a"        "abcdef".size == 6
getSubStr( "abcdef", 1, 1 ) == ""         <- a length would give "b"
getSubStr( "abcdef", 1, 3 ) == "bc"       <- a length would give "bcd"
getSubStr( "abcdef", 0, 6 ) == "abcdef"
toLower( "AbCdEf" ) == "abcdef"
```

That was measured, not reasoned about — the one-off line it came from was

```
ESL-MOD probe len=6 p01=[a] p11=[] p13=[bc] p06=[abcdef] low=[abcdef]
```

printed at level start from `esl_init()`. The stock scripts never disambiguate it:
they either start at 0 (`getSubStr( self.name, 0, 3 ) == "bot"`) or pass the whole
size, and both readings agree there.

A dvar left over from that older format is harmless (nothing reads it any more)
but it is still saved and loaded at every boot, so it is retired by emptying it —
**an empty value is not saved**:

```
tools\rcon.cmd set esl_class_b_sniper ""
tools\rcon.cmd set esl_type_b ""
powershell -NoProfile -ExecutionPolicy Bypass -File tools\class-archive.ps1 -Prune
```

`-Prune` rewrites the file from a server that now has nothing to give; without it
the tool deliberately leaves the file alone rather than empty it.

#### Reading the log at all

`games_mp.log` is written through a buffer that the engine flushes when a level
**shuts down**, so a session that only ever got force-killed (`server.cmd stop`)
leaves nothing behind, and a running session shows nothing yet. `map_rotate` over
rcon flushes it, which is the cheap way to read what the current session wrote:

```
tools\rcon.cmd map_rotate
```

This is also why the class save runs *before* the stop: it is the same window in
which the server can still be asked anything.

## 9. Log lines that are benign in this setup

These turn up in `console_mp.log` on every run and do **not** mean the build is
broken — all of them were present in a session in which everything worked:

| line | why it is harmless |
|---|---|
| `Error: Could not load menu ui_mp\weaponinfo.menu` | [`weaponinfo.menu`](../src/ui_mp/weaponinfo.menu:1) is a macro-only file: it defines the `REF_*` / `STAT_*` names and is pulled in with `#include` from [`cac_ingame.inc`](../src/ui_mp/emzui/cac_ingame.inc:141). The stock `menus.txt` also lists it as a menu file, and loading a menu file that contains no `menuDef` always logs this. The file is byte-identical to ProMod's original, so this is not something ESL-MOD introduced |
| `Could not find menu 'playerdataread'` | stock IW4x, unrelated to the mod |
| no script output in **any** log | measured on this setup: GSC `println` reaches no file, `iprintln` only the client console (not captured), `logString` — an engine builtin used by the stock scripts and ProMod — produced nothing in `logs\games_mp.log`, and the client config does not archive our dvars. `iPrintLnBold` (on screen) and the engine's own `J;`/`K;`/`Weapon;` events are the only channels that can be observed, which is why the per-spawn state is printed on screen and the durable state is keyed so it can be reasoned about without a log |
| `Menu load error: ui_mp\emzui\cac_ingame.inc, line N: expected integer but found tokenReplacement` and the paired `unknown menu keyword ;` | present in **every** session in the log history (`.000` onwards), including the ones where the editor and all of its popups worked — the line numbers just move as the file is edited. Every popup `menuDef` uses `IMPROVED_POPUP_SETUP_ONOPEN`, which is defined by no file we or ProMod ship, so this is how this engine reports it; the menus still build |
| `Ignoring client command 'vdr' because of flood protection` | only matters when it appears in a burst while the editor opens — that is what the `wait` gaps and the synchronous publishing in `esl_pushAvailability()` are for |
| `Waited N msec for asset …` | precache timing, not script |

Anything not in that table is real. Note that ESL-MOD now prints its own state on
every spawn, so a **silent** log across a round transition means the hook did not
run at all, rather than that nothing happened.

## 10. What a mod cannot do: unlock everything for the players

Recorded so it is not attempted a second time.

Unlocks (weapons, attachments, camos, perks, challenges) live in each player's **own
profile**, and a server cannot write into another machine's profile. The one handle a
mod has on it is a console command run on the client, and the only place a script can
run one is the menu language — so the attempt was a menu with no items, `visible 0`,
whose `onOpen` was `exec "cmd unlockstats";` and `close self;`, opened on each player at
their first spawn. That is ProMod's own `clientcmd.menu` shape, and the menu did open
and run.

**The command is refused while a match is running** ("the command is not allowed while
playing"), which is the whole story: a player can only unlock from their own console,
outside a match, so there is nothing a *server* can do here. The carrier menu, the
`esl_unlockall` dvar and the two build guards that checked them were removed again.

The name matters if it is ever revisited: **`unlockall` is not a command in this build**
— sending it over rcon answers `Unknown command "unlockall"` — while `unlockstats` is a
literal in `iw4x.dll` next to the `setPlayerData` writes that do the unlocking.

Nothing in ESL-MOD depends on unlock state: the loadouts never consulted it
(`esl_isCacClass()` bypasses the stock `isItemUnlocked()` checks), so a locked profile
can still build and keep every ESL class.
