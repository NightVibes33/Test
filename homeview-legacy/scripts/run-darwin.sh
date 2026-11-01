#!/usr/bin/env bash
# Experimental Apple ARM Darwin kernel execution. Deliberately serial-only.
# Genuine HomeView graphical output is not supported by this QEMU backend.
set -Eeuo pipefail
QEMU=\${HOMEVIEW_QEMU:-/opt/homeview/bin/qemu-system-aarch64-sptm}
FW=\${HOMEVIEW_FIRMWARE_DIR:-/opt/homeview/firmware}
for required in "$QEMU" "$FW/bootkc" "$FW/dtree" "$FW/ramdisk.dmg" "$FW/ramdisk.tc"; do
  [[ -f "$required" ]] || {
    echo "APPLE_DARWIN_MISSING_INPUT: $required" >&2
    exit 78
  }
done
[[ -x "$QEMU" ]] || { echo "APPLE_QEMU_NOT_EXECUTABLE" >&2; exit 78; }
if [[ -f "$FW/sptm" && ! -f "$FW/txm" ]] || [[ ! -f "$FW/sptm" && -f "$FW/txm" ]]; then
  echo "SPTM/TXM must either both be present or both be absent" >&2
  exit 78
fi
ARGS=(
  -M darwin
  -bootkc "$FW/bootkc"
  -dtree "$FW/dtree"
  -tc "$FW/ramdisk.tc"
  -ramdisk "$FW/ramdisk.dmg"
  -args "rd=md0 serial=3 -v -noprogress wdt=-1"
  -nographic -serial mon:stdio
  -m "\${HOMEVIEW_GUEST_RAM:-3G}"
)
if [[ -f "$FW/sptm" ]]; then ARGS+=(-sptm "$FW/sptm" -txm "$FW/txm"); fi
echo "DARWIN_SERIAL_ONLY: no framebuffer in current QEMU Apple platform"
exec "$QEMU" "\${ARGS[@]}"
