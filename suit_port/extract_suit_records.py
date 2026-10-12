"""Extract every record of a legacy MSMR .suit to individual files and print their magic numbers.

usage: python extract_suit_records.py <suit> <out_dir>
Files are named <index>_<assetid>.bin. Nothing is written outside out_dir.
"""
import struct
import sys
import zipfile
from pathlib import Path


def main():
    suit = Path(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(suit) as z:
        names = z.namelist()
        idn = [n for n in names if n.rsplit('/', 1)[-1] == 'id.txt'][0]
        folder = idn.rsplit('/', 1)[0]
        suit_id = z.read(idn).decode('utf-8-sig').strip()
        info = z.read(folder + '/info.txt')
        recs = []
        for i in range(len(info) // 21):
            off, unk, ln, aid, span = struct.unpack_from('<IIIQB', info, i * 21)
            recs.append((i, off, ln, aid, span))
        pos = 0
        with z.open(folder + '/' + suit_id) as s:
            for i, off, ln, aid, span in recs:
                if off < pos:
                    raise ValueError('records out of order')
                skip = off - pos
                while skip:
                    chunk = s.read(min(8 * 1024 * 1024, skip))
                    if not chunk:
                        raise ValueError('truncated')
                    skip -= len(chunk)
                data = s.read(ln) if ln else b''
                pos = off + ln
                if ln:
                    (out / f'{i:03d}_{aid:016X}_s{span}.bin').write_bytes(data)
                magic = struct.unpack_from('<I', data)[0] if len(data) >= 4 else 0
                print(f'{i:3d} {aid:016X} span={span} size={ln:10d} magic={magic:08X}')


if __name__ == '__main__':
    main()
