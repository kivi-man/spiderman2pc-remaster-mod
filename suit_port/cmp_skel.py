"""Compare the RefSkeleton bone records of the stock SpideyMesh and an imported test mesh."""
import os
import struct
import sys

sys.path.insert(0, r'H:\Spider-Man 2\_mod\pylib')
from upkg import read_package  # noqa: E402


def enc(v):
    b = []
    first = v & 0x3F
    if v > 0x3F:
        b.append(first | 0x40)
        v >>= 6
        while True:
            x = v & 0x7F
            v >>= 7
            if v:
                b.append(x | 0x80)
            else:
                b.append(x)
                break
    else:
        b.append(first)
    return bytes(b)


def bones_of(path, meshname, nbone=77):
    p = read_package(path)
    names = p['names']
    ex = [e for e in p['exports'] if e['name'] == meshname][0]
    data = p['data'][ex['offset']:ex['offset'] + ex['size']]
    ri = [i for i, n in enumerate(names) if n.lower().endswith(':rootparent')][0]
    key = enc(ri)
    out = None
    s = 0
    while True:
        k = data.find(key, s)
        if k < 0:
            break
        s = k + 1
        # sanity: next record starts after 4(flags)+4*4(q)+3*4(pos)+4(len)+3*4(sizes)+3*4(ints)
        try:
            q = struct.unpack_from('<4f', data, k + len(key) + 4)
            n2 = sum(x * x for x in q)
            if abs(n2 - 1.0) < 0.05:
                out = k
                break
        except struct.error:
            pass
    if out is None:
        return None, names, data
    recs = []
    k = out
    for _ in range(nbone):
        # compact name index
        b = data[k]
        l = 1
        if b & 0x40:
            l = 1
            while data[k + l - 1] & 0x80:
                l += 1
        # parse index
        v = data[k] & 0x3F
        sh = 6
        c = 1
        if data[k] & 0x40:
            while True:
                bb = data[k + c]
                c += 1
                v |= (bb & 0x7F) << sh
                sh += 7
                if not (bb & 0x80):
                    break
        k += c
        flags = struct.unpack_from('<I', data, k)[0]
        q = struct.unpack_from('<4f', data, k + 4)
        pos = struct.unpack_from('<3f', data, k + 20)
        nch, par = struct.unpack_from('<2i', data, k + 48)
        recs.append((names[v], flags, q, pos, nch, par, 0))
        k += 56
    return recs, names, data


a, _, _ = bones_of(r'H:\Spider-Man 2\Animations\SpideyAnimations.ukx', 'SpideyMesh')
b, _, _ = bones_of(sys.argv[1], sys.argv[2])
print('stock bones', None if a is None else len(a), 'imported', None if b is None else len(b))
for i in (0, 1, 2, 5, 9, 10, 11, 13, 56, 57):
    if a:
        print('stock   %2d %-28s q=%s pos=%s par=%d' % (i, a[i][0], [round(x, 4) for x in a[i][2]], [round(x, 2) for x in a[i][3]], a[i][5]))
    if b:
        print('import  %2d %-28s q=%s pos=%s par=%d' % (i, b[i][0], [round(x, 4) for x in b[i][2]], [round(x, 2) for x in b[i][3]], b[i][5]))

# full check: import == (x,-y,z) of stock, rotation equal up to sign?
import math
bad_pos = bad_q = 0
for i in range(77):
    sa, sb = a[i], b[i]
    pa, pb = sa[3], sb[3]
    if not (abs(pa[0] - pb[0]) < 1e-3 and abs(pa[1] + pb[1]) < 1e-3 and abs(pa[2] - pb[2]) < 1e-3):
        bad_pos += 1
    qa, qb = sa[2], sb[2]
    d1 = max(abs(x - y) for x, y in zip(qa, qb))
    d2 = max(abs(x + y) for x, y in zip(qa, qb))
    if min(d1, d2) > 1e-3:
        bad_q += 1
        print('q mismatch', i, sa[0], [round(x, 3) for x in qa], [round(x, 3) for x in qb])
print('bad pos', bad_pos, 'bad q', bad_q)

bad = 0
for i in range(77):
    qa = a[i][2]
    m = (-qa[0], qa[1], -qa[2], qa[3])
    qb = b[i][2]
    d1 = max(abs(x - y) for x, y in zip(m, qb))
    d2 = max(abs(x + y) for x, y in zip(m, qb))
    if min(d1, d2) > 1e-3:
        bad += 1
        print('mirror mismatch', i, a[i][0], m, qb)
print('mirror check bad =', bad)
