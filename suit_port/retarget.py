"""Retarget the Raimi MSMR suit (231 joints, A-pose) onto the Spider-Man 2 skeleton (77 bones, T-pose).

Method: every source joint inherits the rigid+scale transform of its nearest "driver" ancestor. A driver maps a
source segment (joint -> child) onto a target segment (bone -> child bone): rotation aligns the directions, scale is
the length ratio. The mesh is deformed once with the source skin weights (linear blend of those transforms) and then
re-skinned on the target bones with the collapsed weights.
usage: python retarget.py [--out DIR]
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, r'H:\Spider-Man 2\_mod\pylib')
from gltfload import Gltf          # noqa: E402
from psk import write_psk          # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
if '--out' in sys.argv:
    OUT = sys.argv[sys.argv.index('--out') + 1]
os.makedirs(OUT, exist_ok=True)

MESH_SCALE = 1.25                     # gltf mesh coords * 1.25 = source skeleton space
BODY_MESHES = list(range(7, 21))      # 0..6 are webbing overlay shells
if '--meshes' in sys.argv:
    BODY_MESHES = [int(x) for x in sys.argv[sys.argv.index('--meshes') + 1].split(',')]
MAX_INFLUENCE = 4
WIND_REVERSED = '--wind-rev' in sys.argv      # UE2's PSK importer mirrors Y; face winding variant

src_bones = json.load(open(os.path.join(HERE, 'skeleton.json')))['bones']
src_names = [b['name'] for b in src_bones]
src_par = [b['parent'] for b in src_bones]
src_idx = {n: i for i, n in enumerate(src_names)}
src_world = np.load(os.path.join(HERE, 'source_world.npy'))          # skeleton space, meters

tgt_scan = json.load(open(os.path.join(HERE, 'target_skeleton_scan.json')))
tgt_world_j = json.load(open(os.path.join(HERE, 'target_world.json')))
tgt_world = np.array([tgt_world_j[str(i)] for i in range(len(tgt_scan))], dtype=np.float64)
tgt_short = [b['name'].split(':')[1] for b in tgt_scan]
tgt_idx = {n: i for i, n in enumerate(tgt_short)}

# skeleton space (X=left, Y=up, Z=forward, right handed) -> UE target (X=right, Y=back, Z=up)
C = np.array([[-1, 0, 0], [0, 0, -1], [0, 1, 0]], dtype=np.float64)
src_ue = (C @ src_world.T).T


def S(n):
    return src_ue[src_idx[n]]


def T(n):
    return tgt_world[tgt_idx[n]]


def unit(v):
    return v / (np.linalg.norm(v) + 1e-12)


def rot_between(a, b):
    a, b = unit(a), unit(b)
    c = float(np.dot(a, b))
    if c > 0.999999:
        return np.eye(3)
    if c < -0.999999:
        ax = unit(np.cross(a, [1, 0, 0]) if abs(a[0]) < 0.9 else np.cross(a, [0, 1, 0]))
        return 2 * np.outer(ax, ax) - np.eye(3)
    v = np.cross(a, b)
    s = np.linalg.norm(v)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * ((1 - c) / (s * s))


def frame(f, side):
    f = unit(f)
    s = side - f * np.dot(side, f)
    s = unit(s)
    return np.stack([f, s, np.cross(f, s)], axis=1)


# global scale (source meters -> target units) from ankle..neck span
G = (T('neck')[2] - T('R_ankle')[2]) / (S('neck')[2] - S('LF_foot')[2])
print('global scale G = %.3f' % G)

# ---- driver table: src joint -> (target bone, src child, target child, mode) ----------------------------
drivers = {}


def drv(sj, tb, sc, tc, mode='dir'):
    drivers[sj] = (tb, sc, tc, mode)


for sp, tp in (('LF', 'L'), ('RT', 'R')):
    drv(sp + '_clavicle', tp + '_clavicle', sp + '_uparm', tp + '_upper_arm')
    drv(sp + '_uparm', tp + '_upper_arm', sp + '_loarm', tp + '_lower_arm')
    drv(sp + '_loarm', tp + '_lower_arm', sp + '_wrist', tp + '_wrist')
    drv(sp + '_wrist', tp + '_wrist', None, None, 'hand')
    drv(sp + '_upleg', tp + '_upper_leg', sp + '_loleg', tp + '_lower_leg')
    drv(sp + '_loleg', tp + '_lower_leg', sp + '_foot', tp + '_ankle')
    drv(sp + '_foot', tp + '_ankle', sp + '_ball', tp + '_ball', 'trans')
    drv(sp + '_ball', tp + '_ball', sp + '_ball_end', tp + '_toe', 'trans')
    for f in 'ABCD':
        tf = {'A': 'index', 'B': 'middle', 'C': 'ring', 'D': 'pinky'}[f]
        drv('%s_finger_%s_A' % (sp, f), tp + '_fingers_conn', '%s_finger_%s_B' % (sp, f), '%s_%s_01' % (tp, tf))
        drv('%s_finger_%s_B' % (sp, f), '%s_%s_01' % (tp, tf), '%s_finger_%s_C' % (sp, f), '%s_%s_02' % (tp, tf))
        drv('%s_finger_%s_C' % (sp, f), '%s_%s_02' % (tp, tf), '%s_finger_%s_D' % (sp, f), None)
    drv(sp + '_thumb_A', tp + '_thumb_01', sp + '_thumb_B', tp + '_thumb_02')
    drv(sp + '_thumb_B', tp + '_thumb_02', sp + '_thumb_C', tp + '_thumb_03')
    drv(sp + '_thumb_C', tp + '_thumb_03', sp + '_thumb_C_end', None)

for _sj, _tb in (('pelvis', 'hip'), ('spine', 'spine_01'), ('spine_B', 'spine_02'), ('chest', 'spine_03'),
                 ('neck', 'neck'), ('head', 'head'), ('jaw', 'jaw')):
    drv(_sj, _tb, None, None, 'trans')

# skeleton chain that gets its own splitted weights (torso)
TORSO_JOINTS = {'pelvis', 'a_body', 'mid', 'spine', 'spine_helper1', 'spine_helper2', 'spine_B', 'spine_B_helper1',
                'spine_B_helper2', 'chest', 'LF_chest_helper', 'RT_chest_helper', 'LF_latissimus', 'RT_latissimus',
                'LF_pelvis_side_helper', 'LF_pelvis_front_helper', 'LF_pelvis_rear_helper', 'RT_pelvis_side_helper',
                'RT_pelvis_front_helper', 'RT_pelvis_rear_helper', 'LF_upperButtock', 'LF_lowerButtock',
                'RT_upperButtock', 'RT_lowerButtock'}

# ---- per driver transform ------------------------------------------------------------------------------
Rm = {}
Km = {}
for sj, (tb, sc, tc, mode) in drivers.items():
    kmin, kmax = 0.85 * G, 1.15 * G
    if mode == 'hand':
        sp = sj[:2]
        tp = 'L' if sp == 'LF' else 'R'
        fs = S(sp + '_finger_B_B') - S(sj)
        ft = T(tp + '_middle_01') - T(tb)
        ss = S(sp + '_finger_A_A') - S(sp + '_finger_D_A')
        st = T(tp + '_index_01') - T(tp + '_pinky_01')
        Rm[sj] = frame(ft, st) @ frame(fs, ss).T
        Km[sj] = G
    elif mode == 'trans':
        Rm[sj] = np.eye(3)
        Km[sj] = G
    elif mode == 'inherit':
        continue
    elif tc is None:
        # leaf segment: use the target segment of the parent driver
        Rm[sj] = None
        Km[sj] = None
    else:
        a = S(sc) - S(sj)
        b = T(tc) - T(tb)
        Rm[sj] = rot_between(a, b)
        Km[sj] = float(np.clip(np.linalg.norm(b) / (np.linalg.norm(a) + 1e-9), kmin, kmax))

# leaf drivers copy the previous segment of their finger/thumb chain
for sp in ('LF', 'RT'):
    for f in 'ABCD':
        j = '%s_finger_%s_C' % (sp, f)
        p = '%s_finger_%s_B' % (sp, f)
        Rm[j], Km[j] = Rm[p], Km[p]
    j, p = sp + '_thumb_C', sp + '_thumb_B'
    Rm[j], Km[j] = Rm[p], Km[p]


def driver_of(j):
    while j >= 0:
        n = src_names[j]
        if n in drivers:
            return n
        j = src_par[j]
    return 'pelvis'


src_driver = [driver_of(i) for i in range(len(src_names))]
# per source joint: affine map (A, b):  x' = A @ x_ue + b
joint_A = np.zeros((len(src_names), 3, 3))
joint_b = np.zeros((len(src_names), 3))
for i, d in enumerate(src_driver):
    tb = drivers[d][0]
    k, R = Km[d], Rm[d]
    A = k * R
    joint_A[i] = A
    joint_b[i] = T(tb) - A @ S(d)

# ---- collapsed weights: source joint -> [(target bone idx, weight)] ----------------------------------
spine_bones = ['hip', 'spine_01', 'spine_02', 'spine_03', 'spine_04']
u_t = [(T(n)[2] - T('hip')[2]) / (T('neck')[2] - T('hip')[2]) for n in spine_bones]
EXTRA = {'LF_scapula_helper': 'L_clavicle', 'RT_scapula_helper': 'R_clavicle', 'neck_collar_helper': 'spine_04',
         'LF_upknee': 'L_lower_leg', 'RT_upknee': 'R_lower_leg', 'neck1_twist': 'neck', 'neck2_twist': 'neck',
         'neck3_twist': 'neck_02', 'neck4_twist': 'neck_02'}


def collapse(j):
    n = src_names[j]
    if n in EXTRA:
        return [(tgt_idx[EXTRA[n]], 1.0)]
    if n in TORSO_JOINTS:
        u = (src_world[j][1] - src_world[src_idx['pelvis']][1]) / (src_world[src_idx['neck']][1] - src_world[src_idx['pelvis']][1])
        if u <= u_t[0]:
            return [(tgt_idx['hip'], 1.0)]
        if u >= u_t[-1]:
            return [(tgt_idx['spine_04'], 1.0)]
        for a in range(len(u_t) - 1):
            if u_t[a] <= u <= u_t[a + 1]:
                t = (u - u_t[a]) / (u_t[a + 1] - u_t[a])
                return [(tgt_idx[spine_bones[a]], 1 - t), (tgt_idx[spine_bones[a + 1]], t)]
    d = src_driver[j]
    tb = drivers[d][0]
    if tb in tgt_idx:
        return [(tgt_idx[tb], 1.0)]
    return [(tgt_idx['hip'], 1.0)]


collapse_map = [collapse(j) for j in range(len(src_names))]

# ---- load + deform ------------------------------------------------------------------------------------
g = Gltf(os.path.join(HERE, 'hero_thegoatthree_lod0.gltf'))
points, wedges, faces, materials, weights = [], [], [], [], []
point_key = {}
stat = {'verts': 0, 'tris': 0}
for mi in BODY_MESHES:
    prim = g.j['meshes'][mi]['primitives'][0]
    at = prim['attributes']
    pos = g.accessor(at['POSITION']).astype(np.float64) * MESH_SCALE
    uv = g.accessor(at['TEXCOORD_0']).astype(np.float64)
    idx = g.accessor(prim['indices']).astype(np.int64).reshape(-1, 3)
    js, ws = [], []
    for k in range(3):
        if 'JOINTS_%d' % k in at:
            js.append(g.accessor(at['JOINTS_%d' % k]).astype(np.int64))
            ws.append(g.accessor(at['WEIGHTS_%d' % k]).astype(np.float64))
    J = np.concatenate(js, axis=1)
    W = np.concatenate(ws, axis=1)
    W = W / np.maximum(W.sum(1, keepdims=True), 1e-9)
    # gltf JOINTS index the skin joint list (== bone index since export kept the order)
    x_ue = (C @ pos.T).T
    new = np.zeros_like(x_ue)
    for k in range(J.shape[1]):
        A = joint_A[J[:, k]]
        b = joint_b[J[:, k]]
        new += W[:, k:k + 1] * (np.einsum('nij,nj->ni', A, x_ue) + b)
    mat_index = len(materials)
    materials.append('Raimi_m%02d' % mi)
    base_wedge = len(wedges)
    for v in range(len(new)):
        key = tuple(np.round(new[v], 3)) + tuple(J[v, :4]) + tuple(np.round(W[v, :4], 3))
        pi = point_key.get(key)
        if pi is None:
            pi = len(points)
            point_key[key] = pi
            points.append(tuple(float(c) for c in new[v]))
            tw = {}
            for k in range(J.shape[1]):
                if W[v, k] <= 0:
                    continue
                for tbi, tbw in collapse_map[J[v, k]]:
                    tw[tbi] = tw.get(tbi, 0.0) + W[v, k] * tbw
            top = sorted(tw.items(), key=lambda kv: -kv[1])[:MAX_INFLUENCE]
            s = sum(w for _, w in top)
            for tbi, w in top:
                weights.append((w / s, pi, tbi))
        wedges.append((pi, float(uv[v, 0]), float(uv[v, 1]), mat_index))
    for t in idx:
        # C has determinant -1 -> flip winding
        if WIND_REVERSED:
            faces.append((base_wedge + int(t[0]), base_wedge + int(t[1]), base_wedge + int(t[2]), mat_index, 1))
        else:
            faces.append((base_wedge + int(t[0]), base_wedge + int(t[2]), base_wedge + int(t[1]), mat_index, 1))
    stat['verts'] += len(new)
    stat['tris'] += len(idx)

print('materials', len(materials), 'points', len(points), 'wedges', len(wedges), 'faces', len(faces), 'weights', len(weights))
pts = np.array(points)
print('bbox min', pts.min(0).round(1), 'max', pts.max(0).round(1))

# The importer mirrors Y (positions and rotations) on load; feed it the mirrored stock skeleton and mesh so that
# the imported reference pose equals the stock one exactly (verified with cmp_skel.py).
def mirror_q(q):
    return (-q[0], q[1], -q[2], q[3])


bones = [(b['name'], b['parent'], mirror_q(b['orientation']), (b['position'][0], -b['position'][1], b['position'][2]),
          b['children']) for b in tgt_scan]
points = [(p[0], -p[1], p[2]) for p in points]
pts = np.array(points)
out_psk = os.path.join(OUT, 'raimi.psk')
write_psk(out_psk, points, wedges, faces, materials, bones, weights)
np.save(os.path.join(OUT, 'points.npy'), pts)
np.save(os.path.join(OUT, 'wedge_mat.npy'), np.array([w[3] for w in wedges]))
json.dump({'materials': materials, 'wedges': len(wedges)}, open(os.path.join(OUT, 'info.json'), 'w'))
print('wrote', out_psk, os.path.getsize(out_psk), 'bytes')
