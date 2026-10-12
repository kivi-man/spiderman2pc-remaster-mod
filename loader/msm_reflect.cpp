// Dynamic reflections for Spider-Man 2 (2004).
//
// The game reflects one pre-shot cubemap per district on every car and window.
// MSMSpidey (MSMSpideyController.RenderTexture) renders into a 1024x1024
// two ScriptedTextures every frame:
//   2048x1024: 6 cube faces of 512x512 around the camera, laid out for the D3D
//              cube convention with D3D (X,Y,Z) = Unreal world (Y,Z,X);
//   2048x2048: the wall in view as a mirror, rendered at screen resolution from
//              the camera reflected through the wall plane.
// Here, at the D3D9 level (d3d8to9), the atlas is copied into our own textures at
// Present and used in place of the stock env cubemaps:
//   - surfaces lying in the mirror plane get the planar image, projected through
//     the mirrored camera (a true mirror: right side up, right distance, player
//     visible); the plane is recovered from the two cameras' view matrices;
//   - everything else gets the live cube, looked up with a texture matrix that
//     matches the face layout above (world-space reflection vector).
// The plane split is done with user clip planes (3 passes for reflective draws).
#include <d3d9.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <math.h>

static const UINT kAtlasW = 2048, kAtlasH = 1024, kFace = 512;   // cube faces, 4x2 cells
static const UINT kMirW = 2048, kMirH = 2048;                    // mirror view (screen-sized viewport inside)
static const float kSlab = 48.0f;     // uu either side of the mirror plane that count as "on the mirror"
static const float kClipBias = 2.0f;  // the mirrored view keeps only what is in front of the wall

struct Vec3 { float x, y, z; };
static Vec3 V3(float x, float y, float z) { Vec3 r = { x, y, z }; return r; }
static Vec3 Sub(Vec3 a, Vec3 b) { return V3(a.x - b.x, a.y - b.y, a.z - b.z); }
static Vec3 Add(Vec3 a, Vec3 b) { return V3(a.x + b.x, a.y + b.y, a.z + b.z); }
static Vec3 Mul(Vec3 a, float s) { return V3(a.x * s, a.y * s, a.z * s); }
static float Dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static float Len(Vec3 a) { return sqrtf(Dot(a, a)); }
static Vec3 Norm(Vec3 a) { float l = Len(a); return l > 1e-6f ? Mul(a, 1.0f / l) : a; }

static D3DMATRIX MatMul(const D3DMATRIX& a, const D3DMATRIX& b)
{
	D3DMATRIX r;
	for (int i = 0; i < 4; i++)
		for (int j = 0; j < 4; j++)
			r.m[i][j] = a.m[i][0] * b.m[0][j] + a.m[i][1] * b.m[1][j] + a.m[i][2] * b.m[2][j] + a.m[i][3] * b.m[3][j];
	return r;
}

static bool MatInverse(const D3DMATRIX& M, D3DMATRIX& Out)
{
	const float* m = &M.m[0][0];
	float inv[16];
	inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
	inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
	inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
	inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
	inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
	inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
	inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
	inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
	inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
	inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
	inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
	inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
	inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
	inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
	inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
	inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
	float det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
	if (fabsf(det) < 1e-12f)
		return false;
	det = 1.0f / det;
	for (int i = 0; i < 16; i++)
		(&Out.m[0][0])[i] = inv[i] * det;
	return true;
}

// camera position / forward / up in world space from a (row vector) view matrix
struct Cam { Vec3 pos, fwd, up; };
static bool CamFromView(const D3DMATRIX& View, Cam& C)
{
	D3DMATRIX I;
	if (!MatInverse(View, I))
		return false;
	C.pos = V3(I._41, I._42, I._43);
	C.fwd = Norm(V3(I._31, I._32, I._33));
	C.up = Norm(V3(I._21, I._22, I._23));
	return true;
}

static bool IsPerspective(const D3DMATRIX& P) { return P._34 != 0.0f && P._44 == 0.0f; }

// The mirrored camera must be the main camera reflected through the plane that
// bisects the two positions. Gives that plane (normal towards the main camera).
static bool MirrorPlane(const Cam& Main, const Cam& Mir, Vec3& N, float& D)
{
	Vec3 Delta = Sub(Main.pos, Mir.pos);
	if (Len(Delta) < 4.0f)
		return false;
	N = Norm(Delta);
	Vec3 Fr = Sub(Main.fwd, Mul(N, 2 * Dot(Main.fwd, N)));
	Vec3 Ur = Sub(Main.up, Mul(N, 2 * Dot(Main.up, N)));
	if (Dot(Fr, Mir.fwd) < 0.98f || Dot(Ur, Mir.up) < 0.98f)
		return false;
	D = -Dot(N, Mul(Add(Main.pos, Mir.pos), 0.5f));   // plane: dot(N,P) + D = 0
	return true;
}

