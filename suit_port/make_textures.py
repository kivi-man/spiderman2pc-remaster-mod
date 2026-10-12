"""Convert the Raimi suit colour textures to DXT1 .dds (with hand-built mip chain) for UE2.

Keeps the in-game texture memory low (the 2004 engine runs as a 32-bit process): 14 x 1024^2 RGBA8 crashed with
CreateTexture failed(80004005); DXT1 is 1/8 of that.
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, r'H:\Spider-Man 2\_mod\pylib')
from suittex import load_texture  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out', 'tex')
os.makedirs(OUT, exist_ok=True)
rec = json.load(open(os.path.join(HERE, 'color_records.json')))

# mesh index -> (texture set, size)
PART = {7: ('spidersfront', 1024), 8: ('frames', 1024), 9: ('spiders', 1024), 10: ('torso', 2048),
        11: ('boots', 1024), 12: ('torsoblues', 1024), 13: ('arms', 2048), 14: ('calves', 1024),
        15: ('hands', 2048), 16: ('legs', 2048), 17: ('shoulders', 1024), 18: ('head', 2048),
        19: ('lenses', 1024), 20: ('lenses', 1024)}
BLUE = np.array([0.12, 0.25, 0.65])
RED_GAIN = 2.4


def grade(part, a):
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    if part in ('legs', 'torsoblues'):
        k = np.clip(lum / max(lum.mean(), 1e-3), 0, 2.4)
        return np.clip(BLUE[None, None, :] * (0.25 + 0.75 * k[..., None]), 0, 1)
    if part in ('spidersfront', 'spiders', 'frames', 'lenses'):
        return a
    return np.clip(a * RED_GAIN, 0, 1)


def dxt1_payload(img):
    b = io.BytesIO()
    img.convert('RGBA').save(b, format='DDS', pixel_format='DXT1')
    return b.getvalue()[128:]


def write_dds(path, img):
    w, h = img.size
    levels = []
    cur = img
    while True:
        levels.append(dxt1_payload(cur))
        if cur.size[0] <= 4 or cur.size[1] <= 4:
            break
        cur = cur.resize((cur.size[0] // 2, cur.size[1] // 2), Image.LANCZOS)
    hdr = b'DDS ' + struct.pack('<7I', 124, 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000, h, w, len(levels[0]), 0,
                                len(levels))
    hdr += b'\0' * 44
    hdr += struct.pack('<2I4s5I', 32, 4, b'DXT1', 0, 0, 0, 0, 0)
    hdr += struct.pack('<5I', 0x401008, 0, 0, 0, 0)
    assert len(hdr) == 128
    with open(path, 'wb') as f:
        f.write(hdr)
        for lv in levels:
            f.write(lv)
    return len(levels), sum(len(l) for l in levels)


cache = {}
for mi, (part, size) in PART.items():
    key = (part, size)
    if key not in cache:
        img, _ = load_texture(os.path.join(HERE, 'assets', rec[part][0]))
        a = np.asarray(img.convert('RGB').resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0
        a = grade(part, a)
        cache[key] = Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGB')
    n, total = write_dds(os.path.join(OUT, 'Raimi_m%02d.dds' % mi), cache[key])
    print('Raimi_m%02d %-13s %4d  mips=%d  %d KB' % (mi, part, size, n, total // 1024))
