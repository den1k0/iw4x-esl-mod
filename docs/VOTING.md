# ESL-MOD — the vote sound

IW4x's built-in voting (map restart, next map, change map, change gametype, kick a
player) is silent. ESL-MOD makes it audible: a short sound plays the moment a vote is
issued.

> The mod has a second, separate vote — the **end-of-match map vote**, where the
> players pick the next map instead of the engine picking one at random. That one is
> its own document: [MAPVOTE.md](MAPVOTE.md). It plays the *long* sound while its menu
> is open; the short one described here is for IW4x's own vote menus.

## What IW4x's voting is

The vote *commands* are the game's own, but the menu that issues them is IW4x's: it
ships the four vote menus as rawfiles inside its own archive
(`iw4x\iw4x_00.iwd`, build r5124):

| menu | what it issues |
|---|---|
| `ui_mp/scriptmenus/callvote.menu` | map restart, next map |
| `ui_mp/scriptmenus/changemap.menu` | map restart, next map, a map from the map list |
| `ui_mp/scriptmenus/changegametype.menu` | map restart, next map, a gametype from the list |
| `ui_mp/scriptmenus/kickplayer.menu` | map restart, next map, a player from the player list |

Each vote is one menu action. Two shapes appear:

```
MENU_CHOICE_BUTTON_VIS(0, "button_1", "@MP_VOTE_MAPRESTART", exec "cmd callvote map_restart"; close self;, ;, 1)
```

and, for the list boxes, one of IW4x's own client-side vote handlers:

```
action { close "self"; uiScript "voteMap"; }     // also: voteGame, voteKick
```

`voteMap`, `voteGame`, `voteKick`, `voteTempBan` and `voteTypeMap` are implemented
inside `iw4x.dll`; a menu can only invoke them.

A mod cannot make the game play a sound at vote time by itself: the engine tells the
game scripts nothing about a vote, there is no vote dvar to watch, and the "a vote is
in progress" display other players get is drawn by the engine. The one hook that exists
is the menu the vote is issued from — a rawfile, and a mod overrides a rawfile by
carrying the same path.

## What ESL-MOD does

The four menus are forked into the repository and one `play` is added to every action
that issues a vote, so the sound fires once per press:

| file | play calls | votes |
|---|---|---|
| [`callvote.menu`](../src/ui_mp/scriptmenus/callvote.menu:1) | 2 | `map_restart`, `map_rotate` |
| [`changemap.menu`](../src/ui_mp/scriptmenus/changemap.menu:1) | 3 | `map_restart`, `map_rotate`, `voteMap` |
| [`changegametype.menu`](../src/ui_mp/scriptmenus/changegametype.menu:1) | 3 | `map_restart`, `map_rotate`, `voteGame` |
| [`kickplayer.menu`](../src/ui_mp/scriptmenus/kickplayer.menu:1) | 3 | `map_restart`, `map_rotate`, `voteKick` |

```c
MENU_CHOICE_BUTTON_VIS(0, "button_1", "@MP_VOTE_MAPRESTART", play "esl_vote"; exec "cmd callvote map_restart"; close self;, ;, 1)
```

```c
action { play "esl_vote"; close "self"; uiScript "voteMap"; }
```

It is in the *action* and not in an `onOpen` on purpose: opening the vote menu and
backing out is not a vote, and the sound should mark the vote, not the menu. The
game's own menus work the same way — they `play "mouse_over"` from the items the
player picks.

**Who hears it.** The client that issues the vote. Everyone else sees IW4x's on-screen
vote notice and casts their vote with the `vote yes` / `vote no` keybinds, which the
mod has no hook for — see the last section of this file.

### Importing the fork again

