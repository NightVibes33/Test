#!/usr/bin/env python3
"""Instrument qemu-sptm's ACTUAL J490 MMIO reads/writes for ANS and DCP research.

This is NOT working NAND, GPU, or display emulation. Registers return zeros
and writes are logged (bounded). Device probing is opt-in via env and must not
be misreported as a booted HomeView device. The upstream clone is disposable.
"""
import argparse
import pathlib

INCLUDE = '#include "hw/intc/apple_aic.h"'
ANCHOR = '    init_sep(dt_root);\n    init_cpu_impl(dt_root);'
FUNCTION = '''\
#define HV_TRACE_LIMIT 96
typedef struct HomeViewMmioTrace {
    MemoryRegion mem;
    const char *label;
    uint64_t count;
    unsigned index;
} HomeViewMmioTrace;

static uint64_t hv_mmio_read(void *opaque, hwaddr addr, unsigned size) {
    HomeViewMmioTrace *d = opaque;
    if (d->count++ < HV_TRACE_LIMIT) {
        qemu_log_mask(LOG_UNIMP, "HOMEVIEW_MMIO_TRACE read %s off=0x%" HWADDR_PRIx " size=%u index=%u\\n",
                      d->label, addr, size, d->index);
    }
    return 0;
}
static void hv_mmio_write(void *opaque, hwaddr addr, uint64_t value, unsigned size) {
    HomeViewMmioTrace *d = opaque;
    if (d->count++ < HV_TRACE_LIMIT) {
        qemu_log_mask(LOG_UNIMP, "HOMEVIEW_MMIO_TRACE write %s off=0x%" HWADDR_PRIx " value=0x%" PRIx64 " size=%u index=%u\\n",
                      d->label, addr, value, size, d->index);
    }
}
static const MemoryRegionOps hv_mmio_ops = {
    .read = hv_mmio_read,
    .write = hv_mmio_write,
    .endianness = DEVICE_NATIVE_ENDIAN,
    .valid = { .min_access_size = 1, .max_access_size = 8 },
    .impl = { .min_access_size = 1, .max_access_size = 8 },
};
#define HV_MMIO_MAX_WINDOWS 128
typedef struct HomeViewTraceWindow {
    hwaddr base, end;
} HomeViewTraceWindow;
static HomeViewTraceWindow hv_trace_windows[HV_MMIO_MAX_WINDOWS];
static size_t hv_trace_window_count;

static void hv_trace_device(MachineState *ms, struct dtree_node *root,
                            const char *name, uint64_t iobase) {
    struct dtree_node *node = adt_find_node(root, name);
    if (!node) return;
    struct adt_io_reg *regs = adt_get_prop_val(node, "reg");
    size_t bytes = adt_get_prop_len(node, "reg");
    if (!regs || !bytes || bytes % sizeof(*regs)) return;
    size_t count = bytes / sizeof(*regs);
    if (!g_getenv("HOMEVIEW_MMIO_ALL_WINDOWS")) count = MIN(count, (size_t)1);
    for (size_t i = 0; i < count; i++) {
        if (!regs[i].len) continue;
        hwaddr len = MIN(regs[i].len, (uint64_t)0x4000);
        hwaddr base = regs[i].base + iobase;
        if (base < iobase || base + len < base) {
            qemu_log_mask(LOG_UNIMP,
                "HOMEVIEW_MMIO_TRACE skipped_overflow %s index=%zu\\n", name, i);
            continue;
        }
        bool overlaps = false;
        for (size_t j = 0; j < hv_trace_window_count; j++) {
            if (base < hv_trace_windows[j].end &&
                hv_trace_windows[j].base < base + len) {
                overlaps = true;
                break;
            }
        }
        if (overlaps || hv_trace_window_count >= HV_MMIO_MAX_WINDOWS) {
            qemu_log_mask(LOG_UNIMP,
                "HOMEVIEW_MMIO_TRACE skipped_overlap %s base=0x%" HWADDR_PRIx
                " length=0x%" HWADDR_PRIx " index=%zu\\n",
                name, base, len, i);
            continue;
        }
        HomeViewMmioTrace *d = g_new0(HomeViewMmioTrace, 1);
        d->label = name;
        d->index = (unsigned)i;
        memory_region_init_io(&d->mem, OBJECT(ms), &hv_mmio_ops, d, name, len);
        memory_region_add_subregion(get_system_memory(), base, &d->mem);
        hv_trace_windows[hv_trace_window_count++] = (HomeViewTraceWindow) {
            .base = base, .end = base + len
        };
        qemu_log_mask(LOG_UNIMP,
            "HOMEVIEW_MMIO_TRACE installed %s base=0x%" HWADDR_PRIx
            " length=0x%" HWADDR_PRIx " index=%zu\\n", name, base, len, i);
    }
}
'''
CALL = '''\
    // Instrument Apple ANS/DCP probes only when explicitly requested.
    // No device functionality or guest framebuffer is implemented here.
    if (g_getenv("HOMEVIEW_MMIO_TRACE")) {
        hv_trace_device(ms, dt_root, "arm-io/ans", iobase);
        hv_trace_device(ms, dt_root, "arm-io/sart-ans", iobase);
        hv_trace_device(ms, dt_root, "arm-io/dcp", iobase);
        hv_trace_device(ms, dt_root, "arm-io/dcp0-expert", iobase);
        hv_trace_device(ms, dt_root, "arm-io/sgx", iobase);
    }
'''

def patch(text):
    if 'HOMEVIEW_MMIO_TRACE installed' in text:
        return text
    if INCLUDE not in text or ANCHOR not in text or 'static void init_sep(' not in text:
        raise ValueError("Upstream qemu-sptm machine layout changed; refusing unsafe patch")
    return (text.replace(INCLUDE, INCLUDE + '\n#include "qemu/log.h"')
        .replace('static void init_sep(', FUNCTION + '\nstatic void init_sep(')
        .replace(ANCHOR, ANCHOR + '\n' + CALL))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('darwin_c')
    args=parser.parse_args()
    path=pathlib.Path(args.darwin_c)
    original=path.read_text()
    updated=patch(original)
    path.write_text(updated)
    print('Installed opt-in trace hooks:', updated.count('hv_trace_device(ms,'))

if __name__=='__main__':
    main()
