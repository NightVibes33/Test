#!/usr/bin/env bash
# Generic ARM64 UEFI on QEMU TCG. NOT a Darwin/HomeView boot.
set -Eeuo pipefail
[[ $# -eq 1 ]] || { echo "usage: test-arm-uefi.sh log.txt" >&2; exit 2; }
LOG="$1"
EFI=/usr/share/qemu-efi-aarch64/QEMU_EFI.fd
[[ -f "$EFI" ]] || { echo "missing ARM UEFI: $EFI" >&2; exit 1; }
set +e
timeout -s TERM 60s qemu-system-aarch64 -machine virt -accel tcg \
  -cpu cortex-a57 -smp 2 -m 512 -bios "$EFI" \
  -display none -monitor none -serial file:"$LOG" -no-reboot
RC=$?
set -e
if [[ ! -s "$LOG" ]]; then
  echo "FAIL: ARM64 UEFI serial output missing; emulator rc=$RC" >&2
  exit 1
fi
echo "PASS: ARM UEFI executed on QEMU TCG; no Apple operating system booted"
head -15 "$LOG" || true
