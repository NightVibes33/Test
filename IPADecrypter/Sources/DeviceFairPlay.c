// Independent FairPlayed-style iOS FairPlay VM mapping backend.
// The mapped executable MUST be inside the installed app bundle with valid SC_Info.
// This does not read or export credentials. Licensed apps only.
#include "DeviceFairPlay.h"
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

typedef int (*fp_remap_fn)(void *, size_t, uint32_t, uint32_t, uint32_t);

static int fp_remap(void *address, size_t length, uint32_t cryptid,
                    uint32_t cpu, uint32_t subtype) {
    fp_remap_fn symbol = (fp_remap_fn)dlsym(RTLD_DEFAULT, "mremap_encrypted");
    if (symbol) return symbol(address, length, cryptid, cpu, subtype);
#if defined(__arm64__)
    register uint64_t x0 __asm__("x0") = (uint64_t)address;
    register uint64_t x1 __asm__("x1") = (uint64_t)length;
    register uint64_t x2 __asm__("x2") = cryptid;
    register uint64_t x3 __asm__("x3") = cpu;
    register uint64_t x4 __asm__("x4") = subtype;
    register uint64_t x16 __asm__("x16") = 489;
    uint64_t error = 0;
    __asm__ volatile("svc #0x80\n\tcset %[error], cs\n\t"
                     : "+r"(x0), "+r"(x1), [error]"=r"(error)
                     : "r"(x2), "r"(x3), "r"(x4), "r"(x16)
                     : "cc", "memory");
    if (error) { errno = (int)x0; return -1; }
    return (int)x0;
#else
    errno = ENOTSUP;
    return -1;
#endif
}

static void fp_register_signature(int fd, uint64_t slice_offset) {
#ifdef F_ADDFILESIGS_RETURN
    struct mach_header_64 h;
    if (pread(fd, &h, sizeof(h), (off_t)slice_offset) != sizeof(h)) return;
    if (h.magic != MH_MAGIC_64 || h.ncmds > 1000 || h.sizeofcmds > 16000000) return;
    uint8_t *commands = malloc(h.sizeofcmds);
    if (!commands) return;
    if (pread(fd, commands, h.sizeofcmds, (off_t)(slice_offset + sizeof(h))) != h.sizeofcmds) {
        free(commands); return;
    }
    size_t pos = 0;
    for (uint32_t i = 0; i < h.ncmds && pos + 8 <= h.sizeofcmds; i++) {
        struct load_command lc;
        memcpy(&lc, commands + pos, sizeof(lc));
        if (lc.cmdsize < sizeof(lc) || lc.cmdsize > h.sizeofcmds - pos) break;
        if (lc.cmd == LC_CODE_SIGNATURE && lc.cmdsize >= sizeof(struct linkedit_data_command)) {
            struct linkedit_data_command sig;
            memcpy(&sig, commands + pos, sizeof(sig));
            fsignatures_t f = {
                .fs_file_start = (off_t)slice_offset,
                .fs_blob_start = (void *)(uintptr_t)sig.dataoff,
                .fs_blob_size = sig.datasize
            };
            (void)fcntl(fd, F_ADDFILESIGS_RETURN, &f);
            break;
        }
        pos += lc.cmdsize;
    }
    free(commands);
#else
    (void)fd; (void)slice_offset;
#endif
}

int fp_device_decrypt_pages(const char *installed_binary_path,
                            uint64_t slice_offset, uint32_t cryptoff, uint32_t cryptsize,
                            uint32_t cputype, uint32_t cpusubtype,
                            uint8_t *result, uint32_t capacity,
                            int *os_error, uint32_t *successful_pages) {
    if (os_error) *os_error = 0;
    if (successful_pages) *successful_pages = 0;
    if (!installed_binary_path || !result || !cryptsize || capacity < cryptsize) return -1;
    uint32_t page = (uint32_t)getpagesize();
    if (!page || (slice_offset % page) || (cryptoff % page) ||
        (cryptsize % page) || cryptsize > 0x10000000) return -2;
    int fd = open(installed_binary_path, O_RDONLY);
    if (fd < 0) { if (os_error) *os_error = errno; return -3; }
    fp_register_signature(fd, slice_offset);
    size_t length = ((uint64_t)cryptoff + cryptsize + page - 1) & ~((uint64_t)page - 1);
    void *mem = mmap(NULL, length, PROT_READ, MAP_PRIVATE, fd, (off_t)slice_offset);
    if (mem == MAP_FAILED) {
        if (os_error) *os_error = errno;
        close(fd);
        return -4;
    }
    uint8_t *at = (uint8_t *)mem + cryptoff;
    errno = 0;
    // Model-cryptid 2 lets iOS perform FairPlay work without PROT_EXEC.
    int remap = fp_remap(at, cryptsize, 2, cputype, cpusubtype);
    if (remap != 0) {
        if (os_error) *os_error = errno;
        munmap(mem, length); close(fd);
        return -5;
    }
    uint32_t good = 0;
    for (uint32_t offset = 0; offset < cryptsize; offset += page) {
        vm_size_t nread = 0;
        kern_return_t kr = vm_read_overwrite(mach_task_self(),
                                              (vm_address_t)(at + offset), page,
                                              (vm_address_t)(result + offset), &nread);
        if (kr != KERN_SUCCESS || nread != page) {
            if (os_error) *os_error = (int)kr;
            munmap(mem, length); close(fd);
            return -6;
        }
        good++;
    }
    if (successful_pages) *successful_pages = good;
    // Reject obvious unchanged pages (so a syscall success isn't itself "decrypted").
    uint8_t *original = malloc(cryptsize);
    int changed = 0;
    if (original) {
        if (pread(fd, original, cryptsize, (off_t)(slice_offset + cryptoff)) == cryptsize)
            changed = memcmp(original, result, cryptsize) != 0;
        free(original);
    }
    munmap(mem, length); close(fd);
    return changed ? 0 : -7;
}
