<div align="center">

# BeamMac

Runs BeamNG.drive on Apple Silicon Macs through Wine, with DXMT or Apple's D3DMetal drawing through Metal.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20·%20Apple%20Silicon-black)

</div>

## What it does

- Installs a Wine 10 engine (Sikarugir build), the Windows Steam client and a dedicated prefix in this folder. Nothing goes to `/Applications` or `~/.wine`.
- Ships two Metal backends for Direct3D 11 and switches between them per launch:
  - **DXMT**: replaces Wine's `d3d11`, `dxgi` and `d3d10core` inside the engine. DXMT's DLLs are marked as Wine builtins, so copies in `system32` or next to the game are swapped back for Wine's own. The originals stay in `engines/wine-builtin-backup`.
  - **D3DMetal** (Game Porting Toolkit): lives in an APFS clone of the engine, so both backends share one prefix and one Steam library.
- Turns on MSync for lower CPU overhead on thread synchronisation.
- Upscales with MetalFX through DXMT and paces frames through Metal (`config/dxmt.conf`). Wine's Retina mode stays off: the game renders at the screen size in points and MetalFX scales that to the panel's pixels.
- Shows Apple's Metal HUD on request for FPS and frame times.
- Keeps a DXMT shader cache in `data/shader-cache` so stutter from shader compilation happens once.

## Install

```sh
bin/setup      # engine, DXMT, D3DMetal, prefix, Steam
bin/steam      # log in and install BeamNG.drive
```

Downloads are pinned by SHA-256, except the Steam installer.

## Requirements

- Apple Silicon Mac, Rosetta 2
- About 2 GB for engines and prefix, plus the game

## Usage

```sh
bin/beamng                 # DXMT, MetalFX on
bin/beamng --hud           # with Metal HUD
bin/beamng --d3dmetal      # Apple D3DMetal instead of DXMT
bin/beamng --no-metalfx    # render at the in-game resolution only
bin/stop                   # end Steam, BeamNG and the wineserver
bin/wine winecfg           # any wine command inside the prefix
```

Every launch restarts Steam, because the game inherits its environment from `steam.exe`.

## App

```sh
script/build_and_run.sh           # build dist/BeamMac.app and open it
script/build_and_run.sh install   # copy it to ~/Applications
```

BeamMac.app runs the same scripts from this checkout. It has three pages:

- **Fahren**: start BeamNG or Steam, pick a profile (Flüssig, Ausgewogen, Schön), pick DXMT, D3DMetal or WineD3D, toggle the Metal HUD. Warns when Low Power Mode is on.
- **Spiel**: MetalFX, frame limit, display mode, BeamNG's quality level, grass, effects, traffic and WASD steering. The resolution follows the screen in points and the MetalFX factor follows its backing scale.
- **Mods**: lists the ZIPs in BeamNG's mod folder, adds new ones by drag and drop, moves removed ones to the Trash.
- **Wartung**: install status, setup, shader cache, winecfg, stop everything, live script output.

Before each launch the app writes `data/dxmt.conf` and the managed keys of BeamNG's `settings/settings.json` and `settings/inputmaps/keyboard.diff`, because the game rewrites its settings when it quits. `config/dxmt.conf` stays the default for terminal launches.

## Layout

| Path | Content | In git |
|---|---|---|
| `bin/`, `lib/` | scripts | yes |
| `config/dxmt.conf` | DXMT frame limit and MetalFX factor | yes |
| `downloads/` | pinned archives | no |
| `engines/` | Wine, DXMT, D3DMetal, dylibs | no |
| `data/` | prefix, Steam, game, logs, shader cache | no |

D3DMetal is Apple software under the Game Porting Toolkit license and is never committed.

## Credits

Wine engine and wrapper libraries: [Sikarugir](https://github.com/Sikarugir-App). DXMT: [3Shain/dxmt](https://github.com/3Shain/dxmt). D3DMetal: Apple.
