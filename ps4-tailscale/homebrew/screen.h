/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef SCREEN_H
#define SCREEN_H
#include <stddef.h>
#define QR_MAX 121
typedef struct {
 char state[40],ip[48];
 int ready,n;
 unsigned char cells[QR_MAX][QR_MAX];
} Screen;
int screen_parse(Screen *out,const char *text);
#endif
