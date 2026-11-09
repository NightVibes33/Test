#pragma once
#include <stdint.h>
int fp_device_decrypt_pages(const char *installed_binary_path,
                            uint64_t slice_offset, uint32_t cryptoff, uint32_t cryptsize,
                            uint32_t cputype, uint32_t cpusubtype,
                            uint8_t *result, uint32_t capacity,
                            int *os_error, uint32_t *successful_pages);
#import "worse_query.h"