static IDirect3DTexture9* g_atlas;      // the game's render target for the cube faces (AddRef'd)
static IDirect3DTexture9* g_mirrorRT;   // the game's render target for the mirror view (AddRef'd)
static IDirect3DCubeTexture9* g_cube;   // live cube
static IDirect3DTexture9* g_planar;     // live mirror image
static UINT g_planarW, g_planarH;
static int g_atlasFrames;
static bool g_ready;
static int g_enabled = -1, g_planarEnabled = -1, g_cfgMips = 1, g_cfgDebug = 0, g_cfgOverride = 1;
static FILE* g_rlog;
static int g_rtLogged;
static IDirect3DBaseTexture9* g_seenCubes[64];
static int g_seenCount;

// per-stage: a stock env cube is bound there (we bound g_cube instead)
static bool g_stageCube[8];
static IDirect3DBaseTexture9* g_stockCubes[64];
static int g_stockCount;

// render target / viewport tracking
static int g_rtKind = 2;                // 0 other render target, 1 cube atlas, 2 back buffer, 3 mirror
static bool g_inPlanar;
static D3DVIEWPORT9 g_planarVP;

// per-frame view statistics (the view used by most draws wins)
struct ViewSlot { D3DMATRIX v, p; int n; };
struct ViewHist
{
	ViewSlot s[8];
	int count;
	void Reset() { count = 0; }
	void Add(const D3DMATRIX& v, const D3DMATRIX& p)
	{
		for (int i = 0; i < count; i++)
			if (!memcmp(&s[i].v, &v, sizeof(v)))
			{
				s[i].n++;
				s[i].p = p;
				return;
			}
		if (count < 8)
		{
			s[count].v = v;
			s[count].p = p;
			s[count].n = 1;
			count++;
		}
	}
	const ViewSlot* Best() const
	{
		const ViewSlot* b = nullptr;
		for (int i = 0; i < count; i++)
			if (!b || s[i].n > b->n)
				b = &s[i];
		return b;
	}
};
static ViewHist g_mainHist, g_planarHist;

// mirror state from the last finished frame
static bool g_planarReady;
static D3DMATRIX g_planarVP_Matrix;     // mirrored camera's view * projection
static Vec3 g_planeN;
static float g_planeD;

// clip plane used while the mirrored view itself is rendered
static D3DMATRIX g_clipForView;
static bool g_clipValid, g_clipKnown;
static float g_clipPlane[4];

// caches of per-view texture matrices
static D3DMATRIX g_cacheView;
static bool g_cacheKnown, g_cacheOk;
static D3DMATRIX g_cubeTexM, g_planarTexM;

static int g_statPlanarDraws, g_statCubeDraws, g_statFrames, g_logFrames;
static int g_statNoMain, g_statNoMirror, g_statReject, g_statOk, g_statKind[4];

static void RLog(const char* Fmt, ...);

void MSM_RLog(const char* Fmt, ...)
{
	char Buf[512];
	va_list Ap;
	va_start(Ap, Fmt);
	vsnprintf(Buf, sizeof(Buf), Fmt, Ap);
	va_end(Ap);
	RLog("%s", Buf);
}

static void RLog(const char* Fmt, ...)
{
	if (!g_rlog)
		g_rlog = fopen("MSMReflections.log", "w");
	if (!g_rlog)
		return;
	va_list Ap;
	va_start(Ap, Fmt);
	vfprintf(g_rlog, Fmt, Ap);
	va_end(Ap);
	fflush(g_rlog);
}

void MSM_ReadSettings();
bool MSM_SettingReflections();
bool MSM_SettingMirror();

// On/off come from the MSM settings page (MSMSpidey.ini [MSMSpidey.MSMSettings]
// bReflections / bMirror). Test switches in MSMReflections.ini [MSMReflections]:
// Mips, Override (cube lookup), Debug (1 = show the mirror image raw on the mirror
// surfaces, 2 = show the cube raw everywhere). All re-read every 2 s.
static void ReadConfig()
{
	const char* Ini = ".\\MSMReflections.ini";
	MSM_ReadSettings();
	g_enabled = MSM_SettingReflections() ? 1 : 0;
	g_planarEnabled = MSM_SettingMirror() ? 1 : 0;
	g_cfgMips = GetPrivateProfileIntA("MSMReflections", "Mips", 1, Ini);
	g_cfgDebug = GetPrivateProfileIntA("MSMReflections", "Debug", 0, Ini);
	g_cfgOverride = GetPrivateProfileIntA("MSMReflections", "Override", 1, Ini);
}

static bool Enabled()
{
	if (g_enabled < 0)
		ReadConfig();
	return g_enabled != 0;
}

