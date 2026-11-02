/*
 * Read-only HomeView 24V514 Apple code entry observer (QEMU API v7).
 *
 * A fingerprint hit means that its first instruction really executed AND
 * 48 matching code bytes were observed (from translated instructions or
 * an execution-time guest virtual-memory read). It is not proof that all
 * 12 instructions, the controller's start(), or storage completed.
 */
#include "plugins/qemu-plugin.h"
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;
#define MAX_TARGETS 24
#define MAX_SIGNATURES 8
#define SIGNATURE_WORDS 12
#define SIGNATURE_BYTES (SIGNATURE_WORDS * 4)
#define MAX_CANDIDATES 250000

typedef struct {
    uint64_t address;
    volatile int seen;
} PCTarget;

typedef struct {
    uint64_t static_address;
    uint8_t bytes[SIGNATURE_BYTES];
    volatile int seen;
} PCSignature;

typedef struct {
    PCSignature *signature;
    uint64_t guest_address;
    bool complete_in_tb;
} PCMatch;

static PCTarget targets[MAX_TARGETS];
static PCSignature signatures[MAX_SIGNATURES];
static size_t count;
static size_t signature_count;
static int trace_fd = -1;
static volatile int candidate_count;
static volatile int candidate_overflow;

/* One write per event: a dedicated artifact does not depend on -d plugin.
 * A simultaneous qemu_plugin_outs copy preserves existing debug-log parsing.
 */
static void trace_event(const char *msg)
{
    qemu_plugin_outs(msg);
    if (trace_fd >= 0) {
        size_t remaining = strlen(msg);
        const char *pos = msg;
        while (remaining) {
            ssize_t n = write(trace_fd, pos, remaining);
            if (n < 0 && errno == EINTR) {
                continue;
            }
            if (n <= 0) {
                break;
            }
            pos += n;
            remaining -= (size_t)n;
        }
    }
}

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
    trace_event(msg);
}

static void signature_hit(unsigned int cpu, void *userdata)
{
    PCMatch *match = userdata;
    PCSignature *s = match->signature;
    if (s->seen) {
        return;
    }
    bool valid = match->complete_in_tb;
    if (!valid) {
        /* Must be done in a vCPU execution callback, not a translation
         * callback: the cross-TB tail may be on a different guest page.
         */
        GByteArray *buf = g_byte_array_sized_new(SIGNATURE_BYTES);
        if (buf) {
            valid = qemu_plugin_read_memory_vaddr(match->guest_address, buf,
                                                  SIGNATURE_BYTES) &&
                    buf->len == SIGNATURE_BYTES &&
                    memcmp(buf->data, s->bytes, SIGNATURE_BYTES) == 0;
            g_byte_array_unref(buf);
        }
    }
    if (!valid || !__sync_bool_compare_and_swap(&s->seen, 0, 1)) {
        return;
    }
    char msg[240];
    snprintf(msg, sizeof(msg),
             "HOMEVIEW_PC_TRACE fingerprint_hit static=0x%" PRIx64
             " guest=0x%" PRIx64 " cpu=%u mode=%s\n",
             s->static_address, match->guest_address, cpu,
             match->complete_in_tb ? "full-tb" : "cross-tb");
    trace_event(msg);
}

/* Compare every available contiguous instruction in the TB. A candidate
 * spanning a boundary is checked against all 48 bytes on its first actual
 * execution; translation by itself is never reported as a hit.
 */
static bool prefix_matches(const struct qemu_plugin_tb *tb, size_t start,
                           size_t words, const PCSignature *s)
{
    for (size_t k = 0; k < words; ++k) {
        const struct qemu_plugin_insn *insn =
            qemu_plugin_tb_get_insn(tb, start + k);
        uint8_t data[4];
        if (qemu_plugin_insn_size(insn) != 4 ||
            qemu_plugin_insn_data(insn, data, 4) != 4 ||
            memcmp(data, s->bytes + k * 4, 4)) {
            return false;
        }
    }
    return true;
}

