// -msmexec=<script>: run editor console commands (one per line) through UEditorEngine::Exec,
// e.g. "MESH MODELIMPORT ..." and "OBJ SAVEPACKAGE ...", then exit. Used to import PSK/PSA
// assets into UE2 packages with the game's own importer. Included by d3d8proxy.cpp.
// Script lines: "#..." / ";..." comments, "@init" calls UEditorEngine::Init, anything else is a command.
static LONG ReportCrash(EXCEPTION_POINTERS* ep)
{
    void* addr = ep->ExceptionRecord->ExceptionAddress;
    HMODULE mod = nullptr;
    char name[MAX_PATH] = {};
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)addr, &mod))
        GetModuleFileNameA(mod, name, MAX_PATH);
    Logf("  exception 0x%08lx at %p (%s +0x%lx) access %s %p\n", ep->ExceptionRecord->ExceptionCode, addr, name,
         (unsigned long)((BYTE*)addr - (BYTE*)mod), ep->ExceptionRecord->ExceptionInformation[0] ? "write" : "read",
         (void*)ep->ExceptionRecord->ExceptionInformation[1]);
    CONTEXT* c = ep->ContextRecord;
    Logf("  eax=%08lx ebx=%08lx ecx=%08lx edx=%08lx esi=%08lx edi=%08lx ebp=%08lx esp=%08lx\n", c->Eax, c->Ebx, c->Ecx, c->Edx, c->Esi, c->Edi, c->Ebp, c->Esp);
    DWORD* sp = (DWORD*)c->Esp;
    int shown = 0;
    for (int i = 0; i < 6000 && shown < 80; i++)
    {
        __try
        {
            DWORD v = sp[i];
            HMODULE m2 = nullptr;
            if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)(ULONG_PTR)v, &m2) && m2)
            {
                char n2[MAX_PATH] = {};
                GetModuleFileNameA(m2, n2, MAX_PATH);
                Logf("    [esp+%02x] %08lx (%s +0x%lx)\n", i * 4, v, n2, (unsigned long)(v - (DWORD)(ULONG_PTR)m2));
                shown++;
            }
        }
        __except (EXCEPTION_EXECUTE_HANDLER) { break; }
    }
    return EXCEPTION_EXECUTE_HANDLER;
}

