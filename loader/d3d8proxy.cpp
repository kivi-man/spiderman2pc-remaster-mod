// d3d8.dll proxy for Spider-Man 2 (2004, Webhead.exe, Unreal Engine 2).
// - Direct3D 8 is provided by d3d8to9 (third_party/d3d8to9, D3D8 -> D3D9), which also
//   hosts the dynamic reflection hooks (msm_reflect.cpp).
// - Hooks Webhead.exe's import of Core.dll!appInit. When the command line has
//   "-ucc=<Commandlet>" (e.g. -ucc=Editor.MakeCommandlet), it runs that commandlet
//   right after appInit using the game's own engine globals, then exits.
//   This replaces the ucc.exe the game never shipped.
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

typedef unsigned short TCHARU; // UE2 TCHAR is 16-bit (mangled as G)

#ifdef MSM_LEGACY_FORWARD
static HMODULE g_realD3D8;
#endif
static FILE* g_log;

static void Logf(const char* fmt, ...)
{
    if (!g_log) return;
    va_list ap; va_start(ap, fmt); vfprintf(g_log, fmt, ap); va_end(ap);
    fflush(g_log);
}

#ifdef MSM_LEGACY_FORWARD
static FARPROC Real(const char* name)
{
    if (!g_realD3D8)
    {
        wchar_t path[MAX_PATH];
        GetSystemDirectoryW(path, MAX_PATH);
        wcscat_s(path, L"\\d3d8.dll");
        g_realD3D8 = LoadLibraryW(path);
    }
    return g_realD3D8 ? GetProcAddress(g_realD3D8, name) : nullptr;
}

extern "C" void* __stdcall Proxy_Direct3DCreate8(UINT v)
{
    typedef void* (__stdcall* Fn)(UINT);
    Fn f = (Fn)Real("Direct3DCreate8");
    return f ? f(v) : nullptr;
}
extern "C" HRESULT __stdcall Proxy_ValidatePixelShader(void* a, void* b, BOOL c, void* d)
{
    typedef HRESULT(__stdcall* Fn)(void*, void*, BOOL, void*);
    Fn f = (Fn)Real("ValidatePixelShader");
    return f ? f(a, b, c, d) : E_FAIL;
}
extern "C" HRESULT __stdcall Proxy_ValidateVertexShader(void* a, void* b, void* c, BOOL d, void* e)
{
    typedef HRESULT(__stdcall* Fn)(void*, void*, void*, BOOL, void*);
    Fn f = (Fn)Real("ValidateVertexShader");
    return f ? f(a, b, c, d, e) : E_FAIL;
}
extern "C" void __stdcall Proxy_DebugSetMute()
{
    typedef void(__stdcall* Fn)();
    Fn f = (Fn)Real("DebugSetMute");
    if (f) f();
}

#endif // MSM_LEGACY_FORWARD

// ---------------------------------------------------------------------------
// appInit hook + commandlet runner

typedef void(__cdecl* AppInitFn)(const TCHARU*, const TCHARU*, void*, void*, void*, void*, void*, void* (*)(), int);
static AppInitFn g_realAppInit;

static const char* kAppInit =
    "?appInit@@YAXPBG0PAVFMalloc@@PAVFOutputDevice@@PAVFOutputDeviceError@@PAVFFeedbackContext@@PAVFFileManager@@P6APAVFConfigCache@@XZH@Z";

static int* CoreInt(const char* sym)
{
    return (int*)GetProcAddress(GetModuleHandleA("Core.dll"), sym);
}

