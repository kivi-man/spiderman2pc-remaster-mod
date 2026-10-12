#!/bin/bash
# Kill the game, recompile MSMSpidey.u, optionally relaunch with -modlog.
cd "/h/Spider-Man 2/System" || exit 1
PIDS=$(tasklist //FI "IMAGENAME eq Webhead.exe" //FO CSV //NH 2>/dev/null | grep -i webhead | cut -d, -f2 | tr -d '"')
if [ -n "$PIDS" ]; then
  if [ "$1" != "kill" ] && [ "$2" != "kill" ]; then echo "GAME RUNNING (pid $PIDS) - ask the user, then rerun with 'kill'"; exit 2; fi
  for pid in $PIDS; do taskkill //PID "$pid" //F >/dev/null 2>&1; done
fi
sleep 1
rm -f MSMSpidey.u
./Webhead.exe -ucc=Editor.MakeCommandlet
grep -E "Error|error|Warning|Success" ModLoader.log | awk '!s[$0]++'
[ -f MSMSpidey.u ] || { echo "BUILD FAILED"; exit 1; }
if [ "$1" = "run" ] || [ "$2" = "run" ]; then
  powershell -NoProfile -Command "Start-Process -FilePath 'H:\Spider-Man 2\System\Webhead.exe' -WorkingDirectory 'H:\Spider-Man 2\System' -ArgumentList '-modlog'"
  echo launched
fi
