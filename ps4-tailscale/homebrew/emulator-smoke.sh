#!/usr/bin/env bash
# Capture actual emulator windows only, never a generated substitute.
set -eu
emulator=$(realpath "$1")
game=$(realpath "$2")
out=$(realpath -m "$3")
mkdir -p "$out"
cd "$(dirname "$emulator")"
export DISPLAY=:95
export LIBGL_ALWAYS_SOFTWARE=1
Xvfb "$DISPLAY" -screen 0 1440x900x24 -nolisten tcp >"$out/xvfb.log" 2>&1 &
xpid=$!
pid=""
cleanup(){ if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; fi; kill "$xpid" 2>/dev/null || true; }
trap cleanup EXIT
for i in $(seq 1 20); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done
"$emulator" "$game" >"$out/emulator.log" 2>&1 &
pid=$!
for i in $(seq 1 60); do
 if ! kill -0 "$pid" 2>/dev/null; then echo "Emulator exited before verified frame" >"$out/result.txt";exit 1;fi
 if grep -q 'PS4TS_UI_FRAME_PRESENTED' "$out/emulator.log"; then
  win=$(xdotool search --onlyvisible --pid "$pid" 2>/dev/null | tail -1 || true)
  if [[ -n "$win" ]]; then
   sleep 2
   import -window "$win" "$out/emulator-fixture.png"
   echo "Emulator reported frame presented; captured its window. Fixture, NOT a live VPN." >"$out/result.txt"
   exit 0
  fi
 fi
 sleep 1
done
echo "No verified emulator frame/window; no screenshot published." >"$out/result.txt"
exit 1
