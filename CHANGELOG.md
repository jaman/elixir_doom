# Changelog

## [0.2.0]

### Added

- The game is drawn by the graphics card (`ElixirDoom.Gpu`) where there is one: in the
  terminal pane by default, or in a window of its own. The picture options `software`,
  `gpu` and `window` choose for one run.
- The options menu's DRAWING row: AUTO, SOFTWARE, CARD or WINDOW, saved with the other
  settings.
- A setup page before the game starts (`Cauldron2D.Drafter.Launcher`) that finds an IWAD
  in Steam's usual installs, CrossOver's included, and checks the one you give.

## [0.1.0]

### Added

- Doom played in a terminal from a WAD you supply (`mix doom --wad DOOM1.WAD`): every
  shareware level with secret exits, the registered episodes' bosses, Doom's weapons,
  monsters, specials, pickups, status bar, automap, intermissions and end text, sound
  effects placed in the world and the WAD's music.
- `--picture` (or `CAULDRON_PICTURE`): how the picture reaches a terminal that keeps
  images, by default twice Doom's 320×200 (`native:2,swap`).
- `--mute` (or `CAULDRON_MUTE=1`): no sound.