The menus are IW4x's files, so they are imported, not written by hand:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\import_vote_menus.ps1
```

It copies the four menus out of `iw4x\iw4x_00.iwd` into `src\ui_mp\scriptmenus\` and
prints the hash of each one, so the fork stays traceable to the build of the game it
came from. **The `play` lines are a mod edit on top of that copy**, so re-importing
overwrites them: run the import after an IW4x update and re-apply the edits, and let
the build tell you when one is missing (it counts the calls per menu and fails on
"plays `esl_vote` 0 time(s)").

## The sound itself

Two rawfiles, both shipped in `z_eslmod.iwd`:

```
soundaliases/esl_vote.csv       the alias the menus play
sound/esl/voting_short.wav      the file the alias names
```

### The alias

A sound alias is a rawfile under `soundaliases\` — the engine loads every
`soundaliases\*.csv` it can find, which is how a mod adds a sound the game's own
fastfiles know nothing about. [`src/soundaliases/esl_vote.csv`](../src/soundaliases/esl_vote.csv:1)
is a copy of the shape the game's own aliases use, using the game's UI template
`ui_screen_trans_in`. To dump those aliases again (they live in the game's fastfiles,
not in the iwds):

```bat
cd /d D:\Games\iw4x
Unlinker.exe --include-assets sound --gdt -o "dumps\sound" zone\russian\ui.ff zone\russian\common.ff
```

which writes one `soundaliases\<name>.csv` per alias, header line and all - that is
where the 31 column names above come from.

```csv
name,sequence,file,vol_min,vol_max,pitch_min,pitch_max,dist_min,dist_max,channel,type,probability,loop,masterslave,loadspec,subtitle,compression,secondaryaliasname,chainaliasname,mixergroup,volumefalloffcurve,startdelay,speakermap,reverb,lfe percentage,center percentage,platform,envelop_min,envelop_max,envelop percentage,velocity_min
esl_vote,0,esl/voting_short.wav,0.85,0.85,1,1,5e+05,2500000,13,loaded,1,nonlooping,,,,,,,,",$default",0,,,0,0,,0,0,0,0
```

The columns that matter here:

| column | value | why |
|---|---|---|
| `name` | `esl_vote` | what the menus `play` |
| `file` | `esl/voting_short.wav` | relative to `sound\` |
| `vol_min`, `vol_max` | `0.85` | **the volume knob** |
| `dist_min`, `dist_max` | `5e+05`, `2500000` | no distance attenuation — this plays at the player, not in the world |
| `channel` | `13` | the channel the game's UI sounds use |
| `type` | `loaded` | held in memory, like every other short UI sound |
| `loop` | `nonlooping` | a one-shot |
| `mixergroup` | `,$default` | the UI mixer group; the trailing comma in the field is why it is quoted |

The columns are **positional**: a missing name in the header line shifts every value of
every row, and the file loads without complaining. The build therefore compares the
header against the game's own, line for line, and checks that every row's `file` really
is in the payload.

### The wav

The game's short sounds are 16 bit PCM wav files; the only `.mp3` files in the game
data are the long, streamed ambience tracks (`streamed`, `channel 28`, mostly looping).
A menu sound is a wav, so the mp3 this started from was converted once and the result
is what ships:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command ".\tools\dev\mp3-to-wav.ps1 -In voting_short.mp3 -Out src\sound\esl\voting_short.wav"
```

[`tools/dev/mp3-to-wav.ps1`](../tools/dev/mp3-to-wav.ps1:1) converts with the Windows
media pipeline (Media Foundation, through the WinRT transcoder) at 44.1 kHz 16 bit
stereo, so no ffmpeg or other tooling is needed. The mp3 it came from is still in the
repository root, `voting_short.mp3`, as the source of the shipped wav.

To use a different sound, put the new wav in `src\sound\esl\` and point the `file`
column at it; the build refuses an alias whose sound is not in the payload.

## Why not sound the vote for everyone

The two things that would be needed are both missing in this game build:

* a **script hook**: `prevote` / `postvote` style callbacks do not exist in IW4's
  script VM, and IW4x does not add one — the vote is handled entirely in the engine,
  and the only script-visible part is the menu that casts it (`uiScript "voteKick"` and
  friends, which a menu invokes rather than receives).
* a **client-side state to watch**: no `ui_vote*` or `vote*` dvar tracks a vote in
  progress (checked against the strings in `iw4x.dll` and the game's own dvars), so a
  HUD script cannot poll for it either.

If a future IW4x release exposes either, the sound is one line to move: the alias and
the sound file stay as they are, and the trigger becomes whatever sees the vote start.

## Verifying

* `tools\build.ps1` prints

  ```
  sound   : 1 alias file(s), 1 sound file(s) -> soundaliases\, sound\
  ```

  and lists `sound/esl/voting_short.wav`, `soundaliases/esl_vote.csv` and the four vote
  menus in its entry summary. It fails on a bad header line, on an alias whose sound is
  not in the payload, on a vote menu missing from the archive, and on a menu whose
  `play` calls went missing.
* In game, the client console (`<IW4x>\userraw\console_mp.log`) logs

  ```
  Missing soundalias "esl_vote".
  ```

  if the alias did not load — that means the CSV was not found or did not parse, and
  the vote will be silent. No such line, and the sound plays.
* The names in the log are worth knowing: `WARNING: can't find any sound alias files
  (soundaliases/*.csv)` only appears when the engine finds *no* alias file at all, so it
  is not expected here — the game's own alias files are inside its fastfiles.
