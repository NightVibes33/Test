#!/usr/bin/env bash
# Experimental Apple ARM Darwin kernel execution. Deliberately serial-only.
# Genuine HomeView graphical output is not supported by this QEMU backend.
set -Eeuo pipefail
QEMU=${HOMEVIEW_QEMU:-/opt/homeview/bin/qemu-system-aarch64-sptm}
FW=${HOMEVIEW_FIRMWARE_DIR:-/opt/homeview/firmware}
for required in "$QEMU" "$FW/bootkc" "$FW/dtree"; do
  [[ -s "$required" ]] || {
    echo "APPLE_DARWIN_MISSING_INPUT: $required" >&2
    exit 78
  }
done
# 'auto' prefers the Apple original software-update recovery ramdisk,
# which is the only one experimentally shown to start launchd/ramrod.
# This is NOT the installed HomeView OS or BreadBoard.
MODE=${HOMEVIEW_BOOT_VARIANT:-auto}
case "$MODE" in
  auto)
    if [[ -e "$FW/ramdisk-su.dmg" || -e "$FW/ramdisk-su.tc" ]]; then
      MODE=software-update
    else
      MODE=restore
    fi
    ;;
  software-update|restore) ;;
  *)
    echo "APPLE_DARWIN_INVALID_VARIANT: $MODE (auto|software-update|restore)" >&2
    exit 64
    ;;
esac
case "$MODE" in
  software-update)
    ERROR_VARIANT="SOFTWARE_UPDATE"
    RAMDISK="$FW/ramdisk-su.dmg"
    TRUSTCACHE="$FW/ramdisk-su.tc"
    ;;
  restore)
    ERROR_VARIANT="RESTORE"
    RAMDISK="$FW/ramdisk.dmg"
    TRUSTCACHE="$FW/ramdisk.tc"
    ;;
esac
for required in "$RAMDISK" "$TRUSTCACHE"; do
  [[ -s "$required" ]] || {
    # macOS ships Bash 3.2; ${var^^} is Bash 4+ and exits before our code 78.
    echo "APPLE_DARWIN_INCOMPLETE_${ERROR_VARIANT}_FIRMWARE: $required" >&2
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
  -tc "$TRUSTCACHE"
  -ramdisk "$RAMDISK"
  -args "rd=md0 serial=3 -v -noprogress wdt=-1"
  -nographic -serial mon:stdio
  -m "${HOMEVIEW_GUEST_RAM:-3G}"
)
if [[ -f "$FW/sptm" ]]; then ARGS+=(-sptm "$FW/sptm" -txm "$FW/txm"); fi
echo "APPLE_DARWIN_BOOT_VARIANT: $MODE (genuine Apple restore/update environment, not installed HomeView)"
echo "DARWIN_SERIAL_ONLY: no framebuffer in current QEMU Apple platform"
exec "$QEMU" "${ARGS[@]}"
