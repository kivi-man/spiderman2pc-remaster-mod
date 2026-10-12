"""Write the msmexec import script: textures (Raimi_mNN) then the suit meshes, saved to out/MSMSuit.ukx.

Every skeletal mesh also needs the stock mesh scale / origin / rotation (read from SpideyMesh): Scale 0.92,
Origin z 55.418, RotOrigin yaw 90 degrees; the importer leaves them zero, which makes the mesh invisible.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
MESHES = [('RaimiSuit', 'full_a')]
lines = ['@init', '@package MSMSuit']
for mi in range(7, 21):
    tga = os.path.join(OUT, 'tex', 'Raimi_m%02d.dds' % mi)
    lines.append('TEXTURE IMPORT NAME=Raimi_m%02d FILE="%s" MIPS=0' % (mi, tga))
for name, folder in MESHES:
    lines.append('MESH MODELIMPORT MESH=%s MODELFILE="%s"' % (name, os.path.join(OUT, folder, 'raimi.psk')))
    lines.append('MESHMAP SCALE MESHMAP=%s X=0.92 Y=0.92 Z=0.92' % name)
    lines.append('MESH ORIGIN MESH=%s X=0 Y=0 Z=55.418 YAW=64' % name)
for name, folder in MESHES:
    lines.append('@linkanim MSMSuit.%s SpideyAnimations.SpideyAnim' % name)
lines.append('@save "%s"' % os.path.join(OUT, 'MSMSuit.ukx'))
path = os.path.join(OUT, 'import_full.txt')
open(path, 'w', newline='\n').write('\n'.join(lines) + '\n')
print(path, len(lines), 'lines')