static void LogMatrix(const char* Name, const D3DMATRIX& M)
{
	RLog("  %s: [%.3f %.3f %.3f %.3f] [%.3f %.3f %.3f %.3f] [%.3f %.3f %.3f %.3f] [%.1f %.1f %.1f %.3f]\n", Name,
		M._11, M._12, M._13, M._14, M._21, M._22, M._23, M._24, M._31, M._32, M._33, M._34, M._41, M._42, M._43, M._44);
}

void MSM_OnCreateTexture(IDirect3DTexture9* Tex, UINT Width, UINT Height, DWORD OrigUsage)
{
	if (!Tex || !Enabled())
		return;
	if ((OrigUsage & D3DUSAGE_RENDERTARGET) && g_rtLogged < 40)
	{
		g_rtLogged++;
		RLog("render target texture %ux%u usage=0x%lx\n", Width, Height, OrigUsage);
	}
	if (Width == kAtlasW && Height == kAtlasH && (OrigUsage & D3DUSAGE_RENDERTARGET))
	{
		if (g_atlas)
			g_atlas->Release();
		g_atlas = Tex;
		g_atlas->AddRef();
		g_atlasFrames = 0;
		g_ready = false;
		g_planarReady = false;
		RLog("atlas found %p\n", Tex);
	}
	if (Width == kMirW && Height == kMirH && (OrigUsage & D3DUSAGE_RENDERTARGET))
	{
		if (g_mirrorRT)
			g_mirrorRT->Release();
		g_mirrorRT = Tex;
		g_mirrorRT->AddRef();
		g_planarReady = false;
		RLog("mirror render target found %p\n", Tex);
	}
}

IDirect3DBaseTexture9* MSM_FilterTexture(DWORD Stage, IDirect3DBaseTexture9* Tex)
{
	if (Stage < 8)
		g_stageCube[Stage] = false;
	if (!g_ready || !Enabled() || !Tex || Tex == g_cube || Tex->GetType() != D3DRTYPE_CUBETEXTURE)
		return Tex;

	int i;
	for (i = 0; i < g_stockCount && g_stockCubes[i] != Tex; i++) {}
	if (i == g_stockCount)
	{
		for (i = 0; i < g_seenCount && g_seenCubes[i] != Tex; i++) {}
		if (i < g_seenCount)
			return Tex;   // seen and rejected
		D3DSURFACE_DESC D;
		IDirect3DCubeTexture9* C = (IDirect3DCubeTexture9*)Tex;
		bool Env = SUCCEEDED(C->GetLevelDesc(0, &D)) && D.Width >= 64;
		RLog("stock cubemap %p edge %u levels %u format %d -> %s\n", Tex, Env ? D.Width : 0, C->GetLevelCount(), Env ? (int)D.Format : 0,
			Env ? "replaced" : "kept (not an environment map)");
		if (!Env)
		{
			if (g_seenCount < 64)
				g_seenCubes[g_seenCount++] = Tex;
			return Tex;
		}
		if (g_stockCount < 64)
			g_stockCubes[g_stockCount++] = Tex;
	}
	if (Stage < 8)
		g_stageCube[Stage] = true;
	return g_cube;
}

static void UpdateRenderTargetKind(IDirect3DDevice9* Dev)
{
	g_rtKind = 0;
	IDirect3DSurface9* RT = nullptr;
	if (FAILED(Dev->GetRenderTarget(0, &RT)) || !RT)
		return;
	IDirect3DSurface9* Atlas0 = nullptr;
	if (g_atlas && SUCCEEDED(g_atlas->GetSurfaceLevel(0, &Atlas0)))
	{
		if (Atlas0 == RT)
			g_rtKind = 1;
		Atlas0->Release();
	}
	if (g_rtKind == 0 && g_mirrorRT && SUCCEEDED(g_mirrorRT->GetSurfaceLevel(0, &Atlas0)))
	{
		if (Atlas0 == RT)
		{
			g_rtKind = 3;
			D3DSURFACE_DESC D;
			RT->GetDesc(&D);
			g_planarVP.X = g_planarVP.Y = 0;
			g_planarVP.Width = D.Width;
			g_planarVP.Height = D.Height;
		}
		Atlas0->Release();
	}
	if (g_rtKind == 0)
	{
		IDirect3DSurface9* BB = nullptr;
		if (SUCCEEDED(Dev->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &BB)) && BB)
		{
			if (BB == RT)
				g_rtKind = 2;
			BB->Release();
		}
	}
	RT->Release();
}

static IDirect3DSurface9* g_lastRT;     // identity only, not referenced
static int g_presents, g_traceDraws, g_tracePersp;
static bool Tracing() { return g_presents % 1800 >= 600 && g_presents % 1800 < 602; }

