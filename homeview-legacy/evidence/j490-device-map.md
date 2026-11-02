# J490 HomeView hardware: verified device map

Source: original Apple HomeView 27.2 / 24V514 device tree, analyzed in [Actions run 41337939773](https://github.com/NightVibes33/Test/actions/runs/41337939773).

| Hardware | Apple ADT path | Device identity |
|---|---|---|
| NAND/ANS storage | /device-tree/arm-io/ans | iop,ascwrap-v6 |
| ANS firmware service | /device-tree/arm-io/ans/iop-ans-nub | iop-nub,rtbuddy-v2 |
| Storage IOMMU | /device-tree/arm-io/sart-ans | sart,coastguard |
| Display co-processor | /device-tree/arm-io/dcp | iop,ascwrap-v6 |
| Display firmware service | /device-tree/arm-io/dcp/iop-dcp-nub | iop-nub,rtbuddy-v2 |
| Display controller | /device-tree/arm-io/dcp0-expert | dcp-expert-v1 |
| Display translation | /device-tree/arm-io/dart-dcp | dart,t8110 |
| GPU | /device-tree/arm-io/sgx | gpu,t8140 |
| Graphics ASC | /device-tree/arm-io/gfx-asc | iop,ascwrap-v6 |
| Touchscreen | /device-tree/arm-io/spi1/multi-touch | hid-transport,thirdpartyspi |
| Speakers | /device-tree/arm-io/i2c1/audio-speaker | audio-control,max98397 |

The inventory classifies 9 storage-related, 18 graphics/display-related, 9 USB/input-related, 35 audio-related and 5 network-related nodes. These are keyword matches, not counts of working emulated controllers.

The real HomeView OTA and its software-update ramdisk reach Apple XNU, launchd, patchd and ramrod under QEMU. The serial reports lack of NAND and framebuffer services. The generic QEMU Darwin machine does not implement Apple ANS, DCP or SGX.

Experimental diagnostic: HOMEVIEW_MMIO_TRACE captures bounded register reads/writes against ANS, DCP and SGX addresses. It does not model complete hardware or imply that native graphics work.

For an authentic HomeView boot screenshot, the pixels must come from Apple's active guest display and Setup Assistant or BreadBoard must independently be confirmed. A host Linux screenshot, extracted asset, or someone else's VM screenshot is not proof of this Intel port. Current status: no native HomeView graphical boot on Intel.

## Source-backed J490 register/interrupt contract (2026-11-02)

`scripts/extract_j490_mmio_contract.py` decodes the actual Apple J490ADP
DeviceTree on the ephemeral firmware runner. It records ANS, SART-ANS,
DCP, DCP0 expert, DART-DCP, SGX and relevant input/audio register windows,
physical MMIO addresses and raw interrupt numbers, without copying Apple's
firmware into the GitHub artifact.

The physical address translation is taken from the pinned jprx/qemu-sptm
source: `arm-io/ranges[1] + adt_io_reg.base`. A second script,
`verify_j490_mmio_log.py`, cross-checks every **installed** QEMU probe window
against the original address and length. The optional trace includes
`sart-ans` in addition to ANS and the display controls.

This validates emulator mapping provenance only; **nothing here implements
NAND, NVMe queues, ASC mailboxes, interrupts, firmware upload, DMA, DCP
framebuffer or host GPU acceleration**.

## Original ANS register reachability — 2026-11-02

The original HomeView 24V514 J490 DeviceTree gives `/arm-io/ans/reg[0]`
`base=0x389600000, length=0x88000`. Previous diagnostic QEMU mapped
only `0x4000` at that base. The Linux Apple NVMe driver maps the coprocessor
registers and NVMe register bank separately, uses the linear SQ control at
`+0x24908`, the NVMMU TCB count at `+0x28100`, and TCB invalidation at
`+0x28118`; all lie outside the prior diagnostic 16KiB window.
The isolated ANS-binding probe now maps the *original* whole
`0x88000` window. The paired Pumpkin control retains the identical
`0x4000` coverage to preserve its experimental isolation.

Reference: https://github.com/torvalds/linux/blob/master/drivers/nvme/host/apple.c
and Apple ASC mailbox.c in the Linux tree. Register names from Linux are
comparative guidance, not a proof of identical behavior in Apple's HomeView
J490 driver. The host-side read handlers still return zero; the guest still
has **no** functional RTKit, ASC mailbox, NVMMU, DMA, NVMe queue, persistent
NAND image, block backend, APFS volume, or graphical display emulator.

## HomeView J490 native ANS/NVMe personality properties

The Apple-original `/arm-io/ans` node includes `nvme-linear-sq`,
`nvme-num-sl`, `nvme-queue-entries`, `nvme-interrupt-idx`,
`nvme-secure-bar`, `nvme-tl-wa`, `iommu-parent`,
`namespaces`, and `iop-version`. They are now included in
`homeview-j490-mmio-contract.json` using decoded original scalar values
or a SHA-256/size-only description for opaque firmware binary properties.
Missing values remain explicitly absent; no default is substituted.
This is metadata only: the QEMU guest will still not see a hardware-backed
Apple ANS device until ASC/RTKit, SART, NVMMU, queues, interrupts, and
persistent block storage are implemented.

## Original J490 ANS2 matching-driver provenance

The original 24V514 kernelcache contains AppleANS2, AppleANS3, AppleNVMe,
AppleDCP, RTBuddy and SART string markers. The decoded J490 ADT's
`/arm-io/ans` declares `role=ANS2`, `nvme-num-sl=2`,
`nvme-queue-entries=64`, `nvme-interrupt-idx=4`, `iommu-parent=93`.
A new pinned-firmware workflow now runs the documented
`ipsw kernel kexts --json` against the **original decrypted Mach-O**,
and emits `homeview-original-kext-iokit-personalities.json`: genuine
KEXT bundle IDs, versions, and bounded IOKit match selectors such as
`IOProviderClass`, `IONameMatch`, and `IOPropertyMatch`.
That is materially stronger driver-identification evidence than searching
for arbitrary substring matches, but it still cannot prove an Apple driver
matches/starts in QEMU or that any NAND, NVMe, RTKit or DCP functionality works.

The pinned QEMU source's TLBI page-granule error is logged with
`LOG_GUEST_ERROR` and returns a zero-length range, not a direct
emulator fatal assertion. Preserve the error in diagnostics; don't infer
it caused an observed guest shutdown without corroborating runtime evidence.

## Actual Apple J490 ANS2 service dependency graph

The original 24V514 kernelcache analysis artifact from
[Actions 41509325012](https://github.com/NightVibes33/Test/actions/runs/41509325012)
proves the *embedded* `com.apple.driver.AppleA7IOP-ASCWrap-v6`,
`com.apple.driver.RTBuddy`, `com.apple.iokit.IONVMeFamily`, and
`com.apple.driver.AppleSART` IOKit personality selectors. They match
the original ADT's `iop,ascwrap-v6` and `iop-nub,rtbuddy-v2` identities.
The IONVMeFamily includes **multiple controller classes** with
`IOProviderClass=RTBuddyService` and `IOPropertyMatch.role=ANS2`,
so there is no evidence that any single AppleANS2/AppleANS3 class has won.
The DCP equivalent uses `role=DCP`. The original Apple guest's full
31-region ANS binding diagnostic produced **zero MMIO read/write
events**, and the guest still blocked waiting for NAND and framebuffer.
This argues for checking actual service publishing, the ASC mailbox,
RTBuddy/RTKit firmware handshake, and SART authorization before attempting
functional NVMe queues.

`scripts/analyze_j490_kexts.py` now generates
`source_backed_IOKit_service_dependency_graph` for ANS and DCP,
preserving every matching candidate and explicit false runtime flags.
A matching Info.plist does not establish an instantiated provider service
or functional ANS, NVMe, DCP or APFS volumes.

## Original Apple ANS2 kernel C++ method inspection

`scripts/inspect_original_iokit_classes.py` uses the source-backed
`ipsw kernel cpp --class NAME --methods` command against the **decrypted
original** kernelcache on the ephemeral macOS 27 runner. It records
bounded C++ vtable/method evidence for AppleASCWrapV6, AppleA7IOPNub,
RTBuddy, RTBuddyService, AppleANS2NVMeController,
AppleANS2DARTNVMeController, AppleANS3NVMeController,
IOCoastGuardSARTMapper, and AppleDCPExpert. The generated
`homeview-original-iokit-cpp-methods.json` contains no binary firmware,
limits each class to 110 lines and 24 unique addresses, and identifies
failed/timed-out queries instead of fabricating method resolutions.
A vtable or `start()` method in a Mach-O is **not proof of invocation**
in QEMU; actual guest IORegistry/driver matching remains unproven.

## Corrected guest-driver runtime finding — original J490 24V514

The original ANS-compatible device-tree experiment is **not merely**
evidence of source-embedded IOKit personalities. Its genuine Apple guest
serial contains an invoked `RTBuddy(ANS2): start()`, followed by
`AppleANS2CGv2Controller::probe` (400000),
`AppleANS2NVMeController::probe` (100000),
`AppleANS3CGv2Controller::probe` (500000), and
`AppleANS3NVMeController::probe` (300000). The matched original-control
serial contains none of those messages. Four methods were **probed**;
the 500000 score is only the largest *reported* score and does not prove
that this class won, successfully started or published NAND. The native
Apple guest still logs `Couldn't alloc class "AFKResource"`, waits for
NAND publishing, and reports no framebuffer. The expanded isolated QEMU
ANS/SART stub mapping records **zero register accesses**, which clearly
does not negate the runtime IOKit probe evidence.

`scripts/analyze_ans2_boot.py` now publishes the exact distinctions
in `homeview-ans2-runtime-matching.json`, comparing the original Apple
control and compatible-only experimental serial and the QEMU MMIO log.
The next implementation target is finding why no ANS2 NVMe controller
`start()`/RTKit mailbox/NAND service success follows the probe path.
