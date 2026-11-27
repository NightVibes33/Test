#pragma once
#include <stdint.h>
typedef void (*NativeText)(int,int,int,uint32_t,const char*);
typedef void (*NativeRect)(int,int,int,int,uint32_t);
void native_init(void);
void native_tick(int daemon_available);
void native_draw(NativeText text,NativeRect rect);
int native_page(void);

int native_show_qr(void);