void MSM_OnSetRenderTarget(IDirect3DDevice9* Dev)
{
	if (!Enabled())
		return;
	if (Tracing())
		RLog("  SetRenderTarget (draws so far %d, perspective %d)\n", g_traceDraws, g_tracePersp);
	UpdateRenderTargetKind(Dev);
	g_inPlanar = g_rtKind == 3;
}

void MSM_OnSetViewport(IDirect3DDevice9* Dev, const D3DVIEWPORT9* VP)
{
	if (!Enabled() || !VP)
		return;
	g_inPlanar = g_rtKind == 3;
	if (g_inPlanar)
		g_planarVP = *VP;
	if (Tracing())
		RLog("  SetViewport %lu,%lu %lux%lu kind %d\n", VP->X, VP->Y, VP->Width, VP->Height, g_rtKind);
}

// texture matrices for the current camera (cached per view matrix)
static bool PrepareMatrices(const D3DMATRIX& View)
{
	if (g_cacheKnown && !memcmp(&g_cacheView, &View, sizeof(View)))
		return g_cacheOk;
	g_cacheKnown = true;
	g_cacheView = View;
	D3DMATRIX Inv;
	g_cacheOk = MatInverse(View, Inv);
	if (!g_cacheOk)
		return false;

	// cube: camera-space reflection vector -> world -> D3D cube axes (Y,Z,X of the world)
	memset(&g_cubeTexM, 0, sizeof(g_cubeTexM));
	for (int i = 0; i < 3; i++)
	{
		g_cubeTexM.m[i][0] = Inv.m[i][1];
		g_cubeTexM.m[i][1] = Inv.m[i][2];
		g_cubeTexM.m[i][2] = Inv.m[i][0];
	}
	g_cubeTexM._44 = 1;

	// planar: camera-space position -> world -> mirrored camera clip space -> texture (projected)
	D3DMATRIX Bias;
	memset(&Bias, 0, sizeof(Bias));
	Bias._11 = 0.5f;
	Bias._22 = -0.5f;
	Bias._41 = 0.5f;
	Bias._42 = 0.5f;
	Bias._43 = 1.0f;
	g_planarTexM = MatMul(MatMul(Inv, g_planarVP_Matrix), Bias);
	return true;
}

// state saved around a reflective draw
static struct
{
	bool active;
	int stage;
	DWORD tci, ttff, addrU, addrV, clipEnable, mip, cop, carg1;
	D3DMATRIX texM;
	float clip0[4], clip1[4];
	bool planar;
	bool clipOnly;
} g_sv;

static void SetClip(IDirect3DDevice9* Dev, DWORD Index, Vec3 N, float D)
{
	float P[4] = { N.x, N.y, N.z, D };
	Dev->SetClipPlane(Index, P);
}

