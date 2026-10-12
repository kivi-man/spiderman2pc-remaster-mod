"""Decode Insomniac .texture (BC7) records from a suit into PIL images."""
import io
import struct
import sys

sys.path.insert(0, r'H:\Spider-Man 2\_mod\work\alert-source')
import dat1lib  # noqa: E402
from PIL import Image  # noqa: E402


def _dds(w, h, dxgi, data):
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x80000
    pitch = ((w + 3) // 4) * ((h + 3) // 4) * 16
    hdr = b'DDS ' + struct.pack('<7I', 124, flags, h, w, pitch, 0, 1) + b'\0' * 44
    hdr += struct.pack('<2I4s5I', 32, 4, b'DX10', 0, 0, 0, 0, 0)
    hdr += struct.pack('<5I', 0x1000, 0, 0, 0, 0)
    hdr += struct.pack('<5I', dxgi, 3, 0, 1, 0)
    return hdr + data


def load_texture(path, layer=0):
    """Largest mip of one layer as a PIL RGBA image. Mip chain order in the file: largest first."""
    raw = open(path, 'rb').read()
    t = dat1lib.read(io.BytesIO(raw))
    h = t.dat1.get_section(0x4EDE3593)
    w, hh = h.sd_width, h.sd_height
    n = h.sd_mipmaps
    blk = 16 if h.fmt in (98, 99) else 8
    sizes = []
    cw, ch = w, hh
    for _ in range(n):
        sizes.append(max(1, (cw + 3) // 4) * max(1, (ch + 3) // 4) * blk)
        cw, ch = max(1, cw // 2), max(1, ch // 2)
    body = raw[len(raw) - h.sd_len:]
    layer_size = sum(sizes)
    off = layer * layer_size
    data = body[off:off + sizes[0]]
    dxgi = {98: 98, 99: 99, 71: 71, 72: 72}.get(h.fmt, h.fmt)
    img = Image.open(io.BytesIO(_dds(w, hh, dxgi, data)))
    img.load()
    return img.convert('RGBA'), h
