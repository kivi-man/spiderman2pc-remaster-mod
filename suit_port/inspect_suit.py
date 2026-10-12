"""Inspect a legacy MSMR .suit and optionally extract one model for local research.

Format references (read as documentation; no third-party code is executed):
https://github.com/Tkachov/Overstrike/blob/9f906ca09ea5ce4b84528410171c235bc4b0bfe6/Overstrike/Installers/MSMRSuitInstaller.cs
https://github.com/Tkachov/ALERT/blob/bc90ed9b53fbcaa3b7acf94b36f00e77eab0dacb/dat1lib/types/sections/model/joints.py
This reader deliberately supports only the 21-byte legacy index records.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import zipfile


def asset_id(path):
    polynomial = 0xC96C5795D7870F42
    crc = polynomial
    for value in path.replace('\\', '/').lower().encode('utf-8'):
        crc ^= value
        for _ in range(8):
            crc = (crc >> 1) ^ (polynomial if crc & 1 else 0)
    return (crc >> 2) | 0x8000000000000000


def inspect_model(data):
    if len(data) < 52 or struct.unpack_from('<I', data)[0] != 0x98906B9F:
        raise ValueError('Expected an MSMR model header')
    dat = memoryview(data)[36:]
    magic, kind, size, count, unknowns = struct.unpack_from('<IIIHH', dat)
    if magic != 0x44415431 or size > len(dat) or 16 + count * 12 > size:
        raise ValueError('Invalid DAT1 header')
    sections = {}
    for i in range(count):
        tag, offset, length = struct.unpack_from('<III', dat, 16 + i * 12)
        if tag in sections or offset + length > size:
            raise ValueError('Duplicate or out-of-bounds DAT1 section')
        sections[tag] = (offset, length)
    joint_offset, joint_size = sections[0x15DF9D3B]
    if joint_size % 16:
        raise ValueError('Incomplete joint record')
    joint_count = joint_size // 16
    transform_offset, transform_size = sections[0xDCC88A19]
    matrix_offset = (joint_count * 48 + 63) // 64 * 64
    if matrix_offset + joint_count * 64 > transform_size:
        raise ValueError('Incomplete joint transforms')
    bones = []
    for i in range(joint_count):
        parent, index, descendants, flags, name_hash, name_offset = struct.unpack_from(
            '<hHHHII', dat, joint_offset + i * 16)
        if not (-1 <= parent < joint_count) or parent == i or name_offset >= size:
            raise ValueError('Invalid joint parent or name offset')
        end = data.find(b'\0', 36 + name_offset, 36 + size)
        if end < 0:
            raise ValueError('Unterminated joint name')
        name = data[36 + name_offset:end].decode('ascii')
        transform = struct.unpack_from('<12f', dat, transform_offset + i * 48)
        matrix = struct.unpack_from('<16f', dat, transform_offset + matrix_offset + i * 64)
        if not all(math.isfinite(v) for v in transform + matrix):
            raise ValueError('Non-finite joint transform')
        bones.append(dict(index=i, stored_index=index, name=name, parent=parent,
                          scale=transform[:3], rotation_xyzw=transform[4:8],
                          local_position=transform[8:11], matrix44=matrix))
    for bone in bones:
        seen = set()
        i = bone['index']
        while i != -1:
            if i in seen:
                raise ValueError('Cycle in skeleton hierarchy')
            seen.add(i)
            i = bones[i]['parent']
    return dict(model_bytes=len(data), model_sha256=hashlib.sha256(data).hexdigest(),
                dat1_bytes=size, bone_count=joint_count, bones=bones,
                sections={f'{tag:08X}': dict(offset=o, size=s) for tag, (o, s) in sections.items()},
                has_skin_batches=0xC61B1FF5 in sections,
                has_skin_weights=0xDCA379A2 in sections)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('suit', type=Path)
    parser.add_argument('--model-path', required=True)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    target = asset_id(args.model_path)
    with zipfile.ZipFile(args.suit) as archive:
        names = archive.namelist()
        id_names = [n for n in names if n.rsplit('/', 1)[-1] == 'id.txt']
        if len(id_names) != 1:
            raise ValueError('Expected exactly one suit id')
        folder = id_names[0].rsplit('/', 1)[0]
        suit_id = archive.read(id_names[0]).decode('utf-8-sig').strip()
        suit_name = archive.read(folder + '/name.txt').decode('utf-8-sig').strip()
        payload = archive.getinfo(folder + '/' + suit_id)
        info = archive.read(folder + '/info.txt')
        if len(info) % 21 != 1 or info[-1] != 0:
            raise ValueError('Unsupported legacy index layout')
        records = []
        previous_end = 0
        for i in range(len(info) // 21):
            offset, unknown, length, aid, span = struct.unpack_from('<IIIQB', info, i * 21)
            if offset < previous_end or offset + length > payload.file_size:
                raise ValueError('Overlapping or out-of-bounds asset')
            previous_end = offset + length
            records.append(dict(index=i, offset=offset, size=length, asset_id=f'{aid:016X}',
                                span=span, unknown=unknown))
        matches = [r for r in records if r['asset_id'] == f'{target:016X}' and r['span'] == 0]
        if len(matches) != 1:
            raise ValueError('Expected one model matching the requested path hash')
        record = matches[0]
        if record['size'] > 256 * 1024 * 1024:
            raise ValueError('Model exceeds inspection memory limit')
        with archive.open(payload) as stream:
            remaining = record['offset']
            while remaining:
                chunk = stream.read(min(4 * 1024 * 1024, remaining))
                if not chunk:
                    raise ValueError('Truncated payload')
                remaining -= len(chunk)
            model = stream.read(record['size'])
            if len(model) != record['size']:
                raise ValueError('Truncated model')
            while stream.read(4 * 1024 * 1024):
                pass  # Read to EOF so zipfile verifies the payload CRC.
        skeleton = inspect_model(model)
        report = dict(source=str(args.suit.resolve()), name=suit_name, suit_id=suit_id,
                      payload_bytes=payload.file_size, record_count=len(records),
                      model_path=args.model_path, model_record=record, records=records)
        args.out.mkdir(parents=True, exist_ok=True)
        for name, content in [('hero_thegoatthree.model', model),
                              ('suit_manifest.json', json.dumps(report, indent=2).encode()),
                              ('skeleton.json', json.dumps(skeleton, indent=2).encode())]:
            destination = args.out / name
            if destination.exists() and destination.read_bytes() != content:
                raise FileExistsError(f'Refusing to overwrite different content: {destination}')
            destination.write_bytes(content)
        print(json.dumps(dict(name=suit_name, records=len(records), model_bytes=len(model),
                              bones=skeleton['bone_count'], has_skin_weights=skeleton['has_skin_weights'],
                              model_sha256=skeleton['model_sha256'], output=str(args.out.resolve())), indent=2))


if __name__ == '__main__':
    main()
