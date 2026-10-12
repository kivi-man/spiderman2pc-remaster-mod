// Driver-level graphics options for Spider-Man 2, set from the MSM settings page
// (MSMSpidey.MSMSettings, saved in System/MSMSpidey.ini):
//   MSAA        0/2/4/8   multisampled back buffer (applied on device creation / reset)
//   bVSync                present on vertical blank (creation / reset)
//   Anisotropy  1..16     anisotropic texture filtering (live)
//   FrameLimit  0 = off   frame rate cap (live)
#include <d3d9.h>
#include <mmsystem.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char* kIni = ".\\MSMSpidey.ini";
static const char* kSection = "MSMSpidey.MSMSettings";

static const bool kMsaaEnabled = false;
static int g_msaa, g_aniso = 8, g_vsync, g_frameLimit;
static int g_reflections = 1, g_mirror = 1;
static bool g_read;

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

// called with the converted D3D9 present parameters before CreateDevice / Reset
void MSM_AdjustPresentParams(IDirect3D9* D3D, UINT Adapter, D3DDEVTYPE Type, D3DPRESENT_PARAMETERS& PP)
{
	MSM_ReadSettings();

	PP.PresentationInterval = g_vsync ? D3DPRESENT_INTERVAL_ONE : D3DPRESENT_INTERVAL_IMMEDIATE;

	PP.MultiSampleType = D3DMULTISAMPLE_NONE;
	PP.MultiSampleQuality = 0;
	// MSAA is off for now: with 8x the game's own CreateTexture fails (appError 80004005).
	// Re-enable only after that is fixed and tested in game.
	if (kMsaaEnabled && g_msaa >= 2 && D3D)
	{
		D3DFORMAT BackFormat = PP.BackBufferFormat;
		if (BackFormat == D3DFMT_UNKNOWN)
		{
			D3DDISPLAYMODE Mode;
			if (SUCCEEDED(D3D->GetAdapterDisplayMode(Adapter, &Mode)))
				BackFormat = Mode.Format;
		}
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
	MSM_RLog("device settings: %ux%u %s, MSAA %d (asked %d), VSync %d, anisotropy %d, frame limit %d\n",
		PP.BackBufferWidth, PP.BackBufferHeight, PP.Windowed ? "windowed" : "fullscreen",
		(int)PP.MultiSampleType, g_msaa, g_vsync, g_aniso, g_frameLimit);
}

void MSM_AdjustPresentParams(IDirect3DDevice9* Dev, D3DPRESENT_PARAMETERS& PP)
{
	IDirect3D9* D3D = nullptr;
	D3DDEVICE_CREATION_PARAMETERS CP = {};
	Dev->GetDirect3D(&D3D);
	Dev->GetCreationParameters(&CP);
	MSM_AdjustPresentParams(D3D, CP.AdapterOrdinal, CP.DeviceType, PP);
	if (D3D)
		D3D->Release();
}

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

// called after each Present
void MSM_FrameLimit()
{
	static LARGE_INTEGER Freq, Next;
	Ensure();
	if (g_frameLimit <= 0)
	{
		Next.QuadPart = 0;
		return;
	}
	if (!Freq.QuadPart)
	{
		QueryPerformanceFrequency(&Freq);
		timeBeginPeriod(1);   // 1 ms sleeps
	}
	const LONGLONG Period = Freq.QuadPart / g_frameLimit;
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