static int RunCommandlet(const wchar_t* className, const wchar_t* parms)
{
    HMODULE core = GetModuleHandleA("Core.dll");
    typedef void* (__cdecl* StaticClassFn)();
    typedef void* (__cdecl* LoadClassFn)(void*, void*, const TCHARU*, const TCHARU*, DWORD, void*);
    typedef void* (__cdecl* ConstructFn)(void*, void*, int, DWORD, void*, void*, void*);
    typedef void* (__cdecl* TransientFn)();
    typedef int(__thiscall* MainFn)(void*, const TCHARU*);

    auto CommandletClass = (StaticClassFn)GetProcAddress(core, "?StaticClass@UCommandlet@@SAPAVUClass@@XZ");
    auto LoadClass = (LoadClassFn)GetProcAddress(core, "?StaticLoadClass@UObject@@SAPAVUClass@@PAV2@PAV1@PBG2KPAVUPackageMap@@@Z");
    auto Construct = (ConstructFn)GetProcAddress(core, "?StaticConstructObject@UObject@@SAPAV1@PAVUClass@@PAV1@VFName@@K1PAVFOutputDevice@@1@Z");
    auto Transient = (TransientFn)GetProcAddress(core, "?GetTransientPackage@UObject@@SAPAVUPackage@@XZ");
    void** baseVtbl = (void**)GetProcAddress(core, "??_7UCommandlet@@6B@");
    void* baseMain = GetProcAddress(core, "?Main@UCommandlet@@UAEHPBG@Z");
    void** pGError = (void**)GetProcAddress(core, "?GError@@3PAVFOutputDeviceError@@A");
    if (!CommandletClass || !LoadClass || !Construct || !Transient || !baseVtbl || !baseMain || !pGError)
    {
        Logf("missing Core.dll export\n");
        return 2;
    }

    int mainIdx = -1;
    for (int i = 0; i < 128; i++)
        if (baseVtbl[i] == baseMain) { mainIdx = i; break; }
    Logf("UCommandlet::Main vtable index = %d\n", mainIdx);
    if (mainIdx < 0) return 3;

    *CoreInt("?GIsUCC@@3HA") = 1;
    *CoreInt("?GIsClient@@3HA") = 0;
    *CoreInt("?GIsServer@@3HA") = 0;
    *CoreInt("?GIsEditor@@3HA") = 1;
    *CoreInt("?GLazyLoad@@3HA") = 1;
    *CoreInt("?GIsScriptable@@3HA") = 1;

    void* cls = LoadClass(CommandletClass(), nullptr, (const TCHARU*)className, nullptr, 0, nullptr);
    Logf("class %ls -> %p\n", className, cls);
    if (!cls) return 4;

    // UEditorEngine::MakeScripts "DowngradeClasses": a class whose ScriptText CRC
    // differs from its stored dependency CRC is marked uncompiled. The shipped
    // packages have their source stripped to " ", so every stock class would be
    // recompiled (and fail). Skip the CRC test; new classes (no dependencies yet)
    // are still compiled.
    if (BYTE* ed = (BYTE*)GetModuleHandleA("Editor.dll"))
    {
        BYTE* p = ed + (0x67c2fb37 - 0x67ba0000);
        if (p[0] == 0x75 && p[1] == 0x07)
        {
            DWORD old;
            VirtualProtect(p, 2, PAGE_EXECUTE_READWRITE, &old);
            p[0] = 0x90; p[1] = 0x90;
            VirtualProtect(p, 2, old, &old);
            Logf("patched MakeScripts CRC check\n");
        }
        else Logf("MakeScripts CRC check bytes not found (%02x %02x)\n", p[0], p[1]);
    }
    void* obj = Construct(cls, Transient(), 0, 0, nullptr, *pGError, nullptr);
    Logf("object -> %p\n", obj);
    if (!obj) return 5;
    MainFn mainFn = (MainFn)(*(void***)obj)[mainIdx];
    int rc = mainFn(obj, (const TCHARU*)parms);
    Logf("Main returned %d\n", rc);
    return rc;
}

#include "msmexec.inc"

// Tee an engine output device (GLog/GWarn) into ModLoader.log by cloning its
// vtable and swapping slot 0 (FOutputDevice::Serialize(const TCHAR*, EName)).
typedef void(__thiscall* SerializeFn)(void*, const TCHARU*, int);
struct TeeSlot { void* obj; SerializeFn orig; };
static TeeSlot g_tee[2];

