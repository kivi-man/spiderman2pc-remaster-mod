#!/bin/bash
# Compile MSMSpidey.u in a copy of System (_mod/buildroot) while the game keeps running.
# Result: _mod/buildroot/System/MSMSpidey.u (install with the game closed).
R="/h/Spider-Man 2/_mod/buildroot"
mkdir -p "$R/System" "$R/MSMSpidey"
rm -rf "$R/MSMSpidey/Classes"; cp -r "/h/Spider-Man 2/MSMSpidey/Classes" "$R/MSMSpidey/"
for f in "/h/Spider-Man 2/System/"*; do
  b=$(basename "$f")
  case "$b" in MSMSpidey.u|*.log) continue;; esac
  cp -u "$f" "$R/System/" 2>/dev/null
done
cp "/h/Spider-Man 2/_mod/loader/d3d8.dll" "$R/System/d3d8.dll"
sed -i 's#^Paths=\.\./System/\*\.u#Paths=../System/*.u#; s#^Paths=\.\./\(Maps\|TestMaps\|Textures\|Sounds\|Music\|StaticMeshes\|Animations\|Saves\)/#Paths=H:/Spider-Man 2/\1/#' "$R/System/Webhead.ini"
cd "$R/System" || exit 1
rm -f MSMSpidey.u ModLoader.log
./Webhead.exe -ucc=Editor.MakeCommandlet
grep -E "Error|error|Warning|Success" ModLoader.log | awk '!s[$0]++'
[ -f MSMSpidey.u ] || { echo "BUILD FAILED"; exit 1; }
