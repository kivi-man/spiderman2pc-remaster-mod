"""Set / clear the Large Address Aware flag of System/Webhead.exe (32-bit process: 2 GB -> 4 GB of address space).

The mod's graphics options (MSAA, supersampled sizes, 4K textures) run out of 32-bit address space without it.
A backup of the original exe is written next to it the first time (Webhead.exe.orig).

  python patch_laa.py "<game dir>\\System\\Webhead.exe"          # enable
  python patch_laa.py "<game dir>\\System\\Webhead.exe" --undo   # restore the original flag
"""
import os
import shutil
import struct
import sys

IMAGE_FILE_LARGE_ADDRESS_AWARE = 0x0020

path = sys.argv[1]
undo = '--undo' in sys.argv[2:]

with open(path, 'rb') as f:
    data = bytearray(f.read())
pe = struct.unpack_from('<I', data, 0x3C)[0]
if data[pe:pe + 4] != b'PE\0\0':
    sys.exit('not a PE file')
off = pe + 4 + 18  # IMAGE_FILE_HEADER.Characteristics
ch = struct.unpack_from('<H', data, off)[0]
want = (ch & ~IMAGE_FILE_LARGE_ADDRESS_AWARE) if undo else (ch | IMAGE_FILE_LARGE_ADDRESS_AWARE)
print('characteristics 0x%04x -> 0x%04x' % (ch, want))
if want == ch:
    print('nothing to do')
    sys.exit(0)
if not os.path.exists(path + '.orig'):
    shutil.copy2(path, path + '.orig')
struct.pack_into('<H', data, off, want)
with open(path, 'wb') as f:
    f.write(data)
print('done')