template <int N>
static void __fastcall TeeSerialize(void* self, void* /*edx*/, const TCHARU* text, int ev)
{
    Logf("%ls\n", (const wchar_t*)text);
    g_tee[N].orig(self, text, ev);
}

template <int N>
static void TeeDevice(const char* globalSym)
{
    void** pDev = (void**)GetProcAddress(GetModuleHandleA("Core.dll"), globalSym);
    if (!pDev || !*pDev) return;
    if (g_tee[N].obj == *pDev) return;   // already teed (-modlog together with -ucc/-msmexec)
    void** vt = *(void***)*pDev;
    void** copy = (void**)VirtualAlloc(nullptr, 64 * sizeof(void*), MEM_COMMIT, PAGE_READWRITE);
    memcpy(copy, vt, 64 * sizeof(void*));
    g_tee[N].obj = *pDev;
    g_tee[N].orig = (SerializeFn)vt[0];
    copy[0] = (void*)&TeeSerialize<N>;
    *(void***)*pDev = copy;
}

// ---------------------------------------------------------------------------
// Controller override. The menus travel with ?Game=Webhead.WebheadGameInfo,
// whose default PlayerControllerClassName is "Webhead.SpideyPlayerController"
// (not config). Load that class once at startup, root it so it is never purged,
// and rewrite the default string in place to the MSM controller.

static const wchar_t kOldPC[] = L"Webhead.SpideyPlayerController";
static const wchar_t kNewPC[] = L"MSMSpidey.MSMSpideyController";
static_assert(sizeof(kNewPC) <= sizeof(kOldPC), "must fit in the old buffer");