int MSM_BeginDraw(IDirect3DDevice9* Dev, bool FixedFunction, DWORD GameClipPlanes)
{
	g_sv.active = false;
	g_sv.planar = false;
	g_sv.clipOnly = false;
	if (!g_atlas || !Enabled())
		return 1;

	// which render target this draw goes to (checked here, whatever way it was set)
	IDirect3DSurface9* RT = nullptr;
	if (SUCCEEDED(Dev->GetRenderTarget(0, &RT)) && RT)
	{
		if (RT != g_lastRT)
		{
			g_lastRT = RT;
			UpdateRenderTargetKind(Dev);
			g_inPlanar = g_rtKind == 3;
			if (Tracing())
			{
				D3DSURFACE_DESC D;
				RT->GetDesc(&D);
				RLog("  draws now go to %p %ux%u kind %d (after %d draws, %d perspective)\n", RT, D.Width, D.Height, g_rtKind, g_traceDraws, g_tracePersp);
			}
		}
		RT->Release();
	}

	D3DMATRIX View, Proj;
	Dev->GetTransform(D3DTS_VIEW, &View);
	Dev->GetTransform(D3DTS_PROJECTION, &Proj);
	const bool Persp = IsPerspective(Proj);
	if (Tracing())
	{
		g_traceDraws++;
		if (Persp)
			g_tracePersp++;
	}

	if (Persp && g_rtKind == 2)
		g_mainHist.Add(View, Proj);

	// while the mirrored view is drawn, drop everything behind the mirror
	bool ClipMirror = false;
	if (g_inPlanar && Persp)
	{
		g_planarHist.Add(View, Proj);
		Dev->GetViewport(&g_planarVP);   // the portal's sub-rectangle (the RT viewport is reset afterwards)
		if (!g_clipKnown || memcmp(&g_clipForView, &View, sizeof(View)))
		{
			g_clipKnown = true;
			g_clipForView = View;
			g_clipValid = false;
			const ViewSlot* M = g_mainHist.Best();
			Cam Main, Mir;
			Vec3 N;
			float D;
			if (M && CamFromView(M->v, Main) && CamFromView(View, Mir) && MirrorPlane(Main, Mir, N, D))
			{
				g_clipValid = true;
				g_clipPlane[0] = N.x;
				g_clipPlane[1] = N.y;
				g_clipPlane[2] = N.z;
				g_clipPlane[3] = D - kClipBias;
			}
		}
		ClipMirror = g_clipValid && FixedFunction && GameClipPlanes == 0;
	}

	int Stage = -1;
	for (int i = 0; i < 8; i++)
		if (g_stageCube[i])
		{
			Stage = i;
			break;
		}

	if (Stage < 0 || !FixedFunction || !PrepareMatrices(View))
	{
		if (ClipMirror)
		{
			g_sv.active = true;
			g_sv.clipOnly = true;
			Dev->GetClipPlane(0, g_sv.clip0);
			Dev->GetRenderState(D3DRS_CLIPPLANEENABLE, &g_sv.clipEnable);
			Dev->SetClipPlane(0, g_clipPlane);
			Dev->SetRenderState(D3DRS_CLIPPLANEENABLE, 1);
		}
		return 1;
	}

	g_sv.active = true;
	g_sv.stage = Stage;
	g_statKind[g_rtKind & 3]++;
	Dev->GetTextureStageState(Stage, D3DTSS_TEXCOORDINDEX, &g_sv.tci);
	Dev->GetTextureStageState(Stage, D3DTSS_TEXTURETRANSFORMFLAGS, &g_sv.ttff);
	Dev->GetTransform((D3DTRANSFORMSTATETYPE)(D3DTS_TEXTURE0 + Stage), &g_sv.texM);
	Dev->GetSamplerState(Stage, D3DSAMP_ADDRESSU, &g_sv.addrU);
	Dev->GetSamplerState(Stage, D3DSAMP_ADDRESSV, &g_sv.addrV);
	Dev->GetClipPlane(0, g_sv.clip0);
	Dev->GetClipPlane(1, g_sv.clip1);
	Dev->GetRenderState(D3DRS_CLIPPLANEENABLE, &g_sv.clipEnable);
	Dev->GetSamplerState(Stage, D3DSAMP_MIPFILTER, &g_sv.mip);
	Dev->GetTextureStageState(Stage, D3DTSS_COLOROP, &g_sv.cop);
	Dev->GetTextureStageState(Stage, D3DTSS_COLORARG1, &g_sv.carg1);
	if (!g_cfgMips)
		Dev->SetSamplerState(Stage, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
	if (g_cfgDebug == 2)
	{
		Dev->SetTextureStageState(Stage, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
		Dev->SetTextureStageState(Stage, D3DTSS_COLORARG1, D3DTA_TEXTURE);
	}

	if (g_logFrames < 3 && g_rtKind == 2)
	{
		g_logFrames++;
		RLog("reflective draw: stage %d tci 0x%lx ttff 0x%lx\n", Stage, g_sv.tci, g_sv.ttff);
		LogMatrix("view", View);
		LogMatrix("proj", Proj);
		LogMatrix("stock tex matrix", g_sv.texM);
		for (int i = 0; i <= Stage; i++)
		{
			DWORD Co, C1, C2, Ao, A1, A2;
			Dev->GetTextureStageState(i, D3DTSS_COLOROP, &Co);
			Dev->GetTextureStageState(i, D3DTSS_COLORARG1, &C1);
			Dev->GetTextureStageState(i, D3DTSS_COLORARG2, &C2);
			Dev->GetTextureStageState(i, D3DTSS_ALPHAOP, &Ao);
			Dev->GetTextureStageState(i, D3DTSS_ALPHAARG1, &A1);
			Dev->GetTextureStageState(i, D3DTSS_ALPHAARG2, &A2);
			RLog("  stage %d: color op %lu (%lu, %lu) alpha op %lu (%lu, %lu)\n", i, Co, C1, C2, Ao, A1, A2);
		}
		DWORD Ab, Sb, Db, Tf;
		Dev->GetRenderState(D3DRS_ALPHABLENDENABLE, &Ab);
		Dev->GetRenderState(D3DRS_SRCBLEND, &Sb);
		Dev->GetRenderState(D3DRS_DESTBLEND, &Db);
		Dev->GetRenderState(D3DRS_TEXTUREFACTOR, &Tf);
		RLog("  blend %lu src %lu dst %lu tfactor 0x%08lx\n", Ab, Sb, Db, Tf);
	}

	// the live cube with a world-space lookup
	const DWORD Gen = g_sv.tci & 0xffff0000;
	if (g_cfgOverride)
	{
		if (Gen != D3DTSS_TCI_CAMERASPACENORMAL)
			Dev->SetTextureStageState(Stage, D3DTSS_TEXCOORDINDEX, D3DTSS_TCI_CAMERASPACEREFLECTIONVECTOR | Stage);
		Dev->SetTextureStageState(Stage, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_COUNT3);
		Dev->SetTransform((D3DTRANSFORMSTATETYPE)(D3DTS_TEXTURE0 + Stage), &g_cubeTexM);
	}
	if (ClipMirror)
	{
		Dev->SetClipPlane(0, g_clipPlane);
		Dev->SetRenderState(D3DRS_CLIPPLANEENABLE, 1);
	}

	if (g_rtKind == 2 && g_planarReady && g_planar && g_planarEnabled && GameClipPlanes == 0 && Gen != D3DTSS_TCI_CAMERASPACENORMAL)
	{
		g_sv.planar = true;
		g_statPlanarDraws++;
		return 3;
	}
	g_statCubeDraws++;
	return 1;
}

// pass 0: surfaces on the mirror plane (planar image); 1/2: in front of / behind it (cube)
void MSM_SetupPass(IDirect3DDevice9* Dev, int Pass)
{
	if (!g_sv.active || !g_sv.planar)
		return;
	const int S = g_sv.stage;
	if (Pass == 0)
	{
		Dev->SetTexture(S, g_planar);
		Dev->SetTextureStageState(S, D3DTSS_TEXCOORDINDEX, D3DTSS_TCI_CAMERASPACEPOSITION | S);
		Dev->SetTextureStageState(S, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_COUNT3 | D3DTTFF_PROJECTED);
		Dev->SetTransform((D3DTRANSFORMSTATETYPE)(D3DTS_TEXTURE0 + S), &g_planarTexM);
		Dev->SetSamplerState(S, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
		Dev->SetSamplerState(S, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
		SetClip(Dev, 0, g_planeN, g_planeD + kSlab);                    // dist >= -slab
		SetClip(Dev, 1, Mul(g_planeN, -1), -g_planeD + kSlab);          // dist <= slab
		Dev->SetRenderState(D3DRS_CLIPPLANEENABLE, 3);
		if (g_cfgDebug == 1)
		{
			Dev->SetTextureStageState(S, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
			Dev->SetTextureStageState(S, D3DTSS_COLORARG1, D3DTA_TEXTURE);
		}
	}
	else
	{
		Dev->SetTexture(S, g_cube);
		if (g_cfgDebug == 1)
		{
			Dev->SetTextureStageState(S, D3DTSS_COLOROP, g_sv.cop);
			Dev->SetTextureStageState(S, D3DTSS_COLORARG1, g_sv.carg1);
		}
		Dev->SetTextureStageState(S, D3DTSS_TEXCOORDINDEX, D3DTSS_TCI_CAMERASPACEREFLECTIONVECTOR | S);
		Dev->SetTextureStageState(S, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_COUNT3);
		Dev->SetTransform((D3DTRANSFORMSTATETYPE)(D3DTS_TEXTURE0 + S), &g_cubeTexM);
		Dev->SetSamplerState(S, D3DSAMP_ADDRESSU, g_sv.addrU);
		Dev->SetSamplerState(S, D3DSAMP_ADDRESSV, g_sv.addrV);
		if (Pass == 1)
			SetClip(Dev, 0, g_planeN, g_planeD - kSlab);                // dist >= slab
		else
			SetClip(Dev, 0, Mul(g_planeN, -1), -g_planeD - kSlab);      // dist <= -slab
		Dev->SetRenderState(D3DRS_CLIPPLANEENABLE, 1);
	}
}

void MSM_EndDraw(IDirect3DDevice9* Dev)
{
	if (!g_sv.active)
		return;
	g_sv.active = false;
	Dev->SetClipPlane(0, g_sv.clip0);
	Dev->SetRenderState(D3DRS_CLIPPLANEENABLE, g_sv.clipEnable);
	if (g_sv.clipOnly)
		return;
	const int S = g_sv.stage;
	Dev->SetClipPlane(1, g_sv.clip1);
	Dev->SetTexture(S, g_cube);
	Dev->SetTextureStageState(S, D3DTSS_TEXCOORDINDEX, g_sv.tci);
	Dev->SetTextureStageState(S, D3DTSS_TEXTURETRANSFORMFLAGS, g_sv.ttff);
	Dev->SetTransform((D3DTRANSFORMSTATETYPE)(D3DTS_TEXTURE0 + S), &g_sv.texM);
	Dev->SetSamplerState(S, D3DSAMP_ADDRESSU, g_sv.addrU);
	Dev->SetSamplerState(S, D3DSAMP_ADDRESSV, g_sv.addrV);
	Dev->SetSamplerState(S, D3DSAMP_MIPFILTER, g_sv.mip);
	Dev->SetTextureStageState(S, D3DTSS_COLOROP, g_sv.cop);
	Dev->SetTextureStageState(S, D3DTSS_COLORARG1, g_sv.carg1);
}

static void FinishPlanar(IDirect3DDevice9* Dev, IDirect3DSurface9* Src)
{
	g_planarReady = false;
	const ViewSlot* M = g_mainHist.Best();
	const ViewSlot* P = g_planarHist.Best();
	if (!g_planarEnabled)
		return;
	if (!M || !P)
	{
		if (!M) g_statNoMain++;
		if (!P) g_statNoMirror++;
		return;
	}
	Cam Main, Mir;
	Vec3 N;
	float D;
	if (!CamFromView(M->v, Main) || !CamFromView(P->v, Mir) || !MirrorPlane(Main, Mir, N, D))
	{
		g_statReject++;
		static int Logged;
		if (Logged++ < 5)
			RLog("mirror view rejected (main %.0f,%.0f,%.0f mirror %.0f,%.0f,%.0f)\n", Main.pos.x, Main.pos.y, Main.pos.z, Mir.pos.x, Mir.pos.y, Mir.pos.z);
		return;
	}

	// The portal fills the top-left W x H of the mirror target; same size rule as
	// MSMSpideyController.RenderTexture (screen size plus a 6% margin, at most 2048).
	UINT W = g_planarVP.Width, H = g_planarVP.Height;
	IDirect3DSurface9* BB = nullptr;
	if (SUCCEEDED(Dev->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &BB)) && BB)
	{
		D3DSURFACE_DESC BD;
		BB->GetDesc(&BD);
		BB->Release();
		float SW = BD.Width < 320 ? 320.0f : (float)BD.Width, SH = BD.Height < 240 ? 240.0f : (float)BD.Height;
		float Margin = 1.06f;
		if (2048.0f / SW < Margin) Margin = 2048.0f / SW;
		if (2048.0f / SH < Margin) Margin = 2048.0f / SH;
		W = (UINT)(SW * Margin);
		H = (UINT)(SH * Margin);
		g_planarVP.X = g_planarVP.Y = 0;
	}
	if (g_planar && (g_planarW != W || g_planarH != H))
	{
		g_planar->Release();
		g_planar = nullptr;
	}
	if (!g_planar)
	{
		D3DSURFACE_DESC Desc;
		if (FAILED(g_atlas->GetLevelDesc(0, &Desc)) ||
			FAILED(Dev->CreateTexture(W, H, 1, D3DUSAGE_RENDERTARGET, Desc.Format == D3DFMT_A8R8G8B8 ? D3DFMT_X8R8G8B8 : Desc.Format, D3DPOOL_DEFAULT, &g_planar, nullptr)))
			return;
		g_planarW = W;
		g_planarH = H;
		RLog("mirror texture %ux%u\n", W, H);
	}
	IDirect3DSurface9* Dst = nullptr;
	if (FAILED(g_planar->GetSurfaceLevel(0, &Dst)))
		return;
	RECT R = { (LONG)g_planarVP.X, (LONG)g_planarVP.Y, (LONG)(g_planarVP.X + W), (LONG)(g_planarVP.Y + H) };
	Dev->StretchRect(Src, &R, Dst, nullptr, D3DTEXF_NONE);
	Dst->Release();

	g_planarVP_Matrix = MatMul(P->v, P->p);
	g_planeN = N;
	g_planeD = D;
	g_planarReady = true;
	g_statOk++;
	g_cacheKnown = false;
	static int Logged;
	if (Logged++ < 3)
	{
		RLog("mirror plane n=(%.3f %.3f %.3f) d=%.1f, main cam %.0f,%.0f,%.0f, mirror cam %.0f,%.0f,%.0f\n", N.x, N.y, N.z, D,
			Main.pos.x, Main.pos.y, Main.pos.z, Mir.pos.x, Mir.pos.y, Mir.pos.z);
		LogMatrix("main view", M->v);
		LogMatrix("mirror view", P->v);
		LogMatrix("mirror proj", P->p);
		RLog("  mirror rect %ux%u\n", W, H);
	}
}

void MSM_OnPresent(IDirect3DDevice9* Dev)
{
	// settings changed in the game's menu arrive within 2 s
	static int ConfigTick;
	if (++ConfigTick >= 120)
	{
		ConfigTick = 0;
		ReadConfig();
	}
	if (!g_atlas || !Enabled())
		return;

	if (!g_cube)
	{
		D3DSURFACE_DESC D;
		if (FAILED(g_atlas->GetLevelDesc(0, &D)))
			return;
		// full mip chain, filled by hand below (autogen is not available for every format).
		// X8R8G8B8: the scene render leaves alpha at 0, the stock maps are opaque.
		const D3DFORMAT F = D.Format == D3DFMT_A8R8G8B8 ? D3DFMT_X8R8G8B8 : D.Format;
		if (FAILED(Dev->CreateCubeTexture(kFace, 0, D3DUSAGE_RENDERTARGET, F, D3DPOOL_DEFAULT, &g_cube, nullptr)))
		{
			if (FAILED(Dev->CreateCubeTexture(kFace, 1, D3DUSAGE_RENDERTARGET, F, D3DPOOL_DEFAULT, &g_cube, nullptr)))
				return;
		}
		RLog("cube format %d (atlas %d)\n", (int)F, (int)D.Format);
	}

	IDirect3DSurface9* Src = nullptr;
	if (FAILED(g_atlas->GetSurfaceLevel(0, &Src)))
		return;
	for (int i = 0; i < 6; i++)
	{
		RECT R;
		R.left = (i % 4) * kFace;
		R.top = (i / 4) * kFace;
		R.right = R.left + kFace;
		R.bottom = R.top + kFace;
		IDirect3DSurface9* Dst = nullptr;
		if (SUCCEEDED(g_cube->GetCubeMapSurface((D3DCUBEMAP_FACES)i, 0, &Dst)))
		{
			Dev->StretchRect(Src, &R, Dst, nullptr, D3DTEXF_NONE);
			Dst->Release();
		}
	}
	Src->Release();
	if (g_mirrorRT && SUCCEEDED(g_mirrorRT->GetSurfaceLevel(0, &Src)))
	{
		FinishPlanar(Dev, Src);
		Src->Release();
	}
	else
		g_planarReady = false;

	// downsample each face level by level (smooth, stable reflections in the distance)
	for (int i = 0; i < 6; i++)
	{
		for (UINT L = 1; L < g_cube->GetLevelCount(); L++)
		{
			IDirect3DSurface9 *Hi = nullptr, *Lo = nullptr;
			if (SUCCEEDED(g_cube->GetCubeMapSurface((D3DCUBEMAP_FACES)i, L - 1, &Hi)) &&
				SUCCEEDED(g_cube->GetCubeMapSurface((D3DCUBEMAP_FACES)i, L, &Lo)))
				Dev->StretchRect(Hi, nullptr, Lo, nullptr, D3DTEXF_LINEAR);
			if (Hi) Hi->Release();
			if (Lo) Lo->Release();
		}
	}

	if (Tracing())
		RLog("Present %d: %d draws, %d perspective; main views %d, mirror views %d\n", g_presents, g_traceDraws, g_tracePersp, g_mainHist.count, g_planarHist.count);
	g_presents++;
	g_traceDraws = g_tracePersp = 0;
	g_mainHist.Reset();
	g_planarHist.Reset();
	g_clipKnown = false;
	g_cacheKnown = false;

	if (++g_statFrames >= 600)
	{
		RLog("last 600 frames: %d mirror draws, %d cube draws; mirror ok %d, no main view %d, no mirror view %d, rejected %d; reflective draws by target other/atlas/back/mirror %d/%d/%d/%d, mirror rect %lu,%lu %lux%lu\n",
			g_statPlanarDraws, g_statCubeDraws, g_statOk, g_statNoMain, g_statNoMirror, g_statReject,
			g_statKind[0], g_statKind[1], g_statKind[2], g_statKind[3], g_planarVP.X, g_planarVP.Y, g_planarVP.Width, g_planarVP.Height);
		g_statFrames = g_statPlanarDraws = g_statCubeDraws = 0;
		g_statOk = g_statNoMain = g_statNoMirror = g_statReject = 0;
		g_statKind[0] = g_statKind[1] = g_statKind[2] = g_statKind[3] = 0;
	}

	// give the game a few frames to render every face once before showing it
	if (++g_atlasFrames > 8 && !g_ready)
	{
		g_ready = true;
		RLog("dynamic cube ready (%u levels)\n", g_cube->GetLevelCount());
	}
}

// Default-pool resources must be gone before IDirect3DDevice9::Reset.
void MSM_OnReset()
{
	g_ready = false;
	g_planarReady = false;
	g_rtKind = 2;
	g_inPlanar = false;
	g_lastRT = nullptr;
	for (int i = 0; i < 8; i++)
		g_stageCube[i] = false;
	if (g_cube)
	{
		g_cube->Release();
		g_cube = nullptr;
	}
	if (g_planar)
	{
		g_planar->Release();
		g_planar = nullptr;
	}
	if (g_atlas)
	{
		g_atlas->Release();
		g_atlas = nullptr;
	}
	if (g_mirrorRT)
	{
		g_mirrorRT->Release();
		g_mirrorRT = nullptr;
	}
}
