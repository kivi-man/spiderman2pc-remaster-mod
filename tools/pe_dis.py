import sys; sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import sys, pefile, capstone
pe = pefile.PE(sys.argv[1]); base = pe.OPTIONAL_HEADER.ImageBase
data = pe.get_memory_mapped_image()
exp = {base+e.address: e.name.decode() for e in pe.DIRECTORY_ENTRY_EXPORT.symbols if e.name}
imp = {}
for d in getattr(pe,'DIRECTORY_ENTRY_IMPORT',[]):
    for i in d.imports: imp[i.address] = (i.name or b'?').decode()
start, n = int(sys.argv[2],16), int(sys.argv[3])
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
for ins in md.disasm(data[start-base:start-base+n], start):
    c = ''
    for tok in ins.op_str.replace('[',' ').replace(']',' ').replace(',',' ').split():
        try: v = int(tok,16)
        except: continue
        if v in exp: c += ' ; '+exp[v]
        elif v in imp: c += ' ; [imp] '+imp[v]
        elif base < v < base+len(data):
            s = data[v-base:v-base+80]
            try:
                w = s.decode('utf-16le').split('\0')[0]
                if len(w)>3 and w.isprintable(): c += f' ; L"{w}"'
            except: pass
    print(f'{ins.address:#x}: {ins.mnemonic} {ins.op_str}{c}')
