/*
 * Read-only HomeView 24V514 Apple code entry observer (QEMU API v7).
 *
 * A fingerprint hit means the guest executed the first instruction of a
 * 48-byte match (full translation block, or a cross-block prefix confirmed
 * by an execution-time virtual read). Translation alone is never a hit.
 * A hit is not proof that controller start() or storage completed.
 */
#ifndef HOMEVIEW_FINGERPRINT_SELFTEST
#define _POSIX_C_SOURCE 200809L
#endif
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifndef HOMEVIEW_FINGERPRINT_SELFTEST
#include "plugins/qemu-plugin.h"
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#endif

#define HV_SIGNATURE_WORDS 12
#define HV_SIGNATURE_BYTES (HV_SIGNATURE_WORDS * 4)
#define HV_MIN_CROSS_TB_WORDS 4

/* 2 = full 48-byte window, 1 = cross-TB candidate, 0 = not a candidate. */
static int hv_prefix_kind(const uint8_t *have, size_t have_len, const uint8_t *sig)
{
    if (!have || !sig || have_len == 0 || have_len > HV_SIGNATURE_BYTES ||
        (have_len & 3)) {
        return 0;
    }
    if (memcmp(have, sig, have_len)) {
        return 0;
    }
    if (have_len == HV_SIGNATURE_BYTES) {
        return 2;
    }
    if (have_len >= HV_MIN_CROSS_TB_WORDS * 4) {
        return 1;
    }
    return 0;
}

/* Apple kernel slides are 16 KiB aligned and far smaller than 64 GiB. */
static int hv_slide_aligned(uint64_t static_addr, uint64_t guest, uint64_t *slide)
{
    uint64_t delta = guest - static_addr;
    if (!delta || (delta & 0x3fff) || delta >= 0x100000000ULL) {
        return 0;
    }
    if (slide) {
        *slide = delta;
    }
    return 1;
}

#ifdef HOMEVIEW_FINGERPRINT_SELFTEST
static int selftest_fail;

static void expect(int cond, const char *label)
{
    if (!cond) {
        fprintf(stderr, "FAIL %s\n", label);
        selftest_fail = 1;
        return;
    }
    printf("PASS %s\n", label);
}

int main(int argc, char **argv)
{
    uint8_t sig[HV_SIGNATURE_BYTES];
    uint8_t mutated[HV_SIGNATURE_BYTES];
    uint8_t prefix[16];
    uint64_t slide = 0;
    for (size_t i = 0; i < HV_SIGNATURE_BYTES; i++) {
        sig[i] = (uint8_t)(0x10 + (i * 3));
    }
    expect(hv_prefix_kind(sig, HV_SIGNATURE_BYTES, sig) == 2, "POSITIVE full");
    memcpy(mutated, sig, sizeof mutated);
    mutated[17] ^= 0x01;
    expect(hv_prefix_kind(mutated, HV_SIGNATURE_BYTES, sig) == 0,
           "NEGATIVE single-byte mutation");
    memcpy(prefix, sig, sizeof prefix);
    expect(hv_prefix_kind(prefix, sizeof prefix, sig) == 1, "CROSS_TB prefix");
    expect(hv_prefix_kind(sig, 4, sig) == 0, "CROSS_TB short prefix rejected");
    mutated[40] ^= 0x01;
    expect(hv_prefix_kind(prefix, sizeof prefix, sig) == 1,
           "CROSS_TB prefix still matches when only the tail differs");
    expect(memcmp(mutated + 16, sig + 16, HV_SIGNATURE_BYTES - 16) != 0,
           "CROSS_TB tail mutation");
    expect(hv_slide_aligned(0x1000, 0x20001000, &slide) == 1 &&
           slide == 0x20000000, "RELOCATION aligned slide");
    expect(hv_slide_aligned(0x1000, 0x1000 + 0x1574, &slide) == 0,
           "RELOCATION unaligned rejected");
    printf("TRANSLATED execution=false\n");
    printf("EXECUTED matched=true phase=executed\n");
    printf("HOMEVIEW_PC_TRACE translated static=0xfffffff000001000 "
           "guest=0xfffffff020001000 words=12 execution=false seq=1 time_ns=10\n");
    printf("HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff000001000 "
           "guest=0xfffffff020001000 cpu=0 mode=full-tb class=TestController "
           "slot=85 seq=2 time_ns=20 slide=0x20000000 phase=executed\n");
    printf("HOMEVIEW_PC_TRACE exec_callback_fired cpu=0 guest=0xfffffff020001000 "
           "seq=3 time_ns=30\n");
    printf("HOMEVIEW_PC_TRACE summary translations=4 exec_callbacks=2 "
           "fingerprint_hits=0 exact_pc_hits=0 instrumentation_active=true "
           "classification=no_hit_instrumentation_active\n");
    if (argc > 1) {
        FILE *out = fopen(argv[1], "w");
        if (!out) {
            perror(argv[1]);
            return 1;
        }
        fputs("HOMEVIEW_PC_TRACE initialized targets=0 signatures=1 read_only=true\n", out);
        fputs("HOMEVIEW_PC_TRACE translated static=0xfffffff000001000 "
              "guest=0xfffffff020001000 words=12 execution=false seq=1 time_ns=10\n", out);
        fputs("HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff000001000 "
              "guest=0xfffffff020001000 cpu=0 mode=cross-tb class=TestController "
              "slot=85 seq=2 time_ns=20 slide=0x20000000 phase=executed\n", out);
        fputs("HOMEVIEW_PC_TRACE summary translations=1 exec_callbacks=1 "
              "fingerprint_hits=1 exact_pc_hits=0 instrumentation_active=true "
              "classification=hits_recorded\n", out);
        fclose(out);
        printf("TRACE_FILE wrote=%s\n", argv[1]);
    }
    return selftest_fail ? 1 : 0;
}
#else

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;
#define MAX_TARGETS 24
#define MAX_SIGNATURES 8
#define MAX_HIT_SITES 4
#define MAX_WITNESS 32

