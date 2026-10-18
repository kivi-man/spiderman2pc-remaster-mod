# MODLOG — Spider-Man 2 (2004 PC, Webhead) → "Marvel's Spider-Man" movement/combat mod

## Facts
- Install: H:\Spider-Man 2, exe System/Webhead.exe (x86). Engine: Unreal Engine 2 (Core.u/Engine.u/.int/.ini). No anti-cheat.
- Maps: *.whr, saves: System/game0-4.ini (save slots!) + gamestate.ini.
- Player pawn class: Webhead.ini [URL] Class=Webhead.SpideyPawn. DefaultGame=Webhead.WebheadGameInfo.
- Script source is STRIPPED from .u files -> need decompiler (UE Explorer) to read.
- Editor.dll contains UMakeCommandlet (+ BatchExport, StripSource...) -> compiling a new .u is possible
  if we have a ucc.exe launcher (none shipped).
- Relevant identifiers in Webhead.u: SPHYS_Swinging, SPHYS_Zipping, MaxSwingDistance, MinSwingDistance,
  InitialSwingLength, CanSwingFromTarget, FireWebRope, ContextSwing/ContextZip, JumpFromWall, ComboAttack,
  PunchAttacks/KickAttacks, DangerSense*, SpiderSense*, SpideyAdrenaline, CalcSwingAdrenaline.

## Backups
- <yedek-zip> (whole System folder).
  Restore: `um backup restore sm2-system`.

## Plan (route: new UnrealScript package subclassing SpideyPawn, selected via Webhead.ini)
1. Tools: ucc launcher for Editor.dll MakeCommandlet; UE Explorer to read SpideyPawn.
2. Slice 1: physics swinging that attaches to building geometry (Trace), with momentum + release boost.
3. Then: point launch, web zip, wall run, air tricks, combat combos/dodge/web strike, gadgets.

