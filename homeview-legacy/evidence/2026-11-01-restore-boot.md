# Genuine HomeView 27.2 — restore userspace milestone

Run: https://github.com/NightVibes33/Test/actions/runs/41332293886

Artifact: https://github.com/NightVibes33/Test/actions/runs/41332293886/artifacts/13094535151

## Verified on 2026-11-01

Official Apple HomeView 27.2 (24V514), HomeAccessory17,1 / J490,
original signed kernelcache and paired Apple software-update ramdisk
running under qemu-sptm with 2 GiB RAM.

### J490 dock node removed

- Original Apple iBoot emulation and XNU/Image4 start: **yes**
- APFS `/dev/md0` ramdisk root mounted: **yes**
- Apple `launchd` PID 1: **yes**
- Apple restore environment: **yes**
- `patchd` and `ramrod` progress reporting: **yes**
- `Waiting for NAND service to publish`: **30 occurrences**
- `unable to get framebuffer`: **17 occurrences**
- Maximum logged restoration progress: **13.896354%** (not installation success)
- Genuine HomeView Setup Assistant, BreadBoard or normal userspace: **NO**

### J490 dock node neutralized

- Original Apple restore environment: **yes**
- `Waiting for NAND service to publish`: **27 occurrences**
- `unable to get framebuffer`: **17 occurrences**
- Genuine HomeView Setup Assistant or BreadBoard: **NO**

### Controls

The unmodified J490 tree reached XNU but produced a
`PC alignment exception` with `IOPortFamily` / AppleDockConnect.
The original restore ramdisk control instead triggered an APFS root-snapshot panic.

**Interpretation:** Apple restore userspace has genuinely been reached.
The NAND service and graphical device required for HomeView's normal startup
are not provided by the current qemu-sptm `darwin` machine.
The Apple OTA ramdisk is for software updates, not a complete installed
HomeView system volume. No HomeKit functionality has been demonstrated.

The classification script in `scripts/boot_evidence.py` differentiates Apple
restore userspace from a successfully booted HomeView device. Passing a
kernel or launchd check MUST NOT make the final native GUI acceptance green.
