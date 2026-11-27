/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RUNTIME_LOADER_H
#define RUNTIME_LOADER_H
#include <stdint.h>
#include <stddef.h>
typedef struct {
 void *base;
 size_t size;
 uintptr_t entry;
} RuntimeImage;
int runtime_map(const void *bytes,size_t size,RuntimeImage *out);
void runtime_unmap(RuntimeImage *image);
int runtime_enter(const RuntimeImage *image,char *const argv[],char *const envp[]);
#endif
