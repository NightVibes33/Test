#!/usr/bin/env bash
# Called by systemd on physical/virtual Intel Mac startup.
set -Eeuo pipefail
echo "HOMEVIEW_LEGACY_READY: x86_64 research host booted"
echo "This is Linux, NOT the native Apple HomeView launcher."
if [[ ! -f /opt/homeview/firmware/bootkc ]]; then
  echo "APPLE_HOMEVIEW_FIRMWARE_MISSING: no Apple Darwin kernel installed"
  echo "APPLE_BREADBOARD_NOT_RUNNING: Full genuine HomeView display is not supported on Intel yet"
  exit 0
fi
echo "EXPERIMENTAL_DARWIN_BOOT_SELECTED: starting Apple-specific QEMU"
exec /usr/local/bin/homeview-darwin
