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
| `MSMSpidey/Classes` | UnrealScript mod package (`MSMSpidey.u`): movement states, camera, swinging, combat, HUD, English settings screen |
| `loader/` | `d3d8.dll` loader (d3d8to9 based): dynamic reflections (planar mirror + live cube map), graphics settings, `-ucc=` commandlet runner, `-msmexec=` editor-script runner |
| `third_party/d3d8to9-msm.patch` | Patch for [crosire/d3d8to9](https://github.com/crosire/d3d8to9) (BSD-2); fetch the upstream source yourself |
| `tools/`, `docs/` | Build/helper scripts; `AGENT.md` (project guide) and `MODLOG.md` (verified technical log), both in Turkish |

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
