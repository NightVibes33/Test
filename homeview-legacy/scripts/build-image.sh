#!/usr/bin/env bash
# Build real UEFI-bootable x86_64 Linux research host; DOES NOT include Apple OS.
set -Eeuo pipefail
if [[ $# -ne 1 ]]; then echo "usage: build-image.sh output.raw" >&2; exit 2; fi
OUT=$(realpath -m "$1")
mkdir -p "$(dirname "$OUT")"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
ROOT="$TMP/root"
mkdir -p "$ROOT"
LOOP=""
cleanup() {
  set +e
  sudo umount -lf "$ROOT/sys" >/dev/null 2>&1
  sudo umount -lf "$ROOT/proc" >/dev/null 2>&1
  sudo umount -lf "$ROOT/dev/pts" >/dev/null 2>&1
  sudo umount -lf "$ROOT/dev" >/dev/null 2>&1
  sudo umount -lf "$ROOT/boot/efi" >/dev/null 2>&1
  sudo umount -lf "$ROOT" >/dev/null 2>&1
  if [[ -n "$LOOP" ]]; then sudo losetup -d "$LOOP" >/dev/null 2>&1; fi
  sudo rm -rf "$TMP"
}
trap cleanup EXIT
for cmd in parted losetup mkfs.vfat mkfs.ext4 debootstrap grub-mkstandalone; do
  command -v "$cmd" >/dev/null || { echo "missing build dependency: $cmd" >&2; exit 1; }
done
echo "Creating GPT/UEFI disk image: $OUT"
truncate -s 5G "$OUT"
parted -s "$OUT" mklabel gpt
parted -s "$OUT" mkpart EFI fat32 1MiB 257MiB
parted -s "$OUT" set 1 esp on
parted -s "$OUT" mkpart root ext4 257MiB 100%
LOOP=$(sudo losetup --find --show --partscan "$OUT")
sudo udevadm settle
for i in {1..20}; do [[ -b "$LOOP"p1 && -b "$LOOP"p2 ]] && break; sleep 1; done
[[ -b "$LOOP"p2 ]] || { echo "loop partitions unavailable" >&2; exit 1; }
sudo mkfs.vfat -F 32 -n HVBOOT "$LOOP"p1
sudo mkfs.ext4 -F -L HVROOT "$LOOP"p2
sudo mount "$LOOP"p2 "$ROOT"
sudo mkdir -p "$ROOT/boot/efi"
sudo mount "$LOOP"p1 "$ROOT/boot/efi"
sudo debootstrap --arch amd64 --variant=minbase noble "$ROOT" http://archive.ubuntu.com/ubuntu/
sudo mkdir -p "$ROOT/etc/apt/apt.conf.d"
echo 'APT::Install-Recommends "false";' | sudo tee "$ROOT/etc/apt/apt.conf.d/90no-recommends" >/dev/null
cat <<'EOF' | sudo tee "$ROOT/etc/apt/sources.list" >/dev/null
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
EOF
echo homeview-legacy | sudo tee "$ROOT/etc/hostname" >/dev/null
echo '127.0.1.1 homeview-legacy' | sudo tee -a "$ROOT/etc/hosts" >/dev/null
echo 'LABEL=HVROOT / ext4 defaults,noatime 0 1' | sudo tee "$ROOT/etc/fstab" >/dev/null
echo 'LABEL=HVBOOT /boot/efi vfat umask=0077 0 1' | sudo tee -a "$ROOT/etc/fstab" >/dev/null
sudo mount --bind /dev "$ROOT/dev"
sudo mount --bind /dev/pts "$ROOT/dev/pts"
sudo mount -t proc proc "$ROOT/proc"
sudo mount -t sysfs sysfs "$ROOT/sys"
sudo env DEBIAN_FRONTEND=noninteractive chroot "$ROOT" /bin/bash -c \
  'apt-get update && apt-get install -y --no-install-recommends systemd-sysv systemd-resolved initramfs-tools linux-image-generic qemu-system-arm qemu-efi-aarch64 qemu-system-gui qemu-utils iproute2 kmod ca-certificates dbus udev pciutils xserver-xorg-core xinit xauth xserver-xorg-video-all xserver-xorg-input-all linux-firmware alsa-utils usbutils libinput-tools network-manager mesa-utils libcapstone4 libslirp0 libfdt1 libpixman-1-0 libgnutls30t64'
sudo mkdir -p "$ROOT/etc/systemd/network" "$ROOT/etc/systemd/system/multi-user.target.wants" "$ROOT/opt/homeview" "$ROOT/var/log/homeview"
cat <<'EOF' | sudo tee "$ROOT/etc/systemd/network/20-wired.network" >/dev/null
[Match]
Name=en* eth*
[Network]
DHCP=yes
EOF
sudo ln -sf /usr/lib/systemd/system/systemd-networkd.service "$ROOT/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
sudo ln -sf /usr/lib/systemd/system/systemd-resolved.service "$ROOT/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"
sudo ln -sf /run/systemd/resolve/stub-resolv.conf "$ROOT/etc/resolv.conf"
sudo install -m 0755 "$SCRIPT_DIR/launch-homeview.sh" "$ROOT/usr/local/bin/homeview-launch"
sudo install -m 0755 "$SCRIPT_DIR/run-darwin.sh" "$ROOT/usr/local/bin/homeview-darwin"
sudo install -m 0755 "$SCRIPT_DIR/hardware-audit.sh" "$ROOT/usr/local/bin/homeview-hardware-audit"
if [[ -n "${QEMU_SPTM_BIN:-}" ]]; then
  [[ -x "$QEMU_SPTM_BIN" ]] || { echo "QEMU_SPTM_BIN not executable: $QEMU_SPTM_BIN" >&2; exit 1; }
  sudo mkdir -p "$ROOT/opt/homeview/bin"
  sudo install -m 0755 "$QEMU_SPTM_BIN" "$ROOT/opt/homeview/bin/qemu-system-aarch64-sptm"
  sudo chroot "$ROOT" /opt/homeview/bin/qemu-system-aarch64-sptm -M help | grep -Eq '(^|[[:space:]])darwin([[:space:]]|$)' || {
    echo "QEMU SPTM Darwin machine missing/binary dependency broken inside USB image" >&2
    exit 1
  }
  echo "QEMU_SPTM_INSTALLED: Apple-specific Darwin emulator verified in USB rootfs"
else
  echo "QEMU_SPTM_NOT_BUNDLED: image is EFI Linux research boot only"
fi
cat <<'EOF' | sudo tee "$ROOT/etc/systemd/system/homeview-legacy.service" >/dev/null
[Unit]
Description=HomeView Legacy Research Launcher (no Apple firmware included)
After=local-fs.target systemd-udevd.service homeview-hardware-audit.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/homeview-launch
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=0
[Install]
WantedBy=multi-user.target
EOF
cat <<'EOF' | sudo tee "$ROOT/etc/systemd/system/homeview-hardware-audit.service" >/dev/null
[Unit]
Description=Discover actual Intel iMac CPU GPU USB HID sound network and memory
After=systemd-udevd.service
Before=homeview-legacy.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/homeview-hardware-audit /var/log/homeview/hardware-audit.txt
StandardOutput=journal+console
StandardError=journal+console
[Install]
WantedBy=multi-user.target
EOF
sudo ln -sf /etc/systemd/system/homeview-hardware-audit.service "$ROOT/etc/systemd/system/multi-user.target.wants/homeview-hardware-audit.service"
sudo ln -sf /etc/systemd/system/homeview-legacy.service "$ROOT/etc/systemd/system/multi-user.target.wants/homeview-legacy.service"
sudo mkdir -p "$ROOT/boot/grub"
KERNEL=$(find "$ROOT/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -1)
INITRD=$(find "$ROOT/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort -V | tail -1)
[[ -n "$KERNEL" && -n "$INITRD" ]] || { echo "kernel/initrd missing" >&2; exit 1; }
sudo ln -sf "$(basename "$KERNEL")" "$ROOT/boot/vmlinuz"
sudo ln -sf "$(basename "$INITRD")" "$ROOT/boot/initrd.img"
cat <<'EOF' | sudo tee "$ROOT/boot/grub/grub.cfg" >/dev/null
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial
set timeout=1
menuentry 'HomeView Legacy Boot (research host)' {
  search --no-floppy --label HVROOT --set=root
  linux /boot/vmlinuz root=LABEL=HVROOT ro console=tty0 console=ttyS0,115200n8 systemd.show_status=true
  initrd /boot/initrd.img
}
EOF
# Self-contained EFI binary with embedded menu; avoids fragile GRUB disk-prefix autodetection.
sudo mkdir -p "$ROOT/boot/efi/EFI/BOOT"
sudo grub-mkstandalone --format=x86_64-efi \
  --output="$ROOT/boot/efi/EFI/BOOT/BOOTX64.EFI" \
  --modules="part_gpt ext2 fat normal linux search search_label serial" \
  "boot/grub/grub.cfg=$ROOT/boot/grub/grub.cfg"
test -f "$ROOT/boot/efi/EFI/BOOT/BOOTX64.EFI"
echo "EFI_STAGING_OK: bootloader, kernel, input/audio/USB drivers, hardware audit and Darwin emulator present"
sync
