"""Parse SpideyAnimations.SpideyAnim (UE2 MeshAnimation) and report which bones have tracks per sequence."""
import struct
import sys

sys.path.insert(0, r'H:\Spider-Man 2\_mod\pylib')
from upkg import read_package, Reader  # noqa: E402

p = read_package(r'H:\Spider-Man 2\Animations\SpideyAnimations.ukx')
names = p['names']
ex = [e for e in p['exports'] if e['name'] == 'SpideyAnim'][0]
d = p['data'][ex['offset']:ex['offset'] + ex['size']]
r = Reader(d)


def fname():
    return names[r.compact()]


def skip_props():
    # tagged properties until 'None'
    while True:
        n = names[r.compact()]
        if n == 'None':
            return
        raise RuntimeError('unexpected property ' + n)


skip_props()
version = r.i32()
nref = r.compact()
refbones = []
for _ in range(nref):
    n = fname()
    fl = r.u32()
    par = r.i32()
    refbones.append((n, fl, par))
print('version', version, 'refbones', nref)
nmoves = r.compact()
moves = []
for mi in range(nmoves):
    root = struct.unpack_from('<3f', d, r.p); r.p += 12
    tt = struct.unpack_from('<f', d, r.p)[0]; r.p += 4
    sb = r.i32()
    fl = r.u32()
    nb = r.compact()
    bidx = [r.i32() for _ in range(nb)]
    nt = r.compact()
    tracks = []
    for _ in range(nt):
        tfl = r.u32()
        nq = r.compact(); r.p += 16 * nq
        np_ = r.compact(); r.p += 12 * np_
        nk = r.compact(); r.p += 4 * nk
        tracks.append((tfl, nq, np_, nk))
    # root track
    rfl = r.u32()
    nq = r.compact(); r.p += 16 * nq
    np_ = r.compact(); r.p += 12 * np_
    nk = r.compact(); r.p += 4 * nk
    moves.append(dict(root=root, tt=tt, sb=sb, fl=fl, bidx=bidx, tracks=tracks))
nseq = r.compact()
seqs = []
for _ in range(nseq):
    n = fname()
    ng = r.compact()
    groups = [fname() for _ in range(ng)]
    sf = r.i32()
    nf = r.i32()
    rate = struct.unpack_from('<f', d, r.p)[0]; r.p += 4
    nn = r.compact()
    # notifys: FMeshAnimNotify {float Time; UObject* Function(FName)?; UAnimNotify* Notify (object ref)}
    notes = []
    for _ in range(nn):
        t = struct.unpack_from('<f', d, r.p)[0]; r.p += 4
        fn = fname()
        ob = r.compact()
        notes.append((t, fn, ob))
    f28 = struct.unpack_from('<f', d, r.p)[0]; r.p += 4
    seqs.append((n, groups, sf, nf, rate, len(notes)))
print('moves', nmoves, 'seqs', nseq, 'pos', r.p, 'of', len(d))
want = sys.argv[1:] or ['IdleRest', 'RunForwards', 'Walk', 'JumpRunningMid']
for i, s in enumerate(seqs):
    if s[0] in want:
        m = moves[i]
        used = [j for j, t in enumerate(m['tracks']) if t[1] > 0 or t[2] > 0]
        print(i, s[0], 'frames', s[3], 'rate', s[4], 'trackTime', m['tt'], 'flags', m['fl'], 'startBone', m['sb'],
              'tracks', len(m['tracks']), 'nonempty', len(used), 'bidx>=0', sum(1 for b in m['bidx'] if b >= 0))
        print('   first bone idx', m['bidx'][:12], 'nonempty tracks head', used[:20])
print('all names:', ' '.join(s[0] for s in seqs[:60]))
