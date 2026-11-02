#!/usr/bin/env bash
# Import prepared Apple firmware from the EFI FAT partition or extra FAT32 USB.
# Never fetch, decrypt, or bundle Apple system binaries.
set -Eeuo pipefail
IMPORTER=/usr/local/bin/homeview-import-firmware.py
DEST=/opt/homeview/firmware
ESP=/boot/efi/HomeView
if [[ -s "$ESP/manifest.json" ]]; then
  exec /usr/bin/python3 "$IMPORTER" --source "$ESP" --destination "$DEST"
fi
# 256MiB EFI system partition may be too small for genuine Apple restore
# images. An extra FAT32 volume with the label HVFIRMWARE is also supported.
DEV="$(/usr/sbin/blkid -L HVFIRMWARE 2>/dev/null || true)"
if [[ -z "$DEV" || ! -b "$DEV" ]]; then
  echo "HOMEVIEW_FIRMWARE_IMPORT: no user-provided firmware volume"
  exit 0
fi
MOUNT=/run/homeview-firmware-usb
mkdir -p "$MOUNT"
mount -t vfat -o ro,nosuid,nodev,noexec "$DEV" "$MOUNT"
cleanup() { umount "$MOUNT" || true; }
trap cleanup EXIT
if [[ -s "$MOUNT/HomeView/manifest.json" ]]; then
  /usr/bin/python3 "$IMPORTER" --source "$MOUNT/HomeView" --destination "$DEST"
elif [[ -s "$MOUNT/manifest.json" ]]; then
  /usr/bin/python3 "$IMPORTER" --source "$MOUNT" --destination "$DEST"
else
  echo "HOMEVIEW_FIRMWARE_IMPORT: HVFIRMWARE has no prepared manifest"
fi
