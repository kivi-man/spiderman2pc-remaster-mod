# Raimi .suit extraction research — 2026-10-12

## Verified local result

Input: `H:\Spider-Man 2\msmraimimod.suit` (338,537,387 bytes).
Embedded name: `GuitarthVader's Raimi 2007 Suit`; id: `thegoatthree`.

The ZIP contains a legacy 21-byte binary asset index in `info.txt`, despite its extension.
Each record is little-endian `uint32 offset, uint32 unknown, uint32 size, uint64 asset_id, uint8 span`.
This file contains 112 records followed by one zero byte. The index points into the extensionless
`thegoatthree/thegoatthree` payload (914,680,396 bytes). The payload is directly readable after ZIP
decompression; no additional decryption was needed.

The path `characters/hero/hero_thegoatthree/hero_thegoatthree.model` hashes to `A8E153F1DD3C8893`.
It matches index record 111, span 0, offset 896,177,400, length 18,502,996 bytes.
The extracted file is `hero_thegoatthree.model` in this directory.
SHA-256: `7b70f3422166ab535f96c2b438150e02d47295aac23781f007f2eb66a1978420`.

The model has the MSMR model magic `98906B9F` and a DAT1 container starting at byte 36.
Joint section `15DF9D3B` has 3,696 bytes: 231 joint records. Joint names, parents, local scale,
quaternion, position and 4x4 matrices are exported to `skeleton.json`.
Examples: `a_body`, `pelvis`, `LF_upleg`, `LF_loleg`, `LF_foot`, `LF_uplegTwist`.
There are also IK, attachment and deformation helper joints; 231 is not the count of essential
body joints and should not be treated as the required target rig count.

Skin batch section `C61B1FF5` is present (3,824 bytes), as is skin weight section `DCA379A2`
(2,723,353 bytes). Weight values and geometry have not yet been exported or visually checked.

Validation performed on the real input: index bounds and non-overlap, expected path hash,
ZIP payload CRC by reading through EOF, model/DAT1 signatures, section bounds, complete joint
records, parent range, acyclic bone hierarchy, finite transforms. This confirms extraction and
structural parsing only, not compatibility with Spider-Man 2 (2004) or in-game rendering.

## Reproduce

From the game directory:

```powershell
python _mod/tools/inspect_suit.py msmraimimod.suit --model-path characters/hero/hero_thegoatthree/hero_thegoatthree.model --out _mod/work/raimi_suit
```

The helper uses only the Python standard library. It supports this legacy index layout, not all
formats called `.suit`. It does not install the suit, alter the original archive, or touch System/Animations.
Output filenames are controlled by the helper, not arbitrary paths from the ZIP.

## Sources and confidence

- Primary source, checked against the actual archive:
  [Overstrike MSMRSuitInstaller](https://github.com/Tkachov/Overstrike/blob/9f906ca09ea5ce4b84528410171c235bc4b0bfe6/Overstrike/Installers/MSMRSuitInstaller.cs),
  especially `WriteAssetsFile`, documents the index record layout.
- Primary source, checked against the model:
  [ALERT model type](https://github.com/Tkachov/ALERT/blob/bc90ed9b53fbcaa3b7acf94b36f00e77eab0dacb/dat1lib/types/model.py),
  [joints](https://github.com/Tkachov/ALERT/blob/bc90ed9b53fbcaa3b7acf94b36f00e77eab0dacb/dat1lib/types/sections/model/joints.py),
  [skin sections](https://github.com/Tkachov/ALERT/blob/bc90ed9b53fbcaa3b7acf94b36f00e77eab0dacb/dat1lib/types/sections/model/skin.py).
- Available conversion route, source inspected but not installed or executed here:
  [ALERT](https://github.com/Tkachov/ALERT) provides `model_to_ascii.py` and `model_to_gltf.py`.
  Its ASCII writer handles joints and skin weights; its README warns that export does not preserve
  every proprietary model feature. Successful export of this particular model remains unverified.
- Issue indexes inspected: [ALERT](https://github.com/Tkachov/ALERT/issues),
  [Overstrike](https://github.com/Tkachov/Overstrike/issues). No tool was recommended solely from a search snippet.

Queries used: `GitHub Spider Man Remastered suit file format info.txt suit tool model blender importer`;
`Spider Man Remastered model importer github skeleton model id daemon export ascii`;
`site.nexusmods.com/marvelsspidermanremastered/mods/5367 suit extractor`;
`site.github.com spiderman model "bone" "DAT1"`.

No screenshots: this was a file-format investigation, with no visual or in-game success claim.
No forum attachments, tool executables, original game downloads or external asset uploads were used.

## Remaining work for an actual port

Export geometry, weights and needed materials/textures; extract the 2004 target skeleton; map
deformation bones and merge appropriate influences; fit scale and bind pose; produce a compatible
UE2 mesh package; verify deformation and rendering in game. The source .suit is sufficient to start
this work without asking the user for a separate FBX, but extraction alone is not a completed port.