static int FindFStringSlot(BYTE* obj, int maxBytes)
{
    for (int off = 0; off < maxBytes; off += 4)
    {
        __try
        {
            const wchar_t* data = *(const wchar_t**)(obj + off);
            int num = *(int*)(obj + off + 4);
            if (data && num == (int)(sizeof(kOldPC) / sizeof(wchar_t)) && wcscmp(data, kOldPC) == 0)
                return off;
        }
        __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
    return -1;
}

static void InstallControllerOverride()
{
    if (GetFileAttributesW(L"MSMSpidey.u") == INVALID_FILE_ATTRIBUTES)
    {
        Logf("MSM: MSMSpidey.u missing, controller override off\n");
        return;
    }
    HMODULE core = GetModuleHandleA("Core.dll");
    typedef void* (__cdecl* StaticClassFn)();
    typedef void* (__cdecl* LoadClassFn)(void*, void*, const TCHARU*, const TCHARU*, DWORD, void*);
    typedef void* (__thiscall* DefaultObjFn)(void*);
    typedef void(__thiscall* AddToRootFn)(void*);
    auto ObjectClass = (StaticClassFn)GetProcAddress(core, "?StaticClass@UObject@@SAPAVUClass@@XZ");
    auto LoadClass = (LoadClassFn)GetProcAddress(core, "?StaticLoadClass@UObject@@SAPAVUClass@@PAV2@PAV1@PBG2KPAVUPackageMap@@@Z");
    auto DefaultObj = (DefaultObjFn)GetProcAddress(core, "?GetDefaultObject@UClass@@QAEPAVUObject@@XZ");
    auto AddToRoot = (AddToRootFn)GetProcAddress(core, "?AddToRoot@UObject@@QAEXXZ");
    if (!ObjectClass || !LoadClass || !DefaultObj || !AddToRoot) { Logf("MSM: missing exports\n"); return; }

    void* cls = LoadClass(ObjectClass(), nullptr, (const TCHARU*)L"Webhead.WebheadGameInfo", nullptr, 0, nullptr);
    if (!cls) { Logf("MSM: WebheadGameInfo not found\n"); return; }
    AddToRoot(cls);
    BYTE* def = (BYTE*)DefaultObj(cls);
    int off = FindFStringSlot(def, 0x2000);
    if (off < 0) { Logf("MSM: PlayerControllerClassName not found in defaults\n"); return; }
    wchar_t* data = *(wchar_t**)(def + off);
    memcpy(data, kNewPC, sizeof(kNewPC));
    *(int*)(def + off + 4) = (int)(sizeof(kNewPC) / sizeof(wchar_t));
    Logf("MSM: WebheadGameInfo.PlayerControllerClassName -> %ls (offset 0x%x)\n", kNewPC, off);
}

static void __cdecl Hook_appInit(const TCHARU* pkg, const TCHARU* cmd, void* malloc_, void* log, void* err,
                                 void* warn, void* fm, void* (*cfg)(), int requireConfig)
{
    const wchar_t* cl = GetCommandLineW();
    const wchar_t* u = wcsstr(cl, L"-ucc=");
    if (u)
    {
        g_log = _wfopen(L"ModLoader.log", L"w");
        *CoreInt("?GIsUCC@@3HA") = 1;
    }
    const wchar_t* x = wcsstr(cl, L"-msmexec=");
    if (x && !u)
        g_log = _wfopen(L"ModLoader.log", L"w");
    const bool modlog = wcsstr(cl, L"-modlog") != nullptr;
    if (modlog && !u)
        g_log = _wfopen(L"ModLoader.log", L"w");
    g_realAppInit(pkg, cmd, malloc_, log, err, warn, fm, cfg, requireConfig);
    if (modlog && !u)
    {
        TeeDevice<0>("?GLog@@3PAVFOutputDevice@@A");
        TeeDevice<1>("?GWarn@@3PAVFFeedbackContext@@A");
    }
    if (x && !u)
    {
        TeeDevice<0>("?GLog@@3PAVFOutputDevice@@A");
        TeeDevice<1>("?GWarn@@3PAVFFeedbackContext@@A");
        wchar_t path[MAX_PATH] = {};
        const wchar_t* t = x + 9;
        int k = 0;
        // a path with spaces arrives as one quoted argument: "-msmexec=C:\a b\x.txt"
        bool q = (*t == L'"') || (x > cl && x[-1] == L'"');
        if (*t == L'"') t++;
        while (*t && k < MAX_PATH - 1 && *t != L'"' && (q || *t != L' ')) path[k++] = *t++;
        Logf("running editor script %ls\n", path);
        // the editor class loading recurses deeply; run it on a thread with a big stack
        struct ExecArg { const wchar_t* path; int rc; } earg = { path, 0 };
        HANDLE th = CreateThread(nullptr, 256u << 20, [](LPVOID p) -> DWORD {
            auto a = (ExecArg*)p;
            a->rc = RunEditorScript(a->path);
            return 0;
        }, &earg, STACK_SIZE_PARAM_IS_A_RESERVATION, nullptr);
        if (th) WaitForSingleObject(th, INFINITE); else earg.rc = RunEditorScript(path);
        int rc = earg.rc;
        Logf("script exit %d\n", rc);
        if (g_log) fclose(g_log);
        TerminateProcess(GetCurrentProcess(), rc);
    }
    if (!u)
    {
        InstallControllerOverride();
        return;
    }

    wchar_t name[256] = {};
    const wchar_t* s = u + 5;
    int n = 0;
    while (*s && *s != L' ' && n < 255) name[n++] = *s++;
    while (*s == L' ') s++;
    TeeDevice<0>("?GLog@@3PAVFOutputDevice@@A");
    TeeDevice<1>("?GWarn@@3PAVFFeedbackContext@@A");
    Logf("running commandlet %ls parms '%ls'\n", name, s);
    int rc = RunCommandlet(name, s);
    Logf("exit %d\n", rc);
    if (g_log) fclose(g_log);
    TerminateProcess(GetCurrentProcess(), rc);
}

static void PatchIAT()
{
    BYTE* base = (BYTE*)GetModuleHandleA(nullptr);
    auto dos = (IMAGE_DOS_HEADER*)base;
    auto nt = (IMAGE_NT_HEADERS*)(base + dos->e_lfanew);
    auto dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    for (auto imp = (IMAGE_IMPORT_DESCRIPTOR*)(base + dir.VirtualAddress); imp->Name; imp++)
    {
        if (_stricmp((char*)(base + imp->Name), "Core.dll") != 0) continue;
        auto names = (IMAGE_THUNK_DATA*)(base + imp->OriginalFirstThunk);
        auto funcs = (IMAGE_THUNK_DATA*)(base + imp->FirstThunk);
        for (; names->u1.AddressOfData; names++, funcs++)
        {
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            auto ibn = (IMAGE_IMPORT_BY_NAME*)(base + names->u1.AddressOfData);
            if (strcmp((char*)ibn->Name, kAppInit) != 0) continue;
            DWORD old;
            VirtualProtect(&funcs->u1.Function, sizeof(void*), PAGE_READWRITE, &old);
            g_realAppInit = (AppInitFn)funcs->u1.Function;
            funcs->u1.Function = (ULONG_PTR)&Hook_appInit;
            VirtualProtect(&funcs->u1.Function, sizeof(void*), old, &old);
        }
    }
}

// Commandlet runs (-ucc=) must not see a running game: Webhead.exe allows one instance
// (named mutex / existing window). Those imports get unnamed / empty answers then.
static HANDLE WINAPI Hook_CreateMutexW(LPSECURITY_ATTRIBUTES a, BOOL owner, LPCWSTR) { return CreateMutexW(a, owner, nullptr); }
static HANDLE WINAPI Hook_CreateMutexA(LPSECURITY_ATTRIBUTES a, BOOL owner, LPCSTR) { return CreateMutexA(a, owner, nullptr); }
static HWND WINAPI Hook_FindWindowExW(HWND, HWND, LPCWSTR, LPCWSTR) { return nullptr; }
static HWND WINAPI Hook_FindWindowExA(HWND, HWND, LPCSTR, LPCSTR) { return nullptr; }

static void PatchImport(const char* dll, const char* fn, void* hook)
{
    BYTE* base = (BYTE*)GetModuleHandleA(nullptr);
    auto dos = (IMAGE_DOS_HEADER*)base;
    auto nt = (IMAGE_NT_HEADERS*)(base + dos->e_lfanew);
    auto dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    for (auto imp = (IMAGE_IMPORT_DESCRIPTOR*)(base + dir.VirtualAddress); imp->Name; imp++)
    {
        if (_stricmp((char*)(base + imp->Name), dll) != 0) continue;
        auto names = (IMAGE_THUNK_DATA*)(base + imp->OriginalFirstThunk);
        auto funcs = (IMAGE_THUNK_DATA*)(base + imp->FirstThunk);
        for (; names->u1.AddressOfData; names++, funcs++)
        {
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            auto ibn = (IMAGE_IMPORT_BY_NAME*)(base + names->u1.AddressOfData);
            if (strcmp((char*)ibn->Name, fn) != 0) continue;
            DWORD old;
            VirtualProtect(&funcs->u1.Function, sizeof(void*), PAGE_READWRITE, &old);
            funcs->u1.Function = (ULONG_PTR)hook;
            VirtualProtect(&funcs->u1.Function, sizeof(void*), old, &old);
        }
    }
}

BOOL WINAPI DllMain(HINSTANCE, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        PatchIAT();
        if (wcsstr(GetCommandLineW(), L"-ucc=") || wcsstr(GetCommandLineW(), L"-msmexec="))
        {
            PatchImport("KERNEL32.dll", "CreateMutexW", (void*)&Hook_CreateMutexW);
            PatchImport("KERNEL32.dll", "CreateMutexA", (void*)&Hook_CreateMutexA);
            PatchImport("USER32.dll", "FindWindowExW", (void*)&Hook_FindWindowExW);
            PatchImport("USER32.dll", "FindWindowExA", (void*)&Hook_FindWindowExA);
        }
    }
    return TRUE;
}
