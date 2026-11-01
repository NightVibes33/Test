#!/usr/bin/env bash
# Experimental Apple Darwin SPTM boot path. NOT validated with HomeView firmware.
set -Eeuo pipefail
QEMU=/opt/homeview/bin/qemu-system-aarch64-sptm
FW=/opt/homeview/firmware
for item in "$QEMU" "$FW/bootkc" "$FW/dtree" "$FW/ramdisk.dmg" "$FW/ramdisk.tc" "$FW/sptm" "$FW/txm"; do
  if [[ ! -f "$item" ]]; then
    echo "APPLE_DARWIN_MISSING_INPUT: $item" >&2
    echo "Firmware files must be locally prepared; this project does not redistribute Apple firmware." >&2
    exit 78
  fi
done
echo "EXPERIMENTAL_APPLE_DARWIN_TCG: attempting boot to SERIAL only; no HomeView graphics support"
exec "$QEMU" \
  -M darwin \
  -bootkc "$FW/bootkc" \
  -sptm "$FW/sptm" \
  -txm "$FW/txm" \
  -dtree "$FW/dtree" \
  -tc "$FW/ramdisk.tc" \
  -ramdisk "$FW/ramdisk.dmg" \
  -args "rd=md0 serial=3 -v -noprogress wdt=-1" \
  -nographic -serial mon:stdio
