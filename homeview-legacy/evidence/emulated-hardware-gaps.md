# Verified Intel HomeView emulation hardware gap

Source: [jprx/qemu-sptm hw/arm/darwin.c](https://github.com/jprx/qemu-sptm/blob/main/hw/arm/darwin.c)

Examined 2026-11-01. The `darwin` machine currently sets up:

- Apple-specific XNU kernelcache, SPTM, TXM, Apple Device Tree and trustcache
- ARM CPU and special register handling, Apple AMCC
- Apple AIC interrupt controller and Samsung-compatible UART
- Minimal SEP InvalidateHmac memory region and CPU implementation registers

There is **no Apple NAND/storage-controller model** and **no HomeView display-controller,
GPU, or Apple framebuffer model** instantiated in this machine. Adding a generic
QEMU VGA adapter does not make it appear as Apple's platform framebuffer to
HomeView's drivers. The `-disable-pvg` build cannot provide Apple's Metal-backed
paravirtual graphics on an Intel Linux host.

Original Apple HomeView restore logs from
[run 41332293886](https://github.com/NightVibes33/Test/actions/runs/41332293886)
show both `Waiting for NAND service to publish` and
`unable to get framebuffer`. Those observations match the absent virtual
hardware models.

## Missing work before a real HomeView setup screen can exist

1. Implement or accurately adapt the HomeAccessory17,1 storage-controller MMIO,
   interrupts, DMA, block-device protocol, and persistent APFS system/data disks.
2. Prepare and boot a genuine *installed system volume* using the Apple TV HD
   restore-base / HomeView OTA userland path; the current SU ramdisk only starts
   Apple's **restore/update** environment, not the regular HomeView desktop.
3. Implement the native Apple framebuffer and display pipeline with full
   BreadBoard rendering, not a rendered lookalike.
4. Feed actual Apple guest input events and audio through supported devices,
   then validate USB/mouse/keyboard/speakers on the physical 2010 Intel iMac.
5. Capture genuine Apple Hello, proximity setup, and BreadBoard screenshots from
   the guest's **own** framebuffer; never substitute the Linux host screenshot.

These are not solved by the current EFI USB, Linux drivers, QEMU `virtio-gpu`
or device-tree alterations. The previous certified USB boot image remains a
**Linux/QEMU research environment** rather than an Apple OS installation.
