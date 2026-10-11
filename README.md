# ElixirDoom

Doom, written in Elixir, played in a terminal. The renderer, the BSP, collision, line of
sight and the state machines are Cauldron's (`cauldron_2d`); this package is the game:
reading a WAD, and Doom's own rules for things, weapons, monsters, doors, lifts, switches,
pickups and levels.

```sh
mix deps.get
mix doom --wad path/to/DOOM1.WAD
mix doom --wad path/to/DOOM.WAD --level E2M1 --skill 4
```

No WAD is included. The shareware `DOOM1.WAD` may be passed on unchanged; the registered
and commercial WADs may not. Point `--wad` at one you have, or set `DOOM_WAD` to its path or `DOOMWADDIR` to its directory.

On a terminal that keeps images (kitty, Ghostty, WezTerm, iTerm2) the picture is drawn
at twice Doom's 320×200 and the terminal scales it to the window, so a small font gives more
room without a blurrier picture. `--picture` (or `CAULDRON_PICTURE`, or
`config :cauldron_2d_drafter, picture: "..."` in a `config/runtime.exs`) chooses
otherwise, with any of these comma separated: `native` draws at Doom's own size times
the largest whole number that fits the window, `native:N` at `N` times, `size:WxH`
sets the size itself, `png` sends each frame as a PNG (about a third smaller, for play
over ssh, at more CPU), `swap` replaces each frame without a blank between, and `none`
draws at the window's cells instead. The default is `native:2,swap`.

## Keys

| Key | Action |
| --- | --- |
| `W` `S` or `↑` `↓` | forward, back |
| `A` `D` | strafe |
| `←` `→` | turn |
| `Space` | fire |
| `F` | use a door or switch |
| `R` (held) | run |
| `Q` `E` | previous, next weapon |
| `1`–`7` | a weapon |
| `Tab` | automap |
| `Esc` | the menu |

`Esc` opens Doom's own menu, drawn from the WAD's pictures; the game pauses while it is
open. New game picks the episode and skill; options holds end game, messages, graphic
detail (low draws the view half as wide), screen size (Doom's border around a smaller
view, or no status bar at the largest), mouse sensitivity, sound and music volume, and
controls, where keys and mouse buttons are bound and the mouse switched on; read this
shows the help screens; quit asks as Doom asks. Loading and saving say they are not
part of this game. With the mouse on, moving it left and right turns, the left button
fires, the right button runs, and the wheel picks the previous and next weapon.

A controller works too: the left stick walks and strafes and the right stick turns, each
as far as it is pushed; the right trigger fires, the left trigger or pressing the left
stick runs, `A` or `X` uses, the bumpers change weapon, `Back` shows the automap and
`Start` the menu, where the d-pad moves, `A` chooses and `B` goes back.

A dead player presses `F` to start the level again. Between levels, `F` or `Space` goes on.

## What is here

* every shareware level, E1M1 to E1M9, with secret exits, and the registered episodes'
  bosses and their exits
* the player's movement, view height and bob, running, sliding along walls, steps and
  drop-offs
* fist, chainsaw, pistol, shotgun, chaingun, rocket launcher, plasma rifle and BFG, with
  Doom's aiming, spread and refire
* zombiemen, sergeants, imps, demons and spectres, lost souls, cacodemons, barons, the
  Cyberdemon and the Spider Mastermind: looking, hearing through open doors, chasing,
  melee and missile attacks, pain, deaths and dropped weapons
* doors (keyed and timed), lifts, rising and falling floors, crushers, stairs, lights that
  flicker, strobe and glow, switches, teleporters, damaging floors and secrets
* pickups — health, armour, ammunition, weapons, keys, the backpack and the power-ups,
  with Doom's messages and screen flashes
* the status bar, the automap, the intermission tallies, and the end-of-episode text
* sound effects from the WAD, placed and panned; the music played from the WAD's MUS
  lumps through `TuningFork`

## What is not

* Doom II's monsters' own attacks (the arch-vile, revenant, mancubus, pain elemental and
  arachnotron do nothing when they attack) and Doom II's line specials above 104
* the music is General MIDI played by `TuningFork`'s synthesised instruments, not the
  OPL sound of a Sound Blaster; reading the WAD's `GENMIDI` patches through an OPL
  emulator is the way to that sound
* saving and loading games, demos and deathmatch

## How it is built

* `ElixirDoom.Wad`, `Graphics` and `Level` read the WAD: lumps, the composed wall
  textures, flats and patches as one `Cauldron2D.Sectors.Pictures` set, and each level as
  a `Cauldron2D.Sectors.Map` with the BSP the WAD carries
* `ElixirDoom.Info` is Doom's state table and thing definitions, generated from the GPL
  `info.c` by `mix doom.info`; states run through `Cauldron2D.States`, actions through
  `ElixirDoom.Actions`
* `ElixirDoom.Game` is the `Cauldron2D.Game`: a world (`ElixirDoom.World`) stepped 35 times
  a second — players (`Player`, `Weapons`), the level's machinery (`Specials` and the
  modules under it, run as `Cauldron2D.Thinkers`), then every thing (`Mobj`, `Enemy`,
  `Combat`, `Items`)
* `ElixirDoom.Client` is the `Cauldron2D.Client.Game`; its scene is a picture
  (`ElixirDoom.Render`, `StatusBar`, `Text`) that Cauldron's surface draws in whatever the
  terminal shows best

### Speed

On E1M1, a whole picture with the status bar takes 0.6 ms at 160×100, 1.6 ms at 400×240
and 2.8 ms at 640×400. A tic — every player, machine and thing — takes 0.2 to 0.8 ms
across the shareware levels. Reading the shareware WAD's pictures takes about a second,
once.

## Tests

```sh
mix test
DOOM_WAD=path/to/DOOM1.WAD mix test
```

Without `DOOM_WAD` the tests that play a level are skipped.

## Licence

GPL-2.0-or-later. Doom's source was released by id Software under the GPL in 1999; the
state table and thing definitions here are generated from it, and the rules follow it
closely, so this package is a derivative of that source. Cauldron, which it plays on, is
MIT and contains no Doom code or data.

The WADs are not covered by that release. Doom's pictures, sounds, music and levels are
id Software's (now ZeniMax's), and this package only reads them from a WAD the player
supplies.
