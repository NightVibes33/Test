/*
 * HomeView 24V514: read-only Apple guest PC observer for qemu-sptm API v7.
 * Only exact vtable VAs; no guest memory/register writes or hardware emulation.
 */
#include "plugins/qemu-plugin.h"
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;
#define MAX_TARGETS 24

typedef struct {
    uint64_t address;
    volatile int seen;
} PCTarget;
static PCTarget targets[MAX_TARGETS];
static size_t count;

static void hit(unsigned int cpu, void *userdata)
{
    PCTarget *t = userdata;
    if (!__sync_bool_compare_and_swap(&t->seen, 0, 1)) {
        return;
    }
    char msg[140];
    snprintf(msg, sizeof(msg),
             "HOMEVIEW_PC_TRACE hit target=0x%" PRIx64 " cpu=%u\n",
             t->address, cpu);
    qemu_plugin_outs(msg);
}

static void translate(struct qemu_plugin_tb *tb, void *userdata)
{
    (void)userdata;
    for (size_t i = 0; i < qemu_plugin_tb_n_insns(tb); i++) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        uint64_t addr = qemu_plugin_insn_vaddr(insn);
        for (size_t j = 0; j < count; j++) {
            if (targets[j].address == addr) {
                qemu_plugin_register_vcpu_insn_exec_cb(
                    insn, hit, QEMU_PLUGIN_CB_NO_REGS, &targets[j]);
            }
        }
    }
}

QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id,
                                          const qemu_info_t *info,
                                          int argc, char **argv)
{
    if (!info->system_emulation || strcmp(info->target_name, "aarch64")) {
        return -1;
    }
    for (int i = 0; i < argc; i++) {
        if (strncmp(argv[i], "addr=0x", 7) || count == MAX_TARGETS) {
            return -1;
        }
        errno = 0;
        char *end = NULL;
        uint64_t addr = strtoull(argv[i] + 5, &end, 0);
        if (errno || !end || *end || !addr || (addr & 3)) {
            return -1;
        }
        for (size_t j = 0; j < count; j++) {
            if (targets[j].address == addr) {
                return -1;
            }
        }
        targets[count++].address = addr;
    }
    if (!count) {
        return -1;
    }
    qemu_plugin_register_vcpu_tb_trans_cb(id, translate, NULL);
    char msg[120];
    snprintf(msg, sizeof(msg),
             "HOMEVIEW_PC_TRACE initialized targets=%zu read_only=true\n",
             count);
    qemu_plugin_outs(msg);
    return 0;
}