## Toolchain (working, 2026-10-12)
- Decompile: _mod/tools/Decomp (UELib 1.13.7) -> _mod/decomp/<pkg>/*.uc (package ver 126/1, "Fizz Make").
- Loader: _mod/loader/d3d8proxy.cpp -> System/d3d8.dll (build with PowerShell `cmd /c build.cmd`; bash `cmd //c` silently fails).
  - `Webhead.exe -ucc=Editor.MakeCommandlet` compiles ..\MSMSpidey\Classes -> System/MSMSpidey.u (log: System/ModLoader.log).
    Needs runtime patch of Editor.dll MakeScripts CRC check at RVA 0x8fb37 (jne->nop), else stock classes w/ stripped
    text (" ") get recompiled and fail ("Missing 'Class' definition").
  - `-modlog` tees GLog/GWarn to ModLoader.log at runtime.
  - Controller override: menus travel with ?Game=Webhead.WebheadGameInfo (hard-coded), ServerActors are NOT spawned
    in standalone, DefaultGame ini ignored. Loader loads WebheadGameInfo at appInit, AddToRoot, rewrites default
    PlayerControllerClassName FString (offset 0x484) -> MSMSpidey.MSMSpideyController. Verified in log.
- Webhead.ini changes: EditPackages+=Webhead,MSMSpidey; windowed 1280x720.
- Mouse is a cursor in this game (WinDrv MouseX/YMultiplier=0); camera turn is aBaseX keys.

## Status
- Slice 1 (dynamic swing anchors on geometry) works in game per user, but uses native non-physics swing.
- User wants FULL replacement of movement, camera, swing, combat, controls with Marvel's Spider-Man feel.
  User offered an HTML reference implementation of swing + combat to port.

## Full MSM port (2026-10-12) — from örnekhtml/src (player.js, camera.js, input.js, enemies.js)
- Classes: MSMSpideyController (all mechanics, runs inside stock PlayerWalking state; inactive on *Startup maps),
  MSMSpideyPawn (TakeDamage/NotifyAttack hooks, mesh rotation), MSMHud (Interaction overlay), MSMAnchor (rope targets).
- Pawn class: User.ini [DefaultPlayer] Class=MSMSpidey.MSMSpideyPawn (Webhead.ini [URL] Class is NOT used).
- Mouse look: Webhead.ini [WinDrv.WindowsClient] MouseX/YMultiplier=1 (were 0 = cursor mode).
- Keys (User.ini aliases 26-33): WASD, mouse cam, Shift swing/parkour/wall-run, Space jump(hold=charged)/release,
  Q web zip, E point launch, LMB attack, RMB web shot, C dodge/dive, F finisher, R old context action (MSMUse).
- Units: S=53 uu per metre; engine gravity 1500 compensated to 30 m/s^2; one physics step per frame + predictive rope clamp.
- Debug: bMSMDebug logs "MSMDBG" once per second to ModLoader.log (-modlog). Rebuild: _mod/rebuild.sh [run].
- Verified in game: swing/air/release/wall entry run without script errors (user playing). Not yet verified: combat vs thugs,
  point launch, wall top climb, rope wrap, anim choices (swing loop = 'TarzanAll' guess).
- Mission compatibility (2026-10-12): stock FindTarget still runs every frame with the stock ThirdPersonCamera steered
  along the MSM view (UpdateContextTarget), so stock reticles + Target/FireAction work. RMB on Pull/Web/Shoot/Pickup/Use
  target -> stock DoAction; E on Zip target -> stock zip; R -> any stock action. Air swing prefers WebSwingPoints within
  60 m (SwingTrigger on attach, ReleaseTrigger on release) and swinging within TargetableRadius of one fires it.
  Verified: CB3_CityStreet tutorial events SwingFire01A..08 + webswingcheckpoint2controller fired by the user's play.
  LMB alias also sends "Button bFire | Fire", RMB "AltFire" (swallowed in MSM state, used by stock lift/throw states).
- rebuild.sh no longer kills a running game unless passed 'kill'.

## Dynamic reflections (2026-10-12)
- Stock: one CubemapHack-shot cubemap per district on every reflective material (stage 3: CURRENT + CURRENT.a * cube,
  TCI camera-space reflection vector, tex matrix = inverse view rotation).
- Loader = d3d8to9 v1.16.0 + msm_reflect.cpp. Patch: _mod/third_party/d3d8to9-msm.patch (device.cpp) + d3d8to9_base.cpp
  CreateDevice strips D3DCREATE_PUREDEVICE (state is read back). Previous DLLs: d3d8.prev-native.dll, d3d8.prev-cube.dll.
- MSMSpideyController.RenderTexture fills two ScriptedTextures every frame:
  ReflTex 2048x1024 = 6 cube faces 512 (D3D cube layout, D3D (X,Y,Z) = UE (Y,Z,X)), pawn hidden;
  MirrorTex 2048x2048 = mirror view, top-left screen*1.06, camera reflected through the nearest wall
  (FindReflPlane: 5 Pawn.Trace rays, actors included; walls here are BSP). MSMHud draws both as a 1x1 additive pixel
  with color 1/255 - PURE BLACK IS SKIPPED BY THE CANVAS AND THE TEXTURES ARE THEN NEVER RE-RENDERED.
- msm_reflect.cpp: per draw it checks the render target (GetRenderTarget), records view matrices per target, finds the
  mirror plane as the bisector of main/mirror cameras (validated), clips the mirror render behind the wall, and splits
  each reflective draw into 3 passes with clip planes: on the plane (+-48uu) -> planar texture projected through the
  mirror camera's view*proj (TCI camera-space position, projected); elsewhere -> live cube with its own tex matrix.
  D3D8 "vertex shaders" with no function are fixed function (check ShaderInfo->Shader == nullptr).
- UE2 does not set a D3D viewport for the portal: the mirror rect is recomputed from the back buffer size.
- System/MSMReflections.ini [MSMReflections]: Enabled, Planar, and test switches re-read every 120 frames: Mips,
  Override, Debug (1 = raw mirror image on mirror surfaces, 2 = raw cube). Log: System/MSMReflections.log.
- Game pauses when it loses focus: drive with um win drive, always "key 0x1B" to unpause first.
- Verified 2026-10-12: CB3_CityStreet tutorial window shows Spider-Man, cart and vendor as a real mirror (screenshot).

## Settings-page launch crash investigation (2026-10-12)
- The settings page opens successfully. The latest `System/ModLoader.log` ends while rendering `CB3_CityStreet` with
  `CreateTexture failed(80004005)`; the crash is in the D3D texture cache, after a device reset to 1280x720 windowed.
- `_mod/third_party/d3d8to9/source/d3d8to9_device.cpp` promotes eligible default-pool textures to render targets for
  reflection capture. Added a fallback: if an implicitly promoted texture fails, retry it using the normal dynamic
  texture mapping. Explicit render-target textures remain unchanged. Both the retry and any remaining failure log
  dimensions, format, usage flags and HRESULT to `System/MSMReflections.log`.
- Loader DLL build completed successfully. The game is currently open, so `System/d3d8.dll` could not be replaced;
  its pre-change copy is saved as `System/d3d8.pre-texture-fallback.dll`. The new DLL is staged at `_mod/loader/d3d8.dll`.
- Runtime verification is pending until the game is closed and the staged DLL can be installed.

## Modern GPU graphics options (2026-10-18)
- `_mod/loader/msm_graphics.cpp` (+ `msm_postfx.hlsl` -> `msm_postfx_ps.h`, built with fxc `/T ps_2_b`): refresh rate (desktop rate by default;
  D3D picks the display default, often 60 Hz, when none is asked for), borderless fullscreen (fullscreen request -> windowed device on a
  WS_POPUP window), adapter override (`Adapter` in MSMSpidey.ini, adapters are listed in ModLoader.log), auto frame cap (Hz-3, VSync off),
  texture LOD bias, MSAA re-enabled (was hard-disabled by `kMsaaEnabled`), post pass (FXAA + unsharp sharpening + gamma ramp via 256x1 LUT).
- The post pass runs in `Direct3DDevice8::Present` (`MSM_PostFX`), copies the back buffer to a render-target texture, draws a fullscreen quad
  back onto it and restores the state with a D3DSBT_ALL state block + render target/depth. The game's `SetGammaRamp` is swallowed when the
  device is windowed/borderless (modern drivers ignore it there) and applied by the shader instead.
- `Webhead.exe` is now Large Address Aware (`_mod/tools/patch_laa.py`, backup `System/Webhead.exe.orig`): 4 GB address space for MSAA / big textures.
- `_mod/tools/prefer_dgpu.ps1`: optional, sets the Windows "high performance GPU" preference for hybrid laptops (not run automatically).
- Not done: render scale / supersampling (the engine's viewport, cursor and UI all assume back buffer == window size), D3D9Ex/FlipEx (the
  wrapper is built on `Direct3DCreate9`, FlipEx excludes MSAA/COPY), HDR output. DXVK can be dropped in as `d3d9.dll` as a compatibility mode.
- `d3d8to9-msm.patch` now covers both `d3d8to9_device.cpp` and `d3d8to9_base.cpp` (the old one missed the CreateDevice hook).