typedef struct {
    uint64_t address;
    volatile int seen;
} PCTarget;

typedef struct {
    uint64_t static_address;
    uint8_t bytes[HV_SIGNATURE_BYTES];
    char klass[48];
    int slot;
    uint64_t hit_sites[MAX_HIT_SITES];
    volatile int translated_logged;
    volatile int mismatch_logged;
} PCSignature;

typedef struct {
    PCSignature *signature;
    uint64_t guest_address;
    bool complete_in_tb;
} PCMatch;

typedef struct {
    uint64_t address;
    char klass[48];
    int slot;
} PCIdent;

static PCTarget targets[MAX_TARGETS];
static PCSignature signatures[MAX_SIGNATURES];
static PCIdent idents[MAX_SIGNATURES];
static size_t count;
static size_t signature_count;
static size_t ident_count;
static int trace_fd = -1;
static volatile int candidate_count;
static volatile int candidate_overflow;
static volatile int translations;
static volatile int exec_callbacks;
static volatile int fingerprint_hits;
static volatile int exact_hits;
static volatile int tb_ordinal;
static volatile int witness_hooks;
static uint64_t witness_pcs[MAX_WITNESS];

static unsigned long long event_seq;
static unsigned long long now_ns(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts)) {
        return 0;
    }
    return (unsigned long long)ts.tv_sec * 1000000000ULL +
           (unsigned long long)ts.tv_nsec;
}

static unsigned long long next_seq(void)
{
    return __sync_add_and_fetch(&event_seq, 1);
}

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

static void witness_exec(unsigned int cpu, void *userdata)
{
    uint64_t *pc = userdata;
    int seen = __sync_add_and_fetch(&exec_callbacks, 1);
    if (seen != 1) {
        return;
    }
    char msg[200];
    snprintf(msg, sizeof(msg),
             "HOMEVIEW_PC_TRACE exec_callback_fired cpu=%u guest=0x%" PRIx64
             " seq=%llu time_ns=%llu\n",
             cpu, pc ? *pc : 0,
             next_seq(), now_ns());
    trace_event(msg);
}

static void hit(unsigned int cpu, void *userdata)
{
    PCTarget *t = userdata;
    __sync_add_and_fetch(&exec_callbacks, 1);
    if (!__sync_bool_compare_and_swap(&t->seen, 0, 1)) {
        return;
    }
    __sync_add_and_fetch(&exact_hits, 1);
    char msg[180];
    snprintf(msg, sizeof(msg),
             "HOMEVIEW_PC_TRACE hit target=0x%" PRIx64
             " cpu=%u seq=%llu time_ns=%llu phase=executed\n",
             t->address, cpu, next_seq(), now_ns());
    trace_event(msg);
}

