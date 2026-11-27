#pragma once
#include <stdint.h>
#include <stddef.h>
#define PROT_NONE 0
#define PROT_READ 1
#define PROT_WRITE 2
#define PROT_EXEC 4
#define MAP_PRIVATE 2
#define MAP_ANONYMOUS 0x1000
#define MAP_FAILED ((void*)-1)
static inline long ps4_call(long n,long a,long b,long c,long d,long e,long f){
 register long r10 __asm__("r10")=d,r8 __asm__("r8")=e,r9 __asm__("r9")=f;
 __asm__ volatile("syscall; jnc 1f; neg %%rax; 1:" : "+a"(n) : "D"(a),"S"(b),"d"(c),"r"(r10),"r"(r8),"r"(r9) : "rcx","r11","memory","cc");return n;
}
static inline void *mmap(void *p,size_t n,int prot,int flags,int fd,long off){
 long r=ps4_call(477,(long)p,n,prot,flags,fd,off);return r<0?MAP_FAILED:(void*)r;
}
static inline int mprotect(void *p,size_t n,int prot){return (int)ps4_call(74,(long)p,n,prot,0,0,0);}
static inline int munmap(void *p,size_t n){return (int)ps4_call(73,(long)p,n,0,0,0,0);}
void *memcpy(void*,const void*,size_t);
void *memset(void*,int,size_t);
int memcmp(const void*,const void*,size_t);
void *calloc(size_t,size_t);
void free(void*);
