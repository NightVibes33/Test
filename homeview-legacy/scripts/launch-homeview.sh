#!/usr/bin/env bash
set -Eeuo pipefail
echo "HOMEVIEW_LEGACY_READY: x86_64 research host booted"
echo "This Linux host is NOT a genuine HomeView guest."
GUEST=/opt/homeview/guest.qcow2
EFI=/usr/share/qemu-efi-aarch64/QEMU_EFI.fd
if [[ ! -f "$GUEST" ]]; then
  echo "HOMEVIEW_GUEST_MISSING: no supported Intel HomeView boot image is available"
  exit 0
fi
if [[ ! -f "$EFI" ]]; then
  echo "ARM_UEFI_MISSING: $EFI"
  exit 1
fi
echo "EXPERIMENTAL_ARM64_BOOT: generic ARM UEFI is not Apple's iBoot/SEP/SPTM"
mkdir -p /var/log/homeview
exec /usr/bin/qemu-system-aarch64 \
  -machine virt -accel tcg,thread=multi -cpu max -smp 2 -m 3072 \
  -bios "$EFI" \
  -drive if=none,id=guest,format=qcow2,file="$GUEST" \
  -device virtio-blk-device,drive=guest \
  -device virtio-gpu-pci \
  -device qemu-xhci -device usb-kbd -device usb-mouse \
  -display gtk,gl=off \
  -serial file:/var/log/homeview/arm64-serial.log \
  -monitor none -no-reboot