static void translate(struct qemu_plugin_tb *tb, void *userdata)
{
    (void)userdata;
    size_t total = qemu_plugin_tb_n_insns(tb);
    for (size_t i = 0; i < total; ++i) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        uint64_t addr = qemu_plugin_insn_vaddr(insn);
        for (size_t j = 0; j < count; ++j) {
            if (targets[j].address == addr) {
                qemu_plugin_register_vcpu_insn_exec_cb(
                    insn, hit, QEMU_PLUGIN_CB_NO_REGS, &targets[j]);
            }
        }
        size_t available = total - i;
        size_t words = available < SIGNATURE_WORDS ? available : SIGNATURE_WORDS;
        for (size_t j = 0; j < signature_count; ++j) {
            PCSignature *s = &signatures[j];
            if (s->seen || !prefix_matches(tb, i, words, s)) {
                continue;
            }
            int slot = __sync_add_and_fetch(&candidate_count, 1);
            if (slot > MAX_CANDIDATES) {
                if (__sync_bool_compare_and_swap(&candidate_overflow, 0, 1)) {
                    trace_event("HOMEVIEW_PC_TRACE candidate_budget_exhausted=true no_hit_is_inconclusive=true\n");
                }
                continue;
            }
            PCMatch *m = malloc(sizeof(*m));
            if (!m) {
                trace_event("HOMEVIEW_PC_TRACE candidate_allocation_failed=true no_hit_is_inconclusive=true\n");
                continue;
            }
            /* The callback owns the pointer for the lifetime of its TB;
             * never free it while QEMU may execute that TB again.
             */
            m->signature = s;
            m->guest_address = addr;
            m->complete_in_tb = words == SIGNATURE_WORDS;
            qemu_plugin_register_vcpu_insn_exec_cb(
                insn, signature_hit, QEMU_PLUGIN_CB_NO_REGS, m);
        }
    }
}

static int nibble(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int parse_address(const char *raw, char **end, uint64_t *address)
{
    if (strncmp(raw, "0x", 2)) return -1;
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
    for (int i = 0; i < argc; ++i) {
        char *end = NULL;
        uint64_t addr;
        if (!strncmp(argv[i], "addr=", 5)) {
            if (count == MAX_TARGETS ||
                parse_address(argv[i] + 5, &end, &addr) || *end) return -1;
            for (size_t j = 0; j < count; ++j) {
                if (targets[j].address == addr) return -1;
            }
            targets[count++].address = addr;
        } else if (!strncmp(argv[i], "sig=", 4)) {
            if (signature_count == MAX_SIGNATURES ||
                parse_address(argv[i] + 4, &end, &addr) || *end != ':') return -1;
            const char *hex = end + 1;
            if (strlen(hex) != SIGNATURE_BYTES * 2) return -1;
            PCSignature *s = &signatures[signature_count];
            s->static_address = addr;
            for (size_t k = 0; k < SIGNATURE_BYTES; ++k) {
                int high = nibble(hex[2 * k]);
                int low = nibble(hex[2 * k + 1]);
                if (high < 0 || low < 0) return -1;
                s->bytes[k] = (uint8_t)((high << 4) | low);
            }
            ++signature_count;
        } else {
            return -1;
        }
    }
    if (!count && !signature_count) return -1;
    const char *path = getenv("HOMEVIEW_TCG_PC_TRACE_FILE");
    if (path && *path) {
        trace_fd = open(path, O_CREAT | O_TRUNC | O_WRONLY | O_CLOEXEC, 0600);
        if (trace_fd < 0) {
            return -1;  /* Never silently fall back if an artifact is required. */
        }
    }
    qemu_plugin_register_vcpu_tb_trans_cb(id, translate, NULL);
    char msg[160];
    snprintf(msg, sizeof(msg),
             "HOMEVIEW_PC_TRACE initialized targets=%zu signatures=%zu read_only=true\n",
             count, signature_count);
    trace_event(msg);
    return 0;
}
