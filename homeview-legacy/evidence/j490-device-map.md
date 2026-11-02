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
