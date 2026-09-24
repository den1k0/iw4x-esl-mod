# ESL-MOD — end-of-match map vote

When a match ends the players pick the next map, instead of the engine drawing a
random entry out of `sv_mapRotation`.

## What the player sees

A menu with four cards: three candidate maps (preview image, name, vote count) and a
**Random Map** card. It opens a few seconds after the last round ends — that is
`esl_mapvote_delay`, so the round-end scoreboard gets its moment first — plays a sound
while it is up, and closes when the vote is over.

**Voting is by hotkey: `1`, `2`, `3` for the three cards and `4` for Random Map.**
The cards also take a mouse click and can be focused, but in the postgame there is no
cursor on screen and nothing starts out focused, so the hotkeys are what actually
works — they are menu-level `execKey`s, the same way every other in-game menu in this
mod is driven. The key has to be a **quoted** string (`execKey "1" { … }`, exactly as
in the game's own `changeclass_mw.menu`); unquoted, as the first version had it, the
key silently never fires. Voting again changes the vote (the last one counts); ESC
closes the menu, and the vote carries on without that player.

The layout is the one the `sesh_server_v2` mod uses — see
[Where the UI comes from](#where-the-ui-comes-from).

## How it works

```
match ends
   │  _gamelogic::endGame()       the game's own end-of-match sequence:
   │                             scoreboard, intermission, then the rotation
   ▼
esl_mapVoteEndgame()     replaces the fixed 3 s / 6 s postgame wait
   │  wait esl_mapvote_delay      the scoreboard gets its moment first
   │  esl_mapVoteRun()            three distinct maps drawn from esl_mapVoteMaps()
   │                             + "Random Map"
   │  publish  map_vote_id_0..2      the candidates (keys in tables\esl_mapvote.csv)
   │           map_vote_count_0..2   their vote counts
   │           map_vote_count_4      the random card's count
   │           esl_vote_timer        "Vote ends in N s"
   │  precacheMenu + openMenu on every player, one listener thread each
   ▼
cast_vote:<slot>        menu -> server, slot 0-2 = a candidate, 4 = random
   │
esl_mapVoteApply()      most votes wins, a tie is drawn at random
   ├─ a winner          -> setDvar( sv_mapRotation, "gametype <gt> map <map>" )
   └─ none / Random Map -> the server's own rotation is put back
   ▼
back in endGame()       level notify( "exitLevel_called" ); exitLevel( false );
                        the engine rotates, reading sv_mapRotation
```

| dvar | what it is |
|---|---|
| `esl_mapvote` | 1 (default) runs the vote, 0 leaves the random rotation alone |
| `esl_mapvote_delay` | seconds the scoreboard is left alone before the cards open, default 3, clamped to 0..30 |
| `esl_mapvote_time` | the window in seconds, default 15, clamped to 5..60 |
| `map_vote_id_<n>` | `map_vote_id_0`..`map_vote_id_2`: the candidate map names |
| `map_vote_count_<n>` | `0`..`2` and `4`: the vote counts |
| `esl_vote_timer` | the line under the menu title |

The first five are registered with `makeDvarServerInfo()`, so one `setDvar()` on the
server reaches every client — the cards are the same for everybody, and only the
highlight is local to a client. Slot 3 is unused on purpose: the slot numbers are the
ones sesh's menu uses, which makes the two easy to compare.

### Timing: the vote *is* the postgame

The engine rotates the map by itself when the postgame ends, reading `sv_mapRotation`
at that moment. When that moment is, is decided by the game's own end-of-match
sequence: `_gamelogic::endGame()` shows the scoreboard, puts the players into
intermission and then — after a fixed wait of 6 s, or 3 s on a one-round match — calls
`exitLevel()`, which is what makes the engine rotate.

That wait is the only place a vote could have lived, and it is far too short: a vote
running alongside it was cut off mid-count and the map went somewhere random, which is
what the first test showed ("the screen came up, it would not let me vote, and five
seconds later the map changed"). Holding the rotation instead, with `sv_dontrotate`,
turned out to be worse than the problem: the engine skips a rotation it is not allowed
to do and never comes back for it, so the level ended with no next map at all — the
server sat in the main menu and stopped answering, which is what
`Not performing map rotation as sv_dontRotate is true` followed by
`----- Server Shutdown -----` in `mods\ESL-MOD\console_mp.log` was.

So the fixed wait is **replaced** by the vote. `tools\dev\build_payload.ps1` patches
`_gamelogic.gsc` so that

```
	//logString( "game ended" );
	if( !nukeDetonated && !level.postGameNotifies )
	{
		if ( !wasOnlyRound() )
			wait 6.0;
		else
			wait 3.0;
	}
	else
	{
		wait ( min( 10.0, 4.0 + level.postGameNotifies ) );
	}

	level notify( "exitLevel_called" );
	exitLevel( false );
```

becomes

```
	maps\mp\gametypes\_globallogic::esl_mapVoteEndgame();

	level notify( "exitLevel_called" );
	exitLevel( false );
```

Everything the rotation depends on is therefore untouched: the map change is still the
engine's own `exitLevel()` call, and the vote only decides what `sv_mapRotation` holds
when it happens. Nothing in this mod sets `sv_dontrotate`, and nothing calls
`exitLevel()`.

The postgame is then exactly as long as the vote:

```
last round ends
   │  endGame() shows the scoreboard
   │  esl_mapvote_delay seconds of scoreboard   (3 by default)
   │  the cards, for esl_mapvote_time seconds   (15 by default, clamped to 5..60)
   │  the result: "Next map: <label>"
   └─ exitLevel() -> the engine rotates, reading sv_mapRotation
```

`esl_mapvote 0` skips the vote but still waits 3 s, so turning it off does not make a
match end the instant it ends.

### If the fork is not loaded

`esl_mapVoteWatch()` is the safety net, and the one line that makes this debuggable: at
boot it writes to `mods\ESL-MOD\logs\games_mp.log`

```
ESL-MOD mapvote: endGame() hook loaded, the vote runs the postgame
```

If it says **WARNING - the patched `_gamelogic.gsc` is not loaded** instead, the install
is running the stock end-of-match code (a `maps/mp/gametypes/_gamelogic.gsc` missing
from the archive, or another mod's copy of it winning the load order). The vote then
falls back to a short one that fits the stock postgame: `level.postGameNotifies` is
raised to stretch that sequence to its 10 s maximum, and the vote runs with 1 s of
delay and a 5 s window.

### What the vote does *not* do

* It does not decide anything when **nobody votes**, or when **Random Map** wins: the
  rotation goes back to what `config\ESL-MOD_server.cfg` describes, i.e. the engine
  picks a random entry as before. It has to be put back explicitly — a vote that named
  a map leaves that one map in `sv_mapRotation`, and without the restore every later
  match would replay it.
* It does not cover players who join *during* the vote — they get no menu, and the
  tally is recomputed from the players who are there when it is cast.
* It does not change the game type or the number of rounds, only which map comes next.

## The map pool

The pool lives in **three** places, and they have to agree:

| where | what it holds | used for |
|---|---|---|
| `esl_mapVoteMaps()` / `esl_mapVoteLabels()` in [`_esl.gsc`](../src/maps/mp/gametypes/_esl.gsc:1) | the map names, and their labels, in the same order | drawing the candidates, announcing the winner |
| [`tables/esl_mapvote.csv`](../src/tables/esl_mapvote.csv:1) | `map, preview material, label` | what each card draws |
| `sv_mapRotation` in [`config/ESL-MOD_server.cfg`](../config/ESL-MOD_server.cfg:1) | the rotation the server starts with | what "Random Map" and a silent vote fall back to |

The build cross-checks the first two — a map in the table the pool never offers, or a
map the pool offers that the table does not have, fails the build:

```
mapvote : 10 maps, esl_mapVoteMaps() and tables\esl_mapvote.csv in step
```

The third is deliberately *not* checked (a server may run a rotation of its own), but
a map that is not installed in `zone\` must never end up in either list: the vote sets
`sv_mapRotation` to a single entry, and an unknown map there stops the server's map
change.

## Where the UI comes from

`ui_mp/scriptmenus/map_vote.menu` is sesh_server_v2's menu, adapted:

* the candidates are looked up in `tables/esl_mapvote.csv` (their own table had 45
  maps; ours has the ten in the pool),
* the timer line reads our `esl_vote_timer` instead of the game's `timer_text`,
* `onOpen` plays our long vote sound instead of theirs,
* the card macros come from their `ui_mp/common/redux.inc`, which is shipped as it
  came.

Two more of their files are used:

* **`mod.ff`** — the mod's own fastfile, installed next to the archive
  (`mods\ESL-MOD\mod.ff`). It is what defines the preview *materials*
  (`preview_mp_terminal`, … `preview_mp_random`): the stock game ships the preview
  *images* (`images\preview_mp_*.iwi`, in `main\iw_02.iwd` and `iw4x_01.iwd`) but no
  materials to draw them with, and a material is a fastfile asset. The file is 1173
  bytes, third-party and unmodified (`third_party\sesh_server_v2\mod.ff`, sha256
  `6E650A2B…`), and it is copied into the mod folder by `tools\install.ps1`.
  The compiler for it (IW4x's ZoneBuilder, `iw4x.exe -zonebuilder`) is a GUI tool, so
  the file is taken as it is rather than rebuilt.
* the card layout itself, as described above.

**The script is not theirs.** sesh_server_v2 ships no script at all, and nothing in
IW4x implements the dvars its menu reads, so the server side (`esl_mapVote*` in
`_esl.gsc`) is ESL-MOD's own.

## The sound

`esl_vote_long` — `src/sound/esl/voting_long.wav`, ~21 s, played once when the menu
opens, so it covers the vote. The alias is
[`src/soundaliases/esl_vote_long.csv`](../src/soundaliases/esl_vote_long.csv:1), the
long counterpart of the `esl_vote` the IW4x vote menus play (see
[VOTING.md](VOTING.md)); the mp3 both were converted from are the `voting_long.mp3`
and `voting_short.mp3` in the repository root.

## Verifying

* The build prints the pool check above and, in its entry summary,
  `ui_mp/scriptmenus/map_vote.menu`, `tables/esl_mapvote.csv` and the two vote menu
  overrides for IW4x's own vote menus. It fails if the map vote menu is missing from
  the archive, if it stops playing `esl_vote_long`, if it stops reading
  `tables/esl_mapvote.csv`, or if its `cast_vote:` response goes away.
* `mods\ESL-MOD\mod.ff` has to be present next to `z_eslmod.iwd`; `tools\install.ps1`
  fails the install when the repository copy is missing.
* In the server log (`mods\ESL-MOD\logs\games_mp.log`) a vote writes one line when it
  starts and one when it resolves:

  ```
  mapvote: mp_terminal / mp_rundown / mp_quarry (+ random), 15 s
  mapvote: mp_rundown wins with 3 vote(s) -> next map
  ```

  "no votes - rotation left alone", "random map wins" and the tie line are the other
  outcomes, so the log says what happened without needing to watch the match.
