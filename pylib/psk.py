"""ActorX .psk writer (skeletal mesh for UE2's MESH MODELIMPORT) and tiny quaternion helpers.

Chunk layout (little endian), each chunk = 20 byte id, int32 flags, int32 item size, int32 item count:
  ACTRHEAD (0 items) | PNTS0000 3*float | VTXW0000 16 bytes | FACE0000 12 bytes | MATT0000 88 bytes
  REFSKELT 120 bytes | RAWWEIGHTS 12 bytes
"""
import struct


def chunk(name, size, items):
    return struct.pack('<20siii', name.encode(), 1999801, size, len(items)) + b''.join(items)


def write_psk(path, points, wedges, faces, materials, bones, weights):
    """points: [(x,y,z)]; wedges: [(point_index, u, v, mat_index)];
    faces: [(w0,w1,w2,mat_index,smoothing_group)]; materials: [name];
    bones: [(name, parent, (qx,qy,qz,qw), (x,y,z), num_children)];
    weights: [(weight, point_index, bone_index)]."""
    out = [struct.pack('<20siii', b'ACTRHEAD', 1999801, 0, 0)]
    out.append(chunk('PNTS0000', 12, [struct.pack('<3f', *p) for p in points]))
    out.append(chunk('VTXW0000', 16, [struct.pack('<HHffBBH', w[0], 0, w[1], w[2], w[3], 0, 0) for w in wedges]))
    out.append(chunk('FACE0000', 12, [struct.pack('<3HBBI', f[0], f[1], f[2], f[3], 0, f[4]) for f in faces]))
    mats = []
    for i, m in enumerate(materials):
        # TextureIndex = material slot, so Actor.Skins[i] drives material i
        mats.append(struct.pack('<64siIiIii', m.encode()[:63], i, 0, -1, 0, 0, 0))
    out.append(chunk('MATT0000', 88, mats))
    refs = []
    for name, parent, q, p, nchild in bones:
        refs.append(struct.pack('<64sIii4f3f4f', name.encode()[:63], 0, nchild, parent, q[0], q[1], q[2], q[3],
                                p[0], p[1], p[2], 0.0, 0.0, 0.0, 0.0))
    out.append(chunk('REFSKELT', 120, refs))
    out.append(chunk('RAWWEIGHTS', 12, [struct.pack('<fii', w[0], w[1], w[2]) for w in weights]))
    with open(path, 'wb') as f:
        f.write(b''.join(out))
