"""Tiny glTF 2.0 loader (embedded base64 or .bin buffers) returning numpy arrays. No external deps."""
import base64
import json
import os
import numpy as np

_COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
_NUM = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT2': 4, 'MAT3': 9, 'MAT4': 16}


class Gltf:
    def __init__(self, path):
        self.path = path
        self.j = json.load(open(path, encoding='utf-8'))
        self.buffers = []
        for b in self.j.get('buffers', []):
            uri = b.get('uri', '')
            if uri.startswith('data:'):
                self.buffers.append(base64.b64decode(uri.split(',', 1)[1]))
            else:
                self.buffers.append(open(os.path.join(os.path.dirname(path), uri), 'rb').read())

    def accessor(self, idx):
        a = self.j['accessors'][idx]
        bv = self.j['bufferViews'][a['bufferView']]
        buf = self.buffers[bv['buffer']]
        dt = np.dtype(_COMP[a['componentType']])
        n = _NUM[a['type']]
        count = a['count']
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride', 0)
        if stride and stride != dt.itemsize * n:
            raw = np.frombuffer(buf, dtype=np.uint8, count=stride * count, offset=off).reshape(count, stride)
            arr = raw[:, :dt.itemsize * n].copy().view(dt).reshape(count, n)
        else:
            arr = np.frombuffer(buf, dtype=dt, count=count * n, offset=off).reshape(count, n)
        if a.get('normalized'):
            if dt == np.uint16:
                arr = arr.astype(np.float32) / 65535.0
            elif dt == np.uint8:
                arr = arr.astype(np.float32) / 255.0
        return arr
