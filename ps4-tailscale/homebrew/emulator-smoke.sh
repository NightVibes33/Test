#!/usr/bin/env bash
# Only capture real emulator windows, after the guest reports its first flip.
set -euo pipefail
emulator=$(realpath "$1")
game=$(realpath "$2")
out=$(realpath -m "$3")
mkdir -p "$out"
test -s "$game"
# shadPS4 v0.21.0 calls create_directory, not create_directories.
# Give the emulator a fresh, existing XDG parent instead of assuming
# ~/.local/share exists on hosted runners.
work=$(mktemp -d)
export XDG_DATA_HOME="$work/data"
export XDG_CONFIG_HOME="$work/config"
export XDG_CACHE_HOME="$work/cache"
export XDG_RUNTIME_DIR="$work/runtime"
mkdir -p "$XDG_DATA_HOME/shadPS4" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export DISPLAY=:95
export SDL_VIDEODRIVER=x11
export SDL_AUDIODRIVER=dummy
export LIBGL_ALWAYS_SOFTWARE=1
cd "$work"
# Avoid an AppImage wrapper PID that differs from the actual window owner.
if [[ "$emulator" == *.AppImage ]]; then
 "$emulator" --appimage-extract >"$out/appimage-extract.log" 2>&1
 emulator="$work/squashfs-root/AppRun"
 test -x "$emulator"
fi
Xvfb "$DISPLAY" -screen 0 1440x900x24 -nolisten tcp >"$out/xvfb.log" 2>&1 &
xpid=$!
pid=""
cleanup(){
 rc=$?
 trap - EXIT
 if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
 kill "$xpid" 2>/dev/null || true
 if [[ -d "$XDG_DATA_HOME/shadPS4/log" ]]; then cp -a "$XDG_DATA_HOME/shadPS4/log" "$out/shad-logs" || true; fi
 if [[ -d "$XDG_DATA_HOME/shadPS4/logs" ]]; then cp -a "$XDG_DATA_HOME/shadPS4/logs" "$out/shad-logs" || true; fi
 if [[ -f "$out/emulator.log" ]]; then tail -n 100 "$out/emulator.log" || true; fi
 if [[ -f "$out/result.txt" ]]; then cat "$out/result.txt"; fi
 rm -rf "$work"
 exit "$rc"
}
trap cleanup EXIT
for i in $(seq 1 20); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done
xdpyinfo >/dev/null
if command -v vulkaninfo >/dev/null; then vulkaninfo --summary >"$out/vulkan.txt" 2>&1 || true; fi
"$emulator" --config-clean "$game" >"$out/emulator.log" 2>&1 &
pid=$!
for i in $(seq 1 90); do
 if ! kill -0 "$pid" 2>/dev/null; then
  code=0; wait "$pid" || code=$?
  echo "Emulator exited before verified frame (exit $code)" >"$out/result.txt"; exit 1
 fi
 if grep -q 'PS4TS_UI_FRAME_PRESENTED' "$out/emulator.log" || grep -rqs 'PS4TS_UI_FRAME_PRESENTED' "$XDG_DATA_HOME/shadPS4/log" "$XDG_DATA_HOME/shadPS4/logs"; then
  # The isolated X server runs only the emulator. Check window geometry;
  # reject small utility/dialog windows.
  for win in $(xdotool search --onlyvisible --class '.*' 2>/dev/null || true); do
   geo=$(xdotool getwindowgeometry --shell "$win" 2>/dev/null || true)
   width=$(printf '%s\n' "$geo" | sed -n 's/^WIDTH=//p')
   height=$(printf '%s\n' "$geo" | sed -n 's/^HEIGHT=//p')
   if [[ ${width:-0} -ge 640 && ${height:-0} -ge 360 ]]; then
    sleep 2
    import -window "$win" "$out/emulator-fixture.png"
    test -s "$out/emulator-fixture.png"
    echo "Guest reported frame presented; captured actual emulator window. Fixture, NOT a live VPN." >"$out/result.txt"
    exit 0
   fi
  done
 fi
 sleep 1
done
echo "No verified emulator frame/window; no screenshot published." >"$out/result.txt"
exit 1
