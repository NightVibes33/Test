# HomeView Legacy Boot — temporary Intel research port

Target device: 2010 Intel iMac (iMac11,2).
Goal: eventual boot of the GENUINE Apple HomeView 27.2 operating system
(build 24V514, HomeAccessory17,1), not an imitation UI.

## What the branch actually implements

A standalone x86_64 UEFI Linux host image with GRUB, kernel, ARM64
QEMU TCG emulator, ARM UEFI, and explicit diagnostics. It is a real USB
disk image builder and CI boot harness, NOT yet a HomeView installer.

Four CI stages:
1. Check genuine Apple HomeView metadata and upstream BreadBoard bringup.
2. Run tests on a real Intel macOS hosted runner.
3. Start generic ARM64 UEFI in QEMU software emulation.
4. Build a 5 GiB UEFI Linux disk, boot with QEMU x86 TCG, and assert
   that the launcher service actually ran.

Every stage states exactly what was tested. A successful workflow does
not prove a genuine HomeView boot on an Intel host.

## Blocking work

ARM64e HomeView cannot execute natively on your Intel CPU. OpenCore can
manage EFI, not translate instructions. The virtual HomeAccessory17,1
hardware, Apple boot chain, SEP/TXM/SPTM compatibility, display services,
framebuffer, HID, and native BreadBoard services are not implemented in
generic QEMU ARM virt. A compatible Apple guest disk that boots on this
emulated hardware does not currently exist.

VPhone's existing HomeView guest works on physically hosted Apple Silicon,
using Apple's Virtualization.framework and private PV=3 capabilities;
that backend cannot run on an x86 Mac or a standard GitHub macOS VM.

The launcher optionally accepts /opt/homeview/guest.qcow2 for diagnostics.
It starts generic ARM UEFI if the file exists. This is an experimental hook,
NOT a proven Apple guest boot path and NOT a HomeView firmware conversion.

## Sources

- https://github.com/Lakr233/vphone-cli
- https://github.com/Lakr233/vphone-cli/blob/main/Research/Firmware/homeview_bringup.md
- https://github.com/jprx/darwin-vm

Firmware is NOT downloaded, extracted, embedded, or redistributed in this
repository or generated USB image. The firmware check only reads the public
upstream Swift catalog and bringup markdown.

## Run on GitHub Actions

Open Actions > HomeView Legacy Boot - EFI and ARM TCG research.
Select the temp/homeview-legacy-boot branch, then Run workflow.

The resulting artifact, if the EFI smoke test passes, is named
homeview-legacy-research-usb. It contains a compressed raw disk image,
SHA-256 hash, and serial log. The firmware and ARM-UEFI jobs have separate
reports. Artifact retention is 7 days.

Manual Ubuntu 24.04 build (requires sudo, internet, and loop block devices):

    sudo apt-get update
    sudo apt-get install -y debootstrap parted dosfstools e2fsprogs grub-efi-amd64-bin grub2-common qemu-system-x86 ovmf zstd
    bash homeview-legacy/scripts/build-image.sh out/homeview-legacy.raw
    bash homeview-legacy/scripts/test-uefi.sh out/homeview-legacy.raw out/serial.log

WARNING: writing this image to a USB device erases the chosen device.
Do not overwrite your internal Mac drive. This USB is a research Linux host,
not a usable HomeView operating system.

## Required next research milestones

- EFI/Linux boot on physical iMac, including real display and Wi-Fi.
- Boot Apple's ARM Darwin kernel under software emulation with correct
  platform drivers and security environment.
- Run the real BreadBoard launcher with working graphics/touch.
- Validate Apple account, HomeKit, camera, music and appliance functions.
- Measure performance on the dual-core 2010 Intel processor.

None of these milestones is claimed complete by this branch.
