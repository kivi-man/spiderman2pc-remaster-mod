# Spider-Man 2 (2004, PC) - Marvel's Spider-Man style mechanics mod

An experimental, personal-use mod for **Spider-Man 2 (2004)** (Unreal Engine 2) that replaces the movement,
camera, web-swinging, combat and settings systems with ones modelled on **Marvel's Spider-Man (Insomniac)**.
This repository contains **source code and tools only**. Game files, extracted models/textures, compiled
packages and third-party assets are **not** included and must not be added (`.gitignore` excludes them).

> Unofficial fan project. Spider-Man 2 and Marvel's Spider-Man belong to their respective rights holders.
> You need your own legitimate copy of the game to run anything here.

## Contents

| Folder | What it is |
|---|---|
| `MSMSpidey/Classes` | UnrealScript mod package (`MSMSpidey.u`): movement states, camera, swinging, combat, HUD, English settings screen, in-game debug menu (Insert), draw distance and crowd density |
| `loader/` | `d3d8.dll` loader (d3d8to9 based): dynamic reflections (planar mirror + live cube map), graphics options (MSAA, FXAA, sharpening, borderless, refresh rate, gamma ramp), `-ucc=` commandlet runner, `-msmexec=` editor-script runner |
| `third_party/d3d8to9-msm.patch` | Patch for [crosire/d3d8to9](https://github.com/crosire/d3d8to9) (BSD-2); fetch the upstream source yourself |
| `tools/`, `docs/` | Build/helper scripts (`patch_laa.py`, `prefer_dgpu.ps1`, ...); `AGENT.md` (project guide) and `MODLOG.md` (verified technical log), both mostly in Turkish |

## Features

**Graphics (settings screen, Display / Graphics tabs)**
- Borderless fullscreen by default, at the monitor's resolution; the resolution and refresh-rate lists never go above
  what the monitor offers (the loader writes `System/MSMDisplay.ini` at every start). "Highest" refresh rate picks the
  monitor's fastest mode instead of the driver's 60 Hz default.
- MSAA, anisotropic filtering, VSync, frame-rate limit (including an automatic cap just under the refresh rate for
  adaptive sync), FXAA, image sharpening, texture LOD bias, monitor/GPU choice.
- Gamma / brightness / contrast keep working when windowed or borderless: the game's gamma ramp is applied by the post
  pass shader instead of the hardware ramp.
- `tools/patch_laa.py` makes `Webhead.exe` large-address aware (4 GB instead of 2 GB; keeps a backup);
  `tools/prefer_dgpu.ps1` sets the Windows "high performance GPU" preference on hybrid laptops (run it yourself).

**World**
- **Draw distance** (Stock to 5x): stretches the cull distance of actors and placed static meshes and the radii in which
  the game's pedestrian / vehicle manager (`TrackNodeManager`) keeps NPCs and cars alive.
- **Crowd** (Stock to 20x): multiplies how many NPCs and vehicles live at once, how many appear per spawn round and how
  fast they appear. 20x is heavy; the setting is there to be lowered.
- **Debug menu** (Insert): show flags, render modes, Karma draws, stat counters and graphs, screenshot, texture flush,
  god mode / game speed, map loader. The game's own debug window (`Webhead.KWDebugRootWindow`) only pauses this build,
  so this page replaces it.

**Recommended: DXVK.** With the stock NVIDIA 32-bit Direct3D 9 driver the game can fail with
`CreateTexture failed(80004005)` after the display mode changes at high resolutions. Dropping the 32-bit
`d3d9.dll` of [DXVK](https://github.com/doitsujin/dxvk) into `System/` (not included here) avoided that in testing; the
loader's `d3d8.dll` then talks to DXVK instead of the driver. Dynamic reflections may need to be off while changing the
display mode (the screen stays black after a device reset with them on).

## Building (summary)

1. **Loader DLL** (x86, MSVC): put the `crosire/d3d8to9` sources under `third_party/d3d8to9`, apply
   `d3d8to9-msm.patch`, run `loader/build.cmd`, and install the result as the game's `System/d3d8.dll`.
2. **UnrealScript**: copy `MSMSpidey/Classes` into the game directory and run
   `Webhead.exe -ucc=Editor.MakeCommandlet` (the loader provides the commandlet runner) to produce
   `System/MSMSpidey.u`. `tools/build_offline.sh` builds in a separate copy while the game is running.
3. `Webhead.ini`: `[Engine.Engine] GUIController=MSMSpidey.MSMGUIController` and
   `[URL] Class=MSMSpidey.MSMSpideyPawn`.

See `docs/AGENT.md` and `docs/MODLOG.md` for details and pitfalls.

## License

Code: MIT (see `LICENSE`). Third-party code and assets keep their own licenses.
