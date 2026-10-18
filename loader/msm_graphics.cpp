// Driver-level graphics options for Spider-Man 2, set from the MSM settings page
// (MSMSpidey.MSMSettings, saved in System/MSMSpidey.ini). Re-read every ~2 s, so most are live:
//   MSAA         0/2/4/8   multisampled back buffer (device creation / reset)
//   bVSync                 present on vertical blank (creation / reset)
//   Anisotropy   1..16     anisotropic texture filtering (live)
//   FrameLimit   0 = off, -1 = auto (refresh rate - 3 when VSync is off), else fps cap (live)
//   RefreshRate  0 = desktop rate, else fullscreen refresh rate in Hz (creation / reset)
//   bBorderless            "fullscreen" requests become a borderless window on the desktop (creation / reset)
//   Adapter      -1 = as the game asks, else display adapter ordinal (creation)
//   PostAA       0/1       FXAA pass on the finished frame (live)
//   Sharpen      0..3      unsharp-mask pass on the finished frame (live)
//   MipBias      0..2      extra negative texture LOD bias: 0, -0.5, -1.0 (as textures are set up)
// The post pass is also what makes the game's gamma / brightness / contrast work when windowed or
// borderless: the gamma ramp the game sets is applied by the shader there instead of the hardware.
#include <d3d9.h>
#include <mmsystem.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "msm_postfx_ps.h"

static const char* kIni = ".\\MSMSpidey.ini";
static const char* kSection = "MSMSpidey.MSMSettings";

static int g_msaa, g_aniso = 8, g_vsync, g_frameLimit, g_refresh, g_borderless, g_adapter = -1;
static int g_postAA, g_sharpen, g_mipBias, g_noPost;
static int g_reflections = 1, g_mirror = 1;
static bool g_read;
static bool g_windowed = true;     // the current device is windowed (also borderless)
static UINT g_dispHz = 60;

void MSM_RLog(const char* Fmt, ...);

static int IniInt(const char* Key, int Default)
{
	char Buf[64];
	GetPrivateProfileStringA(kSection, Key, "", Buf, sizeof(Buf), kIni);
	if (!Buf[0])
		return Default;
	if (!_stricmp(Buf, "true"))
		return 1;
	if (!_stricmp(Buf, "false"))
		return 0;
	return atoi(Buf);
}

void MSM_ReadSettings()
{
	g_msaa = IniInt("MSAA", 0);
	g_aniso = IniInt("Anisotropy", 8);
	g_vsync = IniInt("bVSync", 0);
	g_frameLimit = IniInt("FrameLimit", 0);
	g_refresh = IniInt("RefreshRate", 0);
	g_borderless = IniInt("bBorderless", 1);
	g_adapter = IniInt("Adapter", -1);
	g_postAA = IniInt("PostAA", 0);
	g_sharpen = IniInt("Sharpen", 0);
	g_mipBias = IniInt("MipBias", 0);
	g_noPost = IniInt("NoPostPass", 0);   // test switch: skips the post pass completely
	g_reflections = IniInt("bReflections", 1);
	g_mirror = IniInt("bMirror", 1);
	g_read = true;
}

static void Ensure()
{
	if (!g_read)
		MSM_ReadSettings();
}

bool MSM_SettingReflections() { Ensure(); return g_reflections != 0; }
bool MSM_SettingMirror() { Ensure(); return g_mirror != 0; }

//-----------------------------------------------------------------------------
// device creation

// Display formats the mode list is queried with (back buffer formats map to these)
static D3DFORMAT DisplayFormatFor(D3DFORMAT F)
{
	switch (F)
	{
	case D3DFMT_A8R8G8B8: case D3DFMT_X8R8G8B8: return D3DFMT_X8R8G8B8;
	case D3DFMT_A2R10G10B10: return D3DFMT_A2R10G10B10;
	case D3DFMT_R5G6B5: case D3DFMT_X1R5G5B5: case D3DFMT_A1R5G5B5: return F == D3DFMT_R5G6B5 ? D3DFMT_R5G6B5 : D3DFMT_X1R5G5B5;
	default: return D3DFMT_X8R8G8B8;
	}
}