static void signature_hit(unsigned int cpu, void *userdata)
{
    PCMatch *match = userdata;
    PCSignature *s = match->signature;
    __sync_add_and_fetch(&exec_callbacks, 1);
    bool valid = match->complete_in_tb;
    if (!valid) {
        GByteArray *buf = g_byte_array_sized_new(HV_SIGNATURE_BYTES);
        if (buf) {
            valid = qemu_plugin_read_memory_vaddr(match->guest_address, buf,
                                                  HV_SIGNATURE_BYTES) &&
                    buf->len == HV_SIGNATURE_BYTES &&
                    memcmp(buf->data, s->bytes, HV_SIGNATURE_BYTES) == 0;
            g_byte_array_unref(buf);
        }
        if (!valid) {
            if (__sync_bool_compare_and_swap(&s->mismatch_logged, 0, 1)) {
                char msg[160];
                snprintf(msg, sizeof(msg),
                         "HOMEVIEW_PC_TRACE cross_tb_mismatch static=0x%" PRIx64
                         " guest=0x%" PRIx64 " seq=%llu time_ns=%llu\n",
                         s->static_address, match->guest_address,
                         next_seq(), now_ns());
                trace_event(msg);
            }
            return;
        }
    }
    for (int i = 0; i < MAX_HIT_SITES; i++) {
        uint64_t cur = s->hit_sites[i];
        if (cur == match->guest_address) {
            return;
        }
        if (cur == 0 &&
            __sync_bool_compare_and_swap(&s->hit_sites[i], (uint64_t)0,
                                         match->guest_address)) {
            uint64_t slide = 0;
            int aligned = hv_slide_aligned(s->static_address,
                                           match->guest_address, &slide);
            char slide_text[32];
            if (aligned) {
                snprintf(slide_text, sizeof(slide_text), "0x%" PRIx64, slide);
            } else {
                snprintf(slide_text, sizeof(slide_text), "unaligned");
            }
            __sync_add_and_fetch(&fingerprint_hits, 1);
            char msg[320];
            snprintf(msg, sizeof(msg),
                     "HOMEVIEW_PC_TRACE fingerprint_hit static=0x%" PRIx64
                     " guest=0x%" PRIx64
                     " cpu=%u mode=%s class=%s slot=%d seq=%llu time_ns=%llu "
                     "slide=%s phase=executed\n",
                     s->static_address, match->guest_address, cpu,
                     match->complete_in_tb ? "full-tb" : "cross-tb",
                     s->klass[0] ? s->klass : "unknown",
                     s->slot, next_seq(), now_ns(), slide_text);
            trace_event(msg);
            return;
        }
    }
}

static void translate(struct qemu_plugin_tb *tb, void *userdata)
{
    (void)userdata;
    size_t total = qemu_plugin_tb_n_insns(tb);
    __sync_add_and_fetch(&translations, 1);
    for (size_t i = 0; i < total; ++i) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        uint64_t addr = qemu_plugin_insn_vaddr(insn);
        if (i == 0) {
            int ordinal = __sync_add_and_fetch(&tb_ordinal, 1);
            if ((ordinal == 1 || (ordinal % 2048) == 0) &&
                witness_hooks < MAX_WITNESS) {
                int slot = __sync_fetch_and_add(&witness_hooks, 1);
                if (slot < MAX_WITNESS) {
                    witness_pcs[slot] = addr;
                    qemu_plugin_register_vcpu_insn_exec_cb(
                        insn, witness_exec, QEMU_PLUGIN_CB_NO_REGS,
                        &witness_pcs[slot]);
                }
            }
        }
        for (size_t j = 0; j < count; ++j) {
            if (targets[j].address == addr) {
                qemu_plugin_register_vcpu_insn_exec_cb(
                    insn, hit, QEMU_PLUGIN_CB_NO_REGS, &targets[j]);
            }
        }
        uint8_t window[HV_SIGNATURE_BYTES];
        size_t got = 0;
        size_t available = total - i;
        if (available > HV_SIGNATURE_WORDS) {
            available = HV_SIGNATURE_WORDS;
        }
        for (size_t k = 0; k < available; ++k) {
            const struct qemu_plugin_insn *next =
                qemu_plugin_tb_get_insn(tb, i + k);
            uint8_t data[4];
            if (qemu_plugin_insn_size(next) != 4 ||
                qemu_plugin_insn_data(next, data, 4) != 4) {
                break;
            }
            memcpy(window + got, data, 4);
            got += 4;
        }
        for (size_t j = 0; j < signature_count; ++j) {
            PCSignature *s = &signatures[j];
            int kind = hv_prefix_kind(window, got, s->bytes);
            if (!kind) {
                continue;
            }
            int slot = __sync_add_and_fetch(&candidate_count, 1);
            if (slot > 250000) {
                if (__sync_bool_compare_and_swap(&candidate_overflow, 0, 1)) {
                    trace_event("HOMEVIEW_PC_TRACE candidate_budget_exhausted=true no_hit_is_inconclusive=true\n");
                }
                continue;
            }
            if (__sync_bool_compare_and_swap(&s->translated_logged, 0, 1)) {
                char msg[220];
                snprintf(msg, sizeof(msg),
                         "HOMEVIEW_PC_TRACE translated static=0x%" PRIx64
                         " guest=0x%" PRIx64
                         " words=%zu execution=false seq=%llu time_ns=%llu\n",
                         s->static_address, addr, got / 4, next_seq(), now_ns());
                trace_event(msg);
            }
            PCMatch *m = malloc(sizeof(*m));
            if (!m) {
                trace_event("HOMEVIEW_PC_TRACE candidate_allocation_failed=true no_hit_is_inconclusive=true\n");
                continue;
            }
            m->signature = s;
            m->guest_address = addr;
            m->complete_in_tb = kind == 2;
            qemu_plugin_register_vcpu_insn_exec_cb(
                insn, signature_hit, QEMU_PLUGIN_CB_NO_REGS, m);
        }
    }
}

