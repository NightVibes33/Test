#!/usr/bin/env bash
# Actual host hardware discovery. Does not establish Apple HomeView device support.
set -Eeuo pipefail
[[ $# -eq 1 ]] || { echo "usage: hardware-audit.sh /path/report.txt" >&2; exit 2; }
OUT="$1"
mkdir -p "$(dirname "$OUT")"
{
  echo "HOMEVIEW_HOST_HARDWARE_AUDIT_V1"
  echo "TimestampUTC=$(date -u +%FT%TZ)"
  echo "CPUArchitecture=$(uname -m)"
  echo "LogicalCPUs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown)"
  echo "CPUModel=$(grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//' || true)"
  echo "RAMKiB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
  echo "Kernel=$(uname -r)"
  if [[ -d /sys/firmware/efi ]]; then echo "EFI=yes"; else echo "EFI=no"; fi
  echo "GraphicsPCI:"
  lspci -nnk 2>/dev/null | grep -E -A3 'VGA compatible|3D controller|Display controller' || true
  echo "DRM:"
  ls -l /sys/class/drm 2>/dev/null || true
  echo "USBControllers:"
  lspci -nnk 2>/dev/null | grep -E -A2 'USB controller' || true
  echo "USBDevices:"
  lsusb 2>/dev/null || true
  echo "KeyboardMouseInput:"
  for dev in /sys/class/input/event*/device/name; do
    [[ -e "$dev" ]] || continue
    printf '%s ' "$dev"; cat "$dev"
  done
  echo "AudioHardware:"
  aplay -l 2>&1 || true
  echo "SoundCards:"
  cat /proc/asound/cards 2>/dev/null || true
  echo "AudioOutputTest=not_performed_by_CI"
  echo "NetworkDevices:"
  ip -br link 2>/dev/null || true
  echo "StorageDevices:"
  lsblk -o NAME,TYPE,SIZE,TRAN,MODEL 2>/dev/null || true
  echo "GenuineHomeViewGraphics=not_implemented"
  echo "GenuineHomeViewUSB=not_verified"
  echo "GenuineHomeViewAudio=not_verified"
  echo "GenuineHomeViewAppleSetup=not_verified"
} | tee "$OUT"
