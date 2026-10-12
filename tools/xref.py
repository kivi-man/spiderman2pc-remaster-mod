import sys, pefile, capstone, struct
pe = pefile.PE(sys.argv[1]); base = pe.OPTIONAL_HEADER.ImageBase
data = pe.get_memory_mapped_image()
def find_wstr(s):
    b = s.encode('utf-16le'); out=[]; i=data.find(b)
    while i!=-1: out.append(base+i); i=data.find(b,i+1)
    return out
text = [s for s in pe.sections if s.Name.startswith(b'.text')][0]
code = data[text.VirtualAddress:text.VirtualAddress+text.Misc_VirtualSize]
for s in sys.argv[2:]:
    for a in find_wstr(s):
        if data[a-base-2:a-base]!=b'\0\0': continue
        pat = struct.pack('<I', a); j = code.find(pat)
        while j!=-1:
            print(f'{s!r} @ {a:#x} ref at {base+text.VirtualAddress+j:#x}')
            j = code.find(pat, j+1)
