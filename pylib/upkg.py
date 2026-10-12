"""Minimal Unreal Engine 2 package (.u/.ukx/.utx) export/import table reader (version 126 'Fizz')."""
import struct


class Reader:
    def __init__(self, data):
        self.d = data
        self.p = 0

    def i32(self):
        v = struct.unpack_from('<i', self.d, self.p)[0]
        self.p += 4
        return v

    def u32(self):
        v = struct.unpack_from('<I', self.d, self.p)[0]
        self.p += 4
        return v

    def u16(self):
        v = struct.unpack_from('<H', self.d, self.p)[0]
        self.p += 2
        return v

    def compact(self):
        b = self.d[self.p]
        self.p += 1
        neg = b & 0x80
        v = b & 0x3F
        if b & 0x40:
            shift = 6
            while True:
                b = self.d[self.p]
                self.p += 1
                v |= (b & 0x7F) << shift
                shift += 7
                if not (b & 0x80):
                    break
        return -v if neg else v

    def fstring(self):
        n = self.compact()
        if n < 0:
            s = self.d[self.p:self.p - 2 * n - 2].decode('utf-16le')
            self.p += -2 * n
            return s.rstrip('\0')
        s = self.d[self.p:self.p + n].decode('latin-1')
        self.p += n
        return s.rstrip('\0')


def read_package(path):
    d = open(path, 'rb').read()
    r = Reader(d)
    tag = r.u32()
    assert tag == 0x9E2A83C1, hex(tag)
    ver = r.u16()
    lic = r.u16()
    flags = r.u32()
    name_count, name_off, exp_count, exp_off, imp_count, imp_off = [r.i32() for _ in range(6)]
    r.p = name_off
    names = []
    for _ in range(name_count):
        s = r.fstring()
        r.u32()
        names.append(s)
    r.p = imp_off
    imports = []
    for _ in range(imp_count):
        pkg = r.compact()
        cls = r.compact()
        outer = r.i32()
        obj = r.compact()
        imports.append((names[pkg], names[cls], outer, names[obj]))
    r.p = exp_off
    exports = []
    for _ in range(exp_count):
        cls = r.compact()
        sup = r.compact()
        outer = r.i32()
        obj = r.compact()
        fl = r.u32()
        size = r.compact()
        off = r.compact() if size > 0 else 0
        exports.append(dict(cls=cls, super=sup, outer=outer, name=names[obj], flags=fl, size=size, offset=off))
    return dict(version=ver, licensee=lic, names=names, imports=imports, exports=exports, data=d)


def class_name(pkg, idx):
    if idx > 0:
        return pkg['exports'][idx - 1]['name']
    if idx < 0:
        return pkg['imports'][-idx - 1][3]
    return 'Class'


if __name__ == '__main__':
    import sys
    p = read_package(sys.argv[1])
    print('version', p['version'], 'exports', len(p['exports']), 'imports', len(p['imports']))
    want = sys.argv[2] if len(sys.argv) > 2 else None
    for i, e in enumerate(p['exports']):
        c = class_name(p, e['cls'])
        if want is None or c.lower() == want.lower():
            print(i + 1, c, e['name'], e['size'])