// the refresh rate the display offers at W x H closest to Want (ties go to the higher one)
static UINT PickRefresh(IDirect3D9* D3D, UINT Adapter, D3DFORMAT Fmt, UINT W, UINT H, UINT Want)
{
	const UINT Count = D3D->GetAdapterModeCount(Adapter, Fmt);
	UINT Best = 0;
	int BestDiff = 1 << 30;
	for (UINT i = 0; i < Count; i++)
	{
		D3DDISPLAYMODE M;
		if (FAILED(D3D->EnumAdapterModes(Adapter, Fmt, i, &M)) || M.Width != W || M.Height != H)
			continue;
		const int Diff = abs((int)M.RefreshRate - (int)Want);
		if (Diff < BestDiff || (Diff == BestDiff && M.RefreshRate > Best))
		{
			BestDiff = Diff;
			Best = M.RefreshRate;
		}
	}
	return Best;
}

// A borderless window fills the monitor of the adapter (or sits centred on it when the game asks for a smaller size)
static void PlaceBorderless(IDirect3D9* D3D, UINT Adapter, HWND Wnd, UINT W, UINT H)
{
	if (!Wnd || !D3D || !IsWindow(Wnd))
		return;
	MONITORINFO Info = {};
	Info.cbSize = sizeof(Info);
	HMONITOR Mon = D3D->GetAdapterMonitor(Adapter);
	if (!Mon || !GetMonitorInfoW(Mon, &Info))
		return;
	const int MonW = Info.rcMonitor.right - Info.rcMonitor.left;
	const int MonH = Info.rcMonitor.bottom - Info.rcMonitor.top;
	const int X = Info.rcMonitor.left + (MonW - (int)W) / 2;
	const int Y = Info.rcMonitor.top + (MonH - (int)H) / 2;
	// leave the window alone when it already is where it should be (a resize makes the engine rebuild its viewport)
	RECT Cur;
	const LONG Style = GetWindowLongW(Wnd, GWL_STYLE);
	if ((Style & (WS_CAPTION | WS_THICKFRAME)) == 0 && GetWindowRect(Wnd, &Cur) && Cur.left == X && Cur.top == Y &&
		Cur.right - Cur.left == (LONG)W && Cur.bottom - Cur.top == (LONG)H)
		return;
	SetWindowLongW(Wnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
	SetWindowPos(Wnd, HWND_TOP, X, Y, (int)W, (int)H, SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOACTIVATE);
}

// The window is moved after the device was reset / created: SetWindowPos sends WM_SIZE straight into the
// engine, which must not happen in the middle of IDirect3DDevice9::Reset.
static struct { bool Pending; UINT Adapter; HWND Wnd; UINT W, H; } g_place;

void MSM_AfterDeviceReady(IDirect3DDevice9* Dev)
{
	if (!g_place.Pending)
		return;
	g_place.Pending = false;
	IDirect3D9* D3D = nullptr;
	if (SUCCEEDED(Dev->GetDirect3D(&D3D)))
	{
		PlaceBorderless(D3D, g_place.Adapter, g_place.Wnd, g_place.W, g_place.H);
		D3D->Release();
	}
}

// What the monitor of the adapter is set to in Windows (resolution) and the fastest refresh rate it offers at that
// resolution. Written to MSMDisplay.ini for the settings page, which never offers more than this.
static UINT g_deskW, g_deskH, g_maxHz;

static void WriteDisplayInfo(IDirect3D9* D3D, UINT Adapter)
{
	MONITORINFOEXW Info = {};
	Info.cbSize = sizeof(Info);
	HMONITOR Mon = D3D ? D3D->GetAdapterMonitor(Adapter) : nullptr;
	const wchar_t* Dev = (Mon && GetMonitorInfoW(Mon, &Info)) ? Info.szDevice : nullptr;
	DEVMODEW Cur = {};
	Cur.dmSize = sizeof(Cur);
	if (!EnumDisplaySettingsW(Dev, ENUM_REGISTRY_SETTINGS, &Cur) && !EnumDisplaySettingsW(Dev, ENUM_CURRENT_SETTINGS, &Cur))
		return;
	UINT MaxHz = Cur.dmDisplayFrequency;
	DEVMODEW M = {};
	M.dmSize = sizeof(M);
	for (DWORD i = 0; EnumDisplaySettingsW(Dev, i, &M); i++)
		if (M.dmPelsWidth == Cur.dmPelsWidth && M.dmPelsHeight == Cur.dmPelsHeight && M.dmBitsPerPel >= 32 && M.dmDisplayFrequency > MaxHz && M.dmDisplayFrequency < 1000)
			MaxHz = M.dmDisplayFrequency;
	g_deskW = Cur.dmPelsWidth;
	g_deskH = Cur.dmPelsHeight;
	g_maxHz = MaxHz;
	char V[16];
	static const char* kFile = ".\\MSMDisplay.ini";
	static const char* kSec = "MSMSpidey.MSMDisplayInfo";
	sprintf_s(V, "%u", g_deskW); WritePrivateProfileStringA(kSec, "DesktopWidth", V, kFile);
	sprintf_s(V, "%u", g_deskH); WritePrivateProfileStringA(kSec, "DesktopHeight", V, kFile);
	sprintf_s(V, "%u", Cur.dmDisplayFrequency); WritePrivateProfileStringA(kSec, "DesktopRefresh", V, kFile);
	sprintf_s(V, "%u", g_maxHz); WritePrivateProfileStringA(kSec, "MaxRefresh", V, kFile);
	MSM_RLog("monitor: %ux%u, desktop %u Hz, up to %u Hz\n", g_deskW, g_deskH, Cur.dmDisplayFrequency, g_maxHz);
}

// Called by CreateDevice: lists the adapters once and applies the Adapter override.
UINT MSM_OnCreateDevice(IDirect3D9* D3D, UINT Adapter)
{
	MSM_ReadSettings();
	if (g_adapter >= 0 && D3D && (UINT)g_adapter < D3D->GetAdapterCount())
		WriteDisplayInfo(D3D, (UINT)g_adapter);
	else
		WriteDisplayInfo(D3D, Adapter);
	static bool Listed;
	if (D3D && !Listed)
	{
		Listed = true;
		const UINT N = D3D->GetAdapterCount();
		for (UINT i = 0; i < N; i++)
		{
			D3DADAPTER_IDENTIFIER9 Id = {};
			D3DDISPLAYMODE Mode = {};
			D3D->GetAdapterIdentifier(i, 0, &Id);
			D3D->GetAdapterDisplayMode(i, &Mode);
			MSM_RLog("adapter %u: %s (desktop %ux%u @ %uHz)%s\n", i, Id.Description, Mode.Width, Mode.Height, Mode.RefreshRate,
				i == Adapter ? "  <- requested by the game" : "");
		}
	}
	if (D3D && g_adapter >= 0 && (UINT)g_adapter < D3D->GetAdapterCount() && (UINT)g_adapter != Adapter)
	{
		MSM_RLog("adapter %u -> %d (Adapter in MSMSpidey.ini)\n", Adapter, g_adapter);
		return (UINT)g_adapter;
	}
	return Adapter;
}

// called with the converted D3D9 present parameters before CreateDevice / Reset
static HWND g_focusWnd;
void MSM_AdjustPresentParams(IDirect3D9* D3D, UINT Adapter, D3DDEVTYPE Type, D3DPRESENT_PARAMETERS& PP)
{
	MSM_ReadSettings();

	PP.PresentationInterval = g_vsync ? D3DPRESENT_INTERVAL_ONE : D3DPRESENT_INTERVAL_IMMEDIATE;

	D3DDISPLAYMODE Desktop = {};
	if (D3D)
		D3D->GetAdapterDisplayMode(Adapter, &Desktop);

	if (!PP.Windowed && g_borderless && D3D)
	{
		PP.Windowed = TRUE;
		PP.FullScreen_RefreshRateInHz = 0;
		if (PP.BackBufferFormat != D3DFMT_X8R8G8B8 && PP.BackBufferFormat != D3DFMT_A8R8G8B8)
			PP.BackBufferFormat = Desktop.Format != D3DFMT_UNKNOWN ? Desktop.Format : D3DFMT_X8R8G8B8;
		g_place.Pending = true;
		g_place.Adapter = Adapter;
		g_place.Wnd = PP.hDeviceWindow ? PP.hDeviceWindow : g_focusWnd;
		g_place.W = PP.BackBufferWidth;
		g_place.H = PP.BackBufferHeight;
	}
	else if (!PP.Windowed && D3D)
	{
		// without a request D3D picks the display's default (often 60 Hz): take the desktop rate, or the one asked for
		const D3DFORMAT Fmt = DisplayFormatFor(PP.BackBufferFormat);
		UINT Want = g_refresh > 0 ? (UINT)g_refresh : (g_maxHz ? g_maxHz : Desktop.RefreshRate);
		if (g_maxHz && Want > g_maxHz)
			Want = g_maxHz;
		if (Want)
		{
			const UINT Rate = PickRefresh(D3D, Adapter, Fmt, PP.BackBufferWidth, PP.BackBufferHeight, Want);
			if (Rate)
				PP.FullScreen_RefreshRateInHz = Rate;
		}
	}
	g_windowed = PP.Windowed != FALSE;
	g_dispHz = PP.Windowed ? Desktop.RefreshRate : (PP.FullScreen_RefreshRateInHz ? PP.FullScreen_RefreshRateInHz : Desktop.RefreshRate);
	if (g_dispHz < 24)
		g_dispHz = 60;

	PP.MultiSampleType = D3DMULTISAMPLE_NONE;
	PP.MultiSampleQuality = 0;
	if (g_msaa >= 2 && D3D)
	{
		D3DFORMAT BackFormat = PP.BackBufferFormat;
		if (BackFormat == D3DFMT_UNKNOWN)
			BackFormat = Desktop.Format;
		for (int Samples = g_msaa > 8 ? 8 : g_msaa; Samples >= 2; Samples /= 2)
		{
			const D3DMULTISAMPLE_TYPE MS = (D3DMULTISAMPLE_TYPE)Samples;
			if (SUCCEEDED(D3D->CheckDeviceMultiSampleType(Adapter, Type, BackFormat, PP.Windowed, MS, nullptr)) &&
				(!PP.EnableAutoDepthStencil ||
				 SUCCEEDED(D3D->CheckDeviceMultiSampleType(Adapter, Type, PP.AutoDepthStencilFormat, PP.Windowed, MS, nullptr))))
			{
				PP.MultiSampleType = MS;
				PP.SwapEffect = D3DSWAPEFFECT_DISCARD;
				PP.Flags &= ~D3DPRESENTFLAG_LOCKABLE_BACKBUFFER;
				break;
			}
		}
	}
	MSM_RLog("  swap effect %d, buffers %u, flags 0x%lx, depth format %d\n", (int)PP.SwapEffect, PP.BackBufferCount, (unsigned long)PP.Flags, (int)PP.AutoDepthStencilFormat);
	MSM_RLog("device settings: %ux%u %s%s @%uHz, MSAA %d (asked %d), VSync %d, anisotropy %d, frame limit %d, FXAA %d, sharpen %d\n",
		PP.BackBufferWidth, PP.BackBufferHeight, PP.Windowed ? "windowed" : "fullscreen", PP.Windowed && g_borderless ? " (borderless)" : "",
		g_dispHz, (int)PP.MultiSampleType, g_msaa, g_vsync, g_aniso, g_frameLimit, g_postAA, g_sharpen);
}

void MSM_AdjustPresentParams(IDirect3DDevice9* Dev, D3DPRESENT_PARAMETERS& PP)
{
	IDirect3D9* D3D = nullptr;
	D3DDEVICE_CREATION_PARAMETERS CP = {};
	Dev->GetDirect3D(&D3D);
	Dev->GetCreationParameters(&CP);
	g_focusWnd = CP.hFocusWindow;
	MSM_AdjustPresentParams(D3D, CP.AdapterOrdinal, CP.DeviceType, PP);
	if (D3D)
		D3D->Release();
}

void MSM_SetFocusWindow(HWND Wnd) { g_focusWnd = Wnd; }

//-----------------------------------------------------------------------------
// texture filtering

// texture filter states as the game sets them, with anisotropic filtering forced in
DWORD MSM_SamplerValue(D3DSAMPLERSTATETYPE Type, DWORD Value)
{
	Ensure();
	if (g_aniso <= 1)
		return Value;
	if (Type == D3DSAMP_MINFILTER && Value == D3DTEXF_LINEAR)
		return D3DTEXF_ANISOTROPIC;
	if (Type == D3DSAMP_MAXANISOTROPY)
		return (DWORD)(g_aniso > 16 ? 16 : g_aniso) > Value ? (DWORD)(g_aniso > 16 ? 16 : g_aniso) : Value;
	return Value;
}

// stage filter set up: the max anisotropy must be set alongside the filter
void MSM_ApplyAnisotropy(IDirect3DDevice9* Dev, DWORD Stage)
{
	Ensure();
	if (g_aniso > 1)
		Dev->SetSamplerState(Stage, D3DSAMP_MAXANISOTROPY, g_aniso > 16 ? 16 : g_aniso);
}

// the game's mip LOD bias with the extra sharpening bias added (the bias is a float in a DWORD)
DWORD MSM_MipBias(DWORD Value)
{
	Ensure();
	if (g_mipBias <= 0)
		return Value;
	float Bias;
	memcpy(&Bias, &Value, sizeof(Bias));
	Bias -= g_mipBias >= 2 ? 1.0f : 0.5f;
	DWORD Out;
	memcpy(&Out, &Bias, sizeof(Out));
	return Out;
}

//-----------------------------------------------------------------------------
// reading back a multisampled back buffer (the game's ReadPixels locks it every so often)

static IDirect3DSurface9* g_lockTmp;          // lockable, single-sample copy
static IDirect3DSurface9* g_lockSrc;          // surface currently locked through the copy
static UINT g_lockW, g_lockH;
static D3DFORMAT g_lockFmt;

HRESULT MSM_LockRectFallback(IDirect3DSurface9* Surf, D3DLOCKED_RECT* Locked, const RECT* Rect, HRESULT Failed)
{
	D3DSURFACE_DESC D;
	if (FAILED(Surf->GetDesc(&D)) || D.MultiSampleType == D3DMULTISAMPLE_NONE || D.Pool != D3DPOOL_DEFAULT)
		return Failed;
	IDirect3DDevice9* Dev = nullptr;
	if (FAILED(Surf->GetDevice(&Dev)))
		return Failed;
	HRESULT Hr = Failed;
	if (!g_lockTmp || g_lockW != D.Width || g_lockH != D.Height || g_lockFmt != D.Format)
	{
		if (g_lockTmp) { g_lockTmp->Release(); g_lockTmp = nullptr; }
		if (SUCCEEDED(Dev->CreateRenderTarget(D.Width, D.Height, D.Format, D3DMULTISAMPLE_NONE, 0, TRUE, &g_lockTmp, nullptr)))
		{
			g_lockW = D.Width;
			g_lockH = D.Height;
			g_lockFmt = D.Format;
		}
	}
	if (g_lockTmp && SUCCEEDED(Dev->StretchRect(Surf, nullptr, g_lockTmp, nullptr, D3DTEXF_NONE)) &&
		SUCCEEDED(g_lockTmp->LockRect(Locked, Rect, D3DLOCK_READONLY)))
	{
		g_lockSrc = Surf;
		Hr = D3D_OK;
	}
	Dev->Release();
	return Hr;
}

bool MSM_UnlockRectFallback(IDirect3DSurface9* Surf)
{
	if (!g_lockSrc || g_lockSrc != Surf)
		return false;
	g_lockTmp->UnlockRect();
	g_lockSrc = nullptr;
	return true;
}

//-----------------------------------------------------------------------------
// frame limiter

// called after each Present
void MSM_FrameLimit()
{
	static LARGE_INTEGER Freq, Next;
	Ensure();
	int Limit = g_frameLimit;
	if (Limit < 0)   // auto: just under the refresh rate so adaptive sync never hits its ceiling; VSync needs no cap
		Limit = g_vsync ? 0 : (int)g_dispHz - 3;
	if (Limit <= 0)
	{
		Next.QuadPart = 0;
		return;
	}
	if (!Freq.QuadPart)
	{
		QueryPerformanceFrequency(&Freq);
		timeBeginPeriod(1);   // 1 ms sleeps
	}
	const LONGLONG Period = Freq.QuadPart / Limit;
	LARGE_INTEGER Now;
	QueryPerformanceCounter(&Now);
	if (Next.QuadPart == 0 || Now.QuadPart - Next.QuadPart > Period * 4)
		Next.QuadPart = Now.QuadPart;
	Next.QuadPart += Period;
	for (;;)
	{
		QueryPerformanceCounter(&Now);
		const LONGLONG Left = Next.QuadPart - Now.QuadPart;
		if (Left <= 0)
			break;
		const LONGLONG Ms = Left * 1000 / Freq.QuadPart;
		if (Ms > 2)
			Sleep((DWORD)(Ms - 1));
		else
			YieldProcessor();
	}
}

//-----------------------------------------------------------------------------
// post pass: FXAA, sharpening, gamma ramp

static D3DGAMMARAMP g_ramp;
static bool g_rampSet, g_rampIdentity = true;
static bool g_rampDirty;

static IDirect3DTexture9* g_rampTex;         // managed, survives Reset
static IDirect3DTexture9* g_fxTex;           // copy of the finished frame
static IDirect3DSurface9* g_fxSurf;
static IDirect3DPixelShader9* g_fxPS;
static IDirect3DStateBlock9* g_fxState;
static UINT g_fxW, g_fxH;
static D3DFORMAT g_fxFmt;
static bool g_fxBroken;
static int g_fxSkip;                 // frames left alone after a device reset / creation
static bool g_fxDidPost;             // the back buffer holds the processed frame until MSM_AfterPresent

// The game sets its gamma / brightness / contrast as a hardware gamma ramp. Windowed and borderless
// devices ignore that on current drivers, so the ramp is kept and applied by the post pass instead.
// Returns true when the hardware call must be skipped.
bool MSM_OnSetGammaRamp(const D3DGAMMARAMP* Ramp)
{
	if (!Ramp)
		return false;
	g_ramp = *Ramp;
	g_rampSet = true;
	g_rampDirty = true;
	bool Identity = true;
	for (int i = 0; i < 256; i++)
	{
		const int Id = i * 257;
		if (abs((int)Ramp->red[i] - Id) > 400 || abs((int)Ramp->green[i] - Id) > 400 || abs((int)Ramp->blue[i] - Id) > 400)
		{
			Identity = false;
			break;
		}
	}
	g_rampIdentity = Identity;
	return g_windowed;
}

static void ReleaseFxResources()
{
	if (g_fxState) { g_fxState->Release(); g_fxState = nullptr; }
	if (g_fxSurf) { g_fxSurf->Release(); g_fxSurf = nullptr; }
	if (g_fxTex) { g_fxTex->Release(); g_fxTex = nullptr; }
	g_fxW = g_fxH = 0;
}

// before IDirect3DDevice9::Reset
void MSM_GraphicsOnReset()
{
	ReleaseFxResources();
	g_fxSkip = 8;
	if (g_lockTmp) { g_lockTmp->Release(); g_lockTmp = nullptr; }
	g_lockSrc = nullptr;
	g_fxBroken = false;
}

static bool UpdateRampTexture(IDirect3DDevice9* Dev)
{
	if (!g_rampTex && FAILED(Dev->CreateTexture(256, 1, 1, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &g_rampTex, nullptr)))
		return false;
	if (!g_rampDirty && g_rampSet)
		return true;
	D3DLOCKED_RECT LR;
	if (FAILED(g_rampTex->LockRect(0, &LR, nullptr, 0)))
		return false;
	DWORD* Px = (DWORD*)LR.pBits;
	for (int i = 0; i < 256; i++)
	{
		const DWORD R = g_rampSet ? (g_ramp.red[i] >> 8) : i;
		const DWORD G = g_rampSet ? (g_ramp.green[i] >> 8) : i;
		const DWORD B = g_rampSet ? (g_ramp.blue[i] >> 8) : i;
		Px[i] = 0xFF000000u | (R << 16) | (G << 8) | B;
	}
	g_rampTex->UnlockRect(0);
	g_rampDirty = false;
	return true;
}

struct FxVertex { float x, y, z, rhw, u, v; };

// The menus only redraw the parts of the screen that change and rely on the rest of the back buffer
// staying as they left it. The post pass wrote over it, so the untouched frame is put back after Present
// (otherwise every frame would be processed again on top of the last processed one).
void MSM_AfterPresent(IDirect3DDevice9* Dev)
{
	if (!g_fxDidPost)
		return;
	g_fxDidPost = false;
	if (!g_fxSurf)
		return;
	IDirect3DSurface9* BB = nullptr;
	if (SUCCEEDED(Dev->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &BB)))
	{
		D3DSURFACE_DESC D;
		if (SUCCEEDED(BB->GetDesc(&D)) && D.MultiSampleType == D3DMULTISAMPLE_NONE)
			Dev->StretchRect(g_fxSurf, nullptr, BB, nullptr, D3DTEXF_NONE);
		BB->Release();
	}
}

