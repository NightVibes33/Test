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
set +e
timeout -s TERM 300s qemu-system-x86_64 -accel tcg -machine q35 -cpu max \
  -smp 2 -m 2048 -display none -monitor none -no-reboot \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$TMP/vars.fd" \
  -drive if=virtio,format=raw,file="$IMG" \
  -serial file:"$LOG"
RC=$?
set -e
if grep -Fq 'HOMEVIEW_LEGACY_READY' "$LOG"; then
  echo "PASS: EFI -> GRUB -> x86 Linux -> launch service (TCG)"
  echo "HomeView/BreadBoard on Intel remains UNVERIFIED."
else
  echo "FAIL: launcher marker absent; emulator rc=$RC" >&2
  tail -100 "$LOG" >&2
  exit 1
fi
