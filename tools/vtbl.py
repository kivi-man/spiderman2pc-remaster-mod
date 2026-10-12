import sys, pefile
pe = pefile.PE(sys.argv[1]); base = pe.OPTIONAL_HEADER.ImageBase
exp = {base+e.address: e.name.decode() for e in pe.DIRECTORY_ENTRY_EXPORT.symbols if e.name}
byname = {v:k for k,v in exp.items()}
for vt in sys.argv[2:]:
    a = byname[vt]; print(vt)
    for i in range(40):
        p = pe.get_dword_at_rva(a - base + 4*i)
        if i and p in exp and exp[p].startswith('??_7'): break
        sec = pe.get_section_by_rva(p-base) if p > base else None
        if not sec or not (sec.Characteristics & 0x20000000): break
        print(' ', i, hex(p), exp.get(p, '?'))