// Runs on the finished frame right before Present.
void MSM_PostFX(IDirect3DDevice9* Dev)
{
	Ensure();
	const bool UseRamp = g_windowed && g_rampSet && !g_rampIdentity;
	if (g_fxSkip > 0)
	{
		g_fxSkip--;
		return;
	}
	if (g_noPost || g_fxBroken || (!g_postAA && g_sharpen <= 0 && !UseRamp))
		return;

	IDirect3DSurface9* BB = nullptr;
	if (FAILED(Dev->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &BB)))
		return;
	D3DSURFACE_DESC D;
	BB->GetDesc(&D);

	bool Ok = UpdateRampTexture(Dev);
	if (Ok && (!g_fxTex || g_fxW != D.Width || g_fxH != D.Height || g_fxFmt != D.Format))
	{
		ReleaseFxResources();
		Ok = SUCCEEDED(Dev->CreateTexture(D.Width, D.Height, 1, D3DUSAGE_RENDERTARGET, D.Format, D3DPOOL_DEFAULT, &g_fxTex, nullptr)) &&
			SUCCEEDED(g_fxTex->GetSurfaceLevel(0, &g_fxSurf)) &&
			SUCCEEDED(Dev->CreateStateBlock(D3DSBT_ALL, &g_fxState));
		g_fxW = D.Width;
		g_fxH = D.Height;
		g_fxFmt = D.Format;
		if (Ok && !g_fxPS)
			Ok = SUCCEEDED(Dev->CreatePixelShader((const DWORD*)g_postfxPS, &g_fxPS));
	}
	if (!Ok)
	{
		MSM_RLog("post pass unavailable (resources), disabled until the next device reset\n");
		g_fxBroken = true;
		BB->Release();
		return;
	}

	IDirect3DSurface9 *OldRT = nullptr, *OldDS = nullptr;
	Dev->GetRenderTarget(0, &OldRT);
	Dev->GetDepthStencilSurface(&OldDS);
	g_fxState->Capture();

	const HRESULT Hr = Dev->StretchRect(BB, nullptr, g_fxSurf, nullptr, D3DTEXF_NONE);
	const bool InScene = SUCCEEDED(Dev->BeginScene());
	if (SUCCEEDED(Hr))
	{
		Dev->SetRenderTarget(0, BB);
		Dev->SetDepthStencilSurface(nullptr);
		D3DVIEWPORT9 VP = { 0, 0, D.Width, D.Height, 0.0f, 1.0f };
		Dev->SetViewport(&VP);

		Dev->SetRenderState(D3DRS_ZENABLE, D3DZB_FALSE);
		Dev->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
		Dev->SetRenderState(D3DRS_STENCILENABLE, FALSE);
		Dev->SetRenderState(D3DRS_ALPHABLENDENABLE, FALSE);
		Dev->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
		Dev->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
		Dev->SetRenderState(D3DRS_FOGENABLE, FALSE);
		Dev->SetRenderState(D3DRS_LIGHTING, FALSE);
		Dev->SetRenderState(D3DRS_CLIPPLANEENABLE, 0);
		Dev->SetRenderState(D3DRS_SCISSORTESTENABLE, FALSE);
		Dev->SetRenderState(D3DRS_COLORWRITEENABLE, 0xF);
		Dev->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
		Dev->SetRenderState(D3DRS_FILLMODE, D3DFILL_SOLID);
		for (DWORD S = 0; S < 2; S++)
		{
			Dev->SetSamplerState(S, D3DSAMP_MINFILTER, S ? D3DTEXF_POINT : D3DTEXF_LINEAR);
			Dev->SetSamplerState(S, D3DSAMP_MAGFILTER, S ? D3DTEXF_POINT : D3DTEXF_LINEAR);
			Dev->SetSamplerState(S, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
			Dev->SetSamplerState(S, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
			Dev->SetSamplerState(S, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
			Dev->SetSamplerState(S, D3DSAMP_SRGBTEXTURE, FALSE);
		}
		Dev->SetTexture(0, g_fxTex);
		Dev->SetTexture(1, g_rampTex);
		Dev->SetVertexShader(nullptr);
		Dev->SetFVF(D3DFVF_XYZRHW | D3DFVF_TEX1);
		Dev->SetPixelShader(g_fxPS);

		static const float kSharp[4] = { 0.0f, 0.25f, 0.5f, 0.9f };
		const float C0[4] = { 1.0f / D.Width, 1.0f / D.Height, kSharp[g_sharpen < 0 ? 0 : (g_sharpen > 3 ? 3 : g_sharpen)], g_postAA ? 1.0f : 0.0f };
		const float C1[4] = { UseRamp ? 1.0f : 0.0f, 0, 0, 0 };
		Dev->SetPixelShaderConstantF(0, C0, 1);
		Dev->SetPixelShaderConstantF(1, C1, 1);

		const float W = (float)D.Width - 0.5f, H = (float)D.Height - 0.5f;
		const FxVertex Quad[4] = {
			{ -0.5f, -0.5f, 0.0f, 1.0f, 0.0f, 0.0f },
			{ W, -0.5f, 0.0f, 1.0f, 1.0f, 0.0f },
			{ -0.5f, H, 0.0f, 1.0f, 0.0f, 1.0f },
			{ W, H, 0.0f, 1.0f, 1.0f, 1.0f },
		};
		Dev->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, Quad, sizeof(FxVertex));
		g_fxDidPost = true;
	}
	if (InScene)
		Dev->EndScene();

	// give the game back exactly the state it had
	Dev->SetRenderTarget(0, OldRT);
	Dev->SetDepthStencilSurface(OldDS);
	g_fxState->Apply();

	if (OldRT) OldRT->Release();
	if (OldDS) OldDS->Release();
	BB->Release();
}
