#!/usr/bin/env bash
# EFI/GRUB/Linux/launcher boot proof only. No Apple firmware used.
set -Eeuo pipefail
[[ $# -eq 3 ]] || { echo "usage: test-uefi.sh image.raw output.log console.png" >&2; exit 2; }
IMG=$(realpath "$1")
LOG=$(realpath -m "$2")
PNG=$(realpath -m "$3")
MONITOR=""
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
[[ -f "$CODE" && -f "$VARS" ]] || { echo "OVMF 4M files missing" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$VARS" "$TMP/vars.fd"
MONITOR="$TMP/hmp.sock"
# Stop as soon as the real guest writes the launcher marker; don't waste 300s.
timeout -s TERM 240s qemu-system-x86_64 -accel tcg,thread=multi \
  -machine q35 -cpu qemu64 -smp 2 -m 2048 \
  -vga std -display none -monitor "unix:$MONITOR,server=on,wait=off" -no-reboot \
  -device qemu-xhci,id=usbhost -device usb-kbd,bus=usbhost.0 -device usb-mouse,bus=usbhost.0 \
  -audiodev none,id=silent -device ich9-intel-hda -device hda-duplex,audiodev=silent \
  -netdev user,id=nic0 -device virtio-net-pci,netdev=nic0 \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$TMP/vars.fd" \
  -drive if=virtio,format=raw,file="$IMG" \
  -serial file:"$LOG" &
QEMU_PID=$!
stop_qemu() { kill "$QEMU_PID" 2>/dev/null || true; wait "$QEMU_PID" 2>/dev/null || true; }
trap 'stop_qemu; rm -rf "$TMP"' EXIT
for ((i=0; i<240; i++)); do
  if grep -Fq 'HOMEVIEW_LEGACY_READY' "$LOG"; then
    echo "PASS: EFI -> GRUB -> x86 Linux -> launch service (TCG)"
    PPM="$TMP/console.ppm"
    # QEMU's own simulated VGA framebuffer, not a constructed dashboard.
    printf 'screendump %s\n' "$PPM" | timeout 8s socat - "UNIX-CONNECT:$MONITOR" >/dev/null 2>&1 || true
    for ((j=0; j<30; j++)); do [[ -s "$PPM" ]] && break; sleep 0.2; done
    if [[ ! -s "$PPM" ]]; then
      echo "FAIL: QEMU could not supply a real VGA framebuffer screenshot" >&2
      exit 1
    fi
    python3 homeview-legacy/scripts/ppm_to_png.py "$PPM" "$PNG"
    # Require the guest OS's actual device enumeration, not a fake hardware report.
    grep -Fq 'HOMEVIEW_HOST_HARDWARE_AUDIT_V1' "$LOG" || {
      echo "FAIL: actual guest hardware audit never ran" >&2
      exit 1
    }
    grep -Fq 'CPUArchitecture=x86_64' "$LOG" || {
      echo "FAIL: no guest CPU architecture evidence" >&2
      exit 1
    }
    grep -Fq 'RAMKiB=' "$LOG" || {
      echo "FAIL: no guest memory evidence" >&2
      exit 1
    }
    echo "HOST_HARDWARE_AUDIT_CAPTURED: real guest device list saved in serial log"
    echo "SCREENSHOT_CAPTURED: $PNG (real QEMU x86 VGA, NOT HomeView)"
    echo "HomeView/BreadBoard on Intel remains UNVERIFIED."
    exit 0
  fi
  if grep -Eq 'grub> $' "$LOG"; then
    echo "FAIL: GRUB entered recovery command shell" >&2
    tail -60 "$LOG" >&2
    exit 1
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
echo "FAIL: guest never emitted HomeView research launcher marker" >&2
tail -100 "$LOG" >&2
exit 1
