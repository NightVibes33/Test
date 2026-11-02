/*
 * HomeView 24V514: read-only Apple guest PC observer for qemu-sptm API v7.
 * Only exact vtable VAs and 48-byte original code fingerprints.
 * No guest memory/register writes or hardware emulation.
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
#define MAX_SIGNATURES 8
#define SIGNATURE_WORDS 12
#define SIGNATURE_BYTES (SIGNATURE_WORDS * 4)

typedef struct {
    uint64_t address;
    volatile int seen;
} PCTarget;
typedef struct {
    uint64_t static_address;
    uint64_t guest_address;
    uint8_t bytes[SIGNATURE_BYTES];
    volatile int hooked;
    volatile int seen;
} PCSignature;

static PCTarget targets[MAX_TARGETS];
static PCSignature signatures[MAX_SIGNATURES];
static size_t count;
static size_t signature_count;

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

static void signature_hit(unsigned int cpu, void *userdata)
{
    PCSignature *s = userdata;
    if (!__sync_bool_compare_and_swap(&s->seen, 0, 1)) {
        return;
    }
    char msg[210];
    snprintf(msg, sizeof(msg),
             "HOMEVIEW_PC_TRACE fingerprint_hit static=0x%" PRIx64
             " guest=0x%" PRIx64 " cpu=%u\n",
             s->static_address, s->guest_address, cpu);
    qemu_plugin_outs(msg);
}

static bool matches_signature(const struct qemu_plugin_tb *tb, size_t start,
                              size_t total, const PCSignature *s)
{
    if (start + SIGNATURE_WORDS > total) {
        return false;
    }
    for (size_t k = 0; k < SIGNATURE_WORDS; ++k) {
        const struct qemu_plugin_insn *insn =
            qemu_plugin_tb_get_insn(tb, start + k);
        uint8_t instruction[4];
        if (qemu_plugin_insn_data(insn, instruction, 4) != 4 ||
            memcmp(instruction, s->bytes + 4 * k, 4)) {
            return false;
        }
    }
    return true;
}

static void translate(struct qemu_plugin_tb *tb, void *userdata)
{
    (void)userdata;
    size_t total = qemu_plugin_tb_n_insns(tb);
    for (size_t i = 0; i < total; i++) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        uint64_t addr = qemu_plugin_insn_vaddr(insn);
        for (size_t j = 0; j < count; j++) {
            if (targets[j].address == addr) {
                qemu_plugin_register_vcpu_insn_exec_cb(
                    insn, hit, QEMU_PLUGIN_CB_NO_REGS, &targets[j]);
            }
        }
        for (size_t j = 0; j < signature_count; j++) {
            PCSignature *s = &signatures[j];
            if (s->hooked || !matches_signature(tb, i, total, s)) {
                continue;
            }
            if (__sync_bool_compare_and_swap(&s->hooked, 0, 1)) {
                s->guest_address = addr;
                qemu_plugin_register_vcpu_insn_exec_cb(
                    insn, signature_hit, QEMU_PLUGIN_CB_NO_REGS, s);
            }
        }
    }
}

static int nibble(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    return -1;
}

static int parse_address(const char *raw, char **end, uint64_t *address)
{
    if (strncmp(raw, "0x", 2)) {
        return -1;
    }
    errno = 0;
    *address = strtoull(raw, end, 0);
    return errno || !*address || (*address & 3) ? -1 : 0;
}

QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id,
                                          const qemu_info_t *info,
                                          int argc, char **argv)
{
    if (!info->system_emulation || strcmp(info->target_name, "aarch64")) {
        return -1;
    }
    for (int i = 0; i < argc; i++) {
        char *end = NULL;
        uint64_t addr;
        if (!strncmp(argv[i], "addr=", 5)) {
            if (count == MAX_TARGETS ||
                parse_address(argv[i] + 5, &end, &addr) || *end) {
                return -1;
            }
            for (size_t j = 0; j < count; j++) {
                if (targets[j].address == addr) {
                    return -1;
                }
            }
            targets[count++].address = addr;
        } else if (!strncmp(argv[i], "sig=", 4)) {
            if (signature_count == MAX_SIGNATURES ||
                parse_address(argv[i] + 4, &end, &addr) || *end != ':') {
                return -1;
            }
            const char *hex = end + 1;
            if (strlen(hex) != SIGNATURE_BYTES * 2) {
                return -1;
            }
            PCSignature *s = &signatures[signature_count];
            s->static_address = addr;
            for (size_t k = 0; k < SIGNATURE_BYTES; k++) {
                int high = nibble(hex[2 * k]);
                int low = nibble(hex[2 * k + 1]);
                if (high < 0 || low < 0) {
                    return -1;
                }
                s->bytes[k] = (uint8_t)((high << 4) | low);
            }
            signature_count++;
        } else {
            return -1;
        }
    }
    if (!count && !signature_count) {
        return -1;
    }
    qemu_plugin_register_vcpu_tb_trans_cb(id, translate, NULL);
    char msg[160];
    snprintf(msg, sizeof(msg),
             "HOMEVIEW_PC_TRACE initialized targets=%zu signatures=%zu read_only=true\n",
             count, signature_count);
    qemu_plugin_outs(msg);
    return 0;
}