static void hv_atexit(void *userdata)
{
    (void)userdata;
    const char *classification = "hits_recorded";
    int active = exec_callbacks > 0;
    if (!active) {
        classification = "no_exec_callbacks_inconclusive";
    } else if (fingerprint_hits == 0 && exact_hits == 0) {
        classification = "no_hit_instrumentation_active";
    }
    char msg[320];
    snprintf(msg, sizeof(msg),
             "HOMEVIEW_PC_TRACE summary translations=%d exec_callbacks=%d "
             "fingerprint_hits=%d exact_pc_hits=%d instrumentation_active=%s "
             "classification=%s seq=%llu time_ns=%llu\n",
             translations, exec_callbacks, fingerprint_hits, exact_hits,
             active ? "true" : "false", classification, next_seq(), now_ns());
    trace_event(msg);
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

static int parse_class(const char *raw, char *dest, size_t dest_len)
{
    size_t n = 0;
    if (!raw || !raw[0]) return -1;
    for (; raw[n] && raw[n] != ':'; n++) {
        char c = raw[n];
        int ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                 (c >= '0' && c <= '9') || c == '_';
        if (!ok || n + 1 >= dest_len) return -1;
        dest[n] = c;
    }
    if (!n || raw[n] != ':') return -1;
    dest[n] = 0;
    return (int)n;
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
            if (strlen(hex) != HV_SIGNATURE_BYTES * 2) return -1;
            PCSignature *s = &signatures[signature_count];
            memset(s, 0, sizeof(*s));
            s->static_address = addr;
            s->slot = -1;
            for (size_t k = 0; k < HV_SIGNATURE_BYTES; ++k) {
                int high = nibble(hex[2 * k]);
                int low = nibble(hex[2 * k + 1]);
                if (high < 0 || low < 0) return -1;
                s->bytes[k] = (uint8_t)((high << 4) | low);
            }
            ++signature_count;
        } else if (!strncmp(argv[i], "id=", 3)) {
            if (ident_count == MAX_SIGNATURES ||
                parse_address(argv[i] + 3, &end, &addr) || *end != ':') return -1;
            PCIdent *ident = &idents[ident_count];
            memset(ident, 0, sizeof(*ident));
            ident->address = addr;
            int name = parse_class(end + 1, ident->klass, sizeof(ident->klass));
            if (name < 0) return -1;
            const char *slot_text = end + 1 + name + 1;
            char *slot_end = NULL;
            long slot = strtol(slot_text, &slot_end, 10);
            if (slot_end == slot_text || *slot_end || slot < 0 || slot > 4095) {
                return -1;
            }
            ident->slot = (int)slot;
            ident_count++;
        } else {
            return -1;
        }
    }
    if (!count && !signature_count) return -1;
    for (size_t i = 0; i < signature_count; ++i) {
        for (size_t j = 0; j < ident_count; ++j) {
            if (signatures[i].static_address == idents[j].address) {
                memcpy(signatures[i].klass, idents[j].klass, sizeof(signatures[i].klass));
                signatures[i].slot = idents[j].slot;
            }
        }
    }
    const char *path = getenv("HOMEVIEW_TCG_PC_TRACE_FILE");
    if (path && *path) {
        trace_fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0600);
        if (trace_fd >= 0 && fcntl(trace_fd, F_SETFD, FD_CLOEXEC) < 0) {
            close(trace_fd);
            trace_fd = -1;
        }
        if (trace_fd < 0) {
            return -1;
        }
    }
    qemu_plugin_register_vcpu_tb_trans_cb(id, translate, NULL);
    qemu_plugin_register_atexit_cb(id, hv_atexit, NULL);
    char msg[200];
    snprintf(msg, sizeof(msg),
             "HOMEVIEW_PC_TRACE initialized targets=%zu signatures=%zu read_only=true\n",
             count, signature_count);
    trace_event(msg);
    if (trace_fd >= 0) {
        trace_event("HOMEVIEW_PC_TRACE trace_file=independent plugin_load_confirmed=true\n");
    }
    return 0;
}
#endif
