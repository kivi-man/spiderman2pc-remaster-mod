"""Export the first suit look/LOD to glTF with the local ALERT checkout.

ALERT's generic writer currently tries to decode every skin batch in this suit, including
other look/LOD batches. Their separate layout makes it fail. This wrapper limits decoding
to the batches that cover the vertices used by look 0, LOD 0.
"""

import argparse
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model', type=Path)
    parser.add_argument('gltf', type=Path)
    parser.add_argument('--alert-source', type=Path, default=Path('_mod/work/alert-source'))
    args = parser.parse_args()

    # _mod/tools/dis.py shadows Python's standard-library dis module.
    sys.path = [p for p in sys.path if Path(p).resolve() != Path(__file__).resolve().parent]
    sys.path.insert(0, str(args.alert_source.resolve()))
    import dat1lib
    import dat1lib.types.model
    from dat1lib.types.sections.model.look import ModelLookSection
    from dat1lib.types.sections.model.meshes import MeshesSection
    from dat1lib.types.sections.model.skin import ModelSkinBatchSection
    from model_to_gltf import GltfWriter

    with args.model.open('rb') as f:
        model = dat1lib.read(f)
    if not isinstance(model, dat1lib.types.model.Model):
        raise ValueError('Expected an MSMR model')

    looks = model.dat1.get_section(ModelLookSection.TAG)
    meshes = model.dat1.get_section(MeshesSection.TAG)
    skin_batches = model.dat1.get_section(ModelSkinBatchSection.TAG)
    lod = looks.looks[0].lods[0]
    used_meshes = meshes.meshes[lod.start:lod.start + lod.count]
    if not used_meshes:
        raise ValueError('No meshes in look 0 / LOD 0')
    required_vertices = max(m.vertexStart + m.vertexCount for m in used_meshes)
    original_count = len(skin_batches.batches)
    running = 0
    selected = []
    for batch in skin_batches.batches:
        if running == required_vertices:
            break
        running += batch.vertex_count
        selected.append(batch)
    if running != required_vertices:
        raise ValueError(f'Skin batches cover {running} vertices, expected {required_vertices}')
    skin_batches.batches = selected

    args.gltf.parent.mkdir(parents=True, exist_ok=True)
    GltfWriter().write_model(str(args.gltf), model, [0], 0)
    print(f'Exported {lod.count} meshes, {required_vertices} vertices; '
          f'used {len(selected)} of {original_count} skin batches: {args.gltf.resolve()}')


if __name__ == '__main__':
    main()
