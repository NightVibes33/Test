#!/usr/bin/env bash
# EFI/GRUB/Linux/launcher boot proof only. No Apple firmware used.
set -Eeuo pipefail
[[ $# -eq 2 ]] || { echo "usage: test-uefi.sh image.raw output.log" >&2; exit 2; }
IMG=$(realpath "$1")
LOG=$(realpath -m "$2")
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
[[ -f "$CODE" && -f "$VARS" ]] || { echo "OVMF 4M files missing" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$VARS" "$TMP/vars.fd"
# Stop as soon as the real guest writes the launcher marker; don't waste 300s.
timeout -s TERM 240s qemu-system-x86_64 -accel tcg,thread=multi \
  -machine q35 -cpu qemu64 -smp 2 -m 2048 \
  -display none -monitor none -no-reboot \
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
