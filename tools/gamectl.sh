#!/bin/bash
# Helpers to drive the running game reliably (it pauses itself whenever it loses focus).
# source this file, then:  ensure_running ; shot name ; press 0x76 ...
LOG="/h/Spider-Man 2/System/ModLoader.log"
SHOTS="${SHOTS:-./shots}"

dbg_count() { grep -a -c "MSMDBG" "$LOG"; }

# true when MSMDBG lines keep arriving (the game is simulating)
is_running() {
  local a b
  a=$(dbg_count); sleep 3.2; b=$(dbg_count)
  [ "$b" -gt "$a" ]
}

# resume if paused: focus the window then Esc (toggle) until the log moves again
ensure_running() {
  local i
  for i in 1 2 3; do
    if is_running; then return 0; fi
    um win drive --proc Webhead "focus" "key 0x1B" "sleep 800" >/dev/null 2>&1
  done
  is_running
}

press() { um win drive --proc Webhead "$@" >/dev/null 2>&1; }

# shot <name> [scale]: full-frame capture into the scratchpad, prints the path
shot() { um win shot --exe Webhead.exe "$SHOTS/$1.png" ${2:+--scale $2} | tail -1; }