static LONG CALLBACK MsmVeh(EXCEPTION_POINTERS* ep)
{
    DWORD c = ep->ExceptionRecord->ExceptionCode;
    if (c == 0xC0000005 || c == 0xC00000FD || c == 0xC0000094 || c == 0xC000001D)
    {
        static LONG once = 0;
        if (InterlockedIncrement(&once) == 1)
        {
            Logf("VEH first-chance fatal exception:\n");
            ReportCrash(ep);
        }
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static int RunEditorScript(const wchar_t* scriptPath)
{
    AddVectoredExceptionHandler(1, MsmVeh);
    HMODULE core = GetModuleHandleA("Core.dll");
    typedef void* (__cdecl* StaticClassFn)();
    typedef void* (__cdecl* LoadClassFn)(void*, void*, const TCHARU*, const TCHARU*, DWORD, void*);
    typedef void* (__cdecl* ConstructFn)(void*, void*, int, DWORD, void*, void*, void*);
    typedef void* (__cdecl* TransientFn)();
    typedef int(__thiscall* ExecFn)(void*, const TCHARU*, void*);
    typedef void(__thiscall* InitFn)(void*);

    auto ObjectClass = (StaticClassFn)GetProcAddress(core, "?StaticClass@UObject@@SAPAVUClass@@XZ");
    auto LoadClass = (LoadClassFn)GetProcAddress(core, "?StaticLoadClass@UObject@@SAPAVUClass@@PAV2@PAV1@PBG2KPAVUPackageMap@@@Z");
    auto Construct = (ConstructFn)GetProcAddress(core, "?StaticConstructObject@UObject@@SAPAV1@PAVUClass@@PAV1@VFName@@K1PAVFOutputDevice@@1@Z");
    auto Transient = (TransientFn)GetProcAddress(core, "?GetTransientPackage@UObject@@SAPAVUPackage@@XZ");
    void** pGError = (void**)GetProcAddress(core, "?GError@@3PAVFOutputDeviceError@@A");
    void** pGLog = (void**)GetProcAddress(core, "?GLog@@3PAVFOutputDevice@@A");
    if (!ObjectClass || !LoadClass || !Construct || !Transient || !pGError || !pGLog)
    {
        Logf("missing Core.dll export\n");
        return 2;
    }
    *CoreInt("?GIsUCC@@3HA") = 1;
    *CoreInt("?GIsClient@@3HA") = 0;
    *CoreInt("?GIsServer@@3HA") = 0;
    *CoreInt("?GIsEditor@@3HA") = 1;
    *CoreInt("?GLazyLoad@@3HA") = 1;
    *CoreInt("?GIsScriptable@@3HA") = 1;

    void* cls = LoadClass(ObjectClass(), nullptr, (const TCHARU*)L"Editor.EditorEngine", nullptr, 0, nullptr);
    Logf("EditorEngine class -> %p\n", cls);
    if (!cls) return 4;
    HMODULE ed = GetModuleHandleA("Editor.dll");
    if (!ed)
    {
        Logf("Editor.dll not loaded\n");
        return 5;
    }
    void* obj = Construct(cls, Transient(), 0, 0, nullptr, *pGError, nullptr);
    Logf("EditorEngine object -> %p\n", obj);
    if (!obj) return 6;
    void** pGEditor = (void**)GetProcAddress(ed, "?GEditor@@3PAVUEditorEngine@@A");
    if (pGEditor) *pGEditor = obj;
    auto Exec = (ExecFn)GetProcAddress(ed, "?Exec@UEditorEngine@@UAEHPBGAAVFOutputDevice@@@Z");
    auto Init = (InitFn)GetProcAddress(ed, "?Init@UEditorEngine@@UAEXXZ");
    if (!Exec)
    {
        Logf("Exec export missing\n");
        return 7;
    }

    // UEditorEngine::Exec dereferences Level (offset 0xE4) only when it is non-null; the
    // object we construct outside UnrealEd has garbage there. There is no level to edit.
    *(void**)((BYTE*)obj + 0x34 + 0xE4) = nullptr;

    FILE* f = _wfopen(scriptPath, L"r");
    if (!f)
    {
        Logf("cannot open script %ls\n", scriptPath);
        return 8;
    }
    char line[2048];
    void* ctxPackage = nullptr;
    int rc = 0;
    while (fgets(line, sizeof(line), f))
    {
        size_t n = strlen(line);
        while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = 0;
        if (!line[0] || line[0] == '#' || line[0] == ';') continue;
        if (_strnicmp(line, "@package ", 9) == 0)
        {
            typedef void* (__cdecl* CreatePackageFn)(void*, const TCHARU*);
            auto CreatePackage = (CreatePackageFn)GetProcAddress(core, "?CreatePackage@UObject@@SAPAVUPackage@@PAV1@PBG@Z");
            wchar_t wname[128];
            MultiByteToWideChar(CP_UTF8, 0, line + 9, -1, wname, 128);
            ctxPackage = CreatePackage ? CreatePackage(nullptr, (const TCHARU*)wname) : nullptr;
            Logf("package %ls -> %p\n", wname, ctxPackage);
            continue;
        }
        if (_strnicmp(line, "@save ", 6) == 0)
        {
            // @save <path>: save the context package (all RF_Public|RF_Standalone objects)
            typedef int (__cdecl* SavePackageFn)(void*, void*, DWORD, const TCHARU*, void*, void*);
            auto SavePackage = (SavePackageFn)GetProcAddress(core, "?SavePackage@UObject@@SAHPAV1@0KPBGPAVFOutputDevice@@PAVULinkerLoad@@@Z");
            wchar_t wpath[MAX_PATH];
            const char* q = line + 6;
            if (*q == '"') q++;
            MultiByteToWideChar(CP_UTF8, 0, q, -1, wpath, MAX_PATH);
            size_t pl = wcslen(wpath);
            if (pl && wpath[pl - 1] == L'"') wpath[pl - 1] = 0;
            Logf("saving package %p to %ls\n", ctxPackage, wpath);
            __try
            {
                int ok = SavePackage ? SavePackage(ctxPackage, nullptr, 0x00080004, (const TCHARU*)wpath, *pGLog, nullptr) : -1;
                Logf("  SavePackage -> %d\n", ok);
                if (ok != 1) rc = 10;
            }
            __except (ReportCrash(GetExceptionInformation()))
            {
                Logf("  crashed\n");
                rc = 9;
            }
            continue;
        }
        if (_strnicmp(line, "@bonemap ", 9) == 0)
        {
            // @bonemap <Pkg.Mesh> <Pkg.Anim>: check how the anim set's RefBones match the mesh's bones
            typedef void* (__cdecl* LoadObjFn)(void*, void*, const TCHARU*, const TCHARU*, DWORD, void*);
            typedef int(__thiscall* MatchFn)(void*, DWORD);
            auto LoadObj = (LoadObjFn)GetProcAddress(core, "?StaticLoadObject@UObject@@SAPAV1@PAVUClass@@PAV1@PBG2KPAVUPackageMap@@@Z");
            HMODULE eng = GetModuleHandleA("Engine.dll");
            auto Match = (MatchFn)GetProcAddress(eng, "?MatchRefBone@USkeletalMesh@@QAEHVFName@@@Z");
            char mp[256] = {}, ap[256] = {};
            sscanf(line + 9, "%255s %255s", mp, ap);
            wchar_t wm[256], wa[256];
            MultiByteToWideChar(CP_UTF8, 0, mp, -1, wm, 256);
            MultiByteToWideChar(CP_UTF8, 0, ap, -1, wa, 256);
            void* mesh = LoadObj(ObjectClass(), nullptr, (const TCHARU*)wm, nullptr, 0, nullptr);
            void* anim = LoadObj(ObjectClass(), nullptr, (const TCHARU*)wa, nullptr, 0, nullptr);
            Logf("bonemap mesh=%p anim=%p match=%p\n", mesh, anim, Match);
            if (mesh && anim && Match)
            {
                for (int o = 0x20; o < 0x200; o += 4)
                {
                    DWORD p = *(DWORD*)((BYTE*)anim + o), n = *(DWORD*)((BYTE*)anim + o + 4), m = *(DWORD*)((BYTE*)anim + o + 8);
                    if (p > 0x10000 && n > 0 && n <= m && n < 4000)
                        Logf("  anim +0x%x array ptr=%08x num=%u max=%u\n", o, p, n, m);
                }
                // anim RefBones at +0x38: FNamedBone {FName, flags, parent}, 12 bytes
                DWORD sp = *(DWORD*)((BYTE*)anim + 0x38), sn = *(DWORD*)((BYTE*)anim + 0x3c);
                int bad = 0;
                for (DWORD i = 0; i < sn; i++)
                {
                    DWORD nm = *(DWORD*)(sp + i * 12);
                    int r = -2;
                    __try { r = Match(mesh, nm); } __except (EXCEPTION_EXECUTE_HANDLER) {}
                    if (r != (int)i) { bad++; if (bad <= 12) Logf("  anim bone %u name#%u -> MatchRefBone %d\n", i, nm, r); }
                }
                Logf("  anim bones %u, mismatches vs mesh order %d\n", sn, bad);
            }
            continue;
        }
        if (_strnicmp(line, "@dumpobj ", 9) == 0)
        {
            // @dumpobj <Pkg.Object> <outfile> [size]: raw bytes of a loaded object (reverse engineering aid)
            typedef void* (__cdecl* LoadObjFn)(void*, void*, const TCHARU*, const TCHARU*, DWORD, void*);
            auto LoadObj = (LoadObjFn)GetProcAddress(core, "?StaticLoadObject@UObject@@SAPAV1@PAVUClass@@PAV1@PBG2KPAVUPackageMap@@@Z");
            char opath[256] = {}, ofile[MAX_PATH] = {};
            int osize = 0x600;
            sscanf(line + 9, "%255s %259s %i", opath, ofile, &osize);
            wchar_t wo[256];
            MultiByteToWideChar(CP_UTF8, 0, opath, -1, wo, 256);
            void* o = LoadObj(ObjectClass(), nullptr, (const TCHARU*)wo, nullptr, 0, nullptr);
            Logf("dumpobj %s -> %p\n", opath, o);
            if (o)
            {
                FILE* of = fopen(ofile, "wb");
                if (of)
                {
                    for (int i = 0; i < osize; i += 4)
                    {
                        DWORD v = 0;
                        __try { v = *(DWORD*)((BYTE*)o + i); } __except (EXCEPTION_EXECUTE_HANDLER) { v = 0xDEADBEEF; }
                        fwrite(&v, 4, 1, of);
                    }
                    fclose(of);
                }
            }
            continue;
        }
        if (_strnicmp(line, "@linkanim ", 10) == 0)
        {
            // @linkanim <Pkg.Mesh> <Pkg.Anim>: SkeletalMesh keeps a serialized reference to its MeshAnimation (right
            // after RefSkeleton); the PSK importer leaves it null, which leaves the mesh in its reference pose.
            // Find the slot by locating the stock mesh's pointer to the stock anim set, then copy it.
            typedef void* (__cdecl* LoadObjFn)(void*, void*, const TCHARU*, const TCHARU*, DWORD, void*);
            typedef void* (__cdecl* FindObjFn)(void*, void*, const TCHARU*, int);
            auto LoadObj = (LoadObjFn)GetProcAddress(core, "?StaticLoadObject@UObject@@SAPAV1@PAVUClass@@PAV1@PBG2KPAVUPackageMap@@@Z");
            auto FindObj = (FindObjFn)GetProcAddress(core, "?StaticFindObject@UObject@@SAPAV1@PAVUClass@@PAV1@PBGH@Z");
            char meshPath[256] = {}, animPath[256] = {};
            sscanf(line + 10, "%255s %255s", meshPath, animPath);
            wchar_t wm[256], wa[256];
            MultiByteToWideChar(CP_UTF8, 0, meshPath, -1, wm, 256);
            MultiByteToWideChar(CP_UTF8, 0, animPath, -1, wa, 256);
            void* objClass = ObjectClass();
            void* stock = LoadObj(objClass, nullptr, (const TCHARU*)L"SpideyAnimations.SpideyMesh", nullptr, 0, nullptr);
            void* anim = LoadObj(objClass, nullptr, (const TCHARU*)wa, nullptr, 0, nullptr);
            void* target = FindObj(objClass, nullptr, (const TCHARU*)wm, 0);
            Logf("linkanim stock=%p anim=%p target=%p\n", stock, anim, target);
            if (stock && anim && target)
            {
                int hits = 0, off = -1;
                for (int o = 0x20; o < 0x800; o += 4)
                {
                    __try
                    {
                        if (*(void**)((BYTE*)stock + o) == anim)
                        {
                            Logf("  stock mesh +0x%x holds the anim set\n", o);
                            if (off < 0) off = o;
                            hits++;
                        }
                    }
                    __except (EXCEPTION_EXECUTE_HANDLER) { break; }
                }
                if (off >= 0)
                {
                    *(void**)((BYTE*)target + off) = anim;
                    Logf("  target +0x%x set\n", off);
                }
                else
                {
                    Logf("  anim pointer slot not found\n");
                    rc = 11;
                }
            }
            else rc = 11;
            continue;
        }
        if (_strnicmp(line, "@init", 5) == 0)
        {
            if (Init)
            {
                __try { Init(obj); Logf("Init done\n"); }
                __except (EXCEPTION_EXECUTE_HANDLER) { Logf("Init crashed: 0x%08lx\n", GetExceptionCode()); }
            }
            continue;
        }
        wchar_t wline[2048];
        MultiByteToWideChar(CP_UTF8, 0, line, -1, wline, 2048);
        *(void**)((BYTE*)obj + 0x34 + 0xE4) = nullptr;
        *(void**)((BYTE*)obj + 0x198) = ctxPackage;   // UEditorEngine::ParentContext: where imports are created
        Logf("> %s\n", line);
        __try
        {
            int r = Exec((BYTE*)obj + 0x34, (const TCHARU*)wline, *pGLog);
            Logf("  -> %d\n", r);
        }
        __except (ReportCrash(GetExceptionInformation()))
        {
            Logf("  crashed\n");
            rc = 9;
        }
    }
    fclose(f);
    return rc;
}
