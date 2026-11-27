/* SPDX-License-Identifier: GPL-3.0-or-later
 * User-mode mapper for internally linked Go PIE. No kernel offsets, permission
 * overrides, or jailbreak APIs. Refuse anything except bounded RELATIVE relocs.
 */
#include "runtime_loader.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#ifdef __FreeBSD__
#include <orbis/libkernel.h>
#endif
typedef struct { unsigned char ident[16]; uint16_t type,machine; uint32_t version; uint64_t entry,phoff,shoff; uint32_t flags; uint16_t ehsize,phentsize,phnum,shentsize,shnum,shstr; } Ehdr;
typedef struct { uint32_t type,flags; uint64_t offset,vaddr,paddr,filesz,memsz,align; } Phdr;
typedef struct { int64_t tag; uint64_t value; } Dyn;
typedef struct { uint64_t offset,info; int64_t addend; } Rela;
_Static_assert(sizeof(Ehdr)==64 && sizeof(Phdr)==56 && sizeof(Dyn)==16 && sizeof(Rela)==24,"ELF layout");
enum { PT_LOAD=1, PT_DYNAMIC=2, PF_X=1, PF_W=2, PF_R=4 };
enum { DT_NULL=0,DT_NEEDED=1,DT_RELA=7,DT_RELASZ=8,DT_RELAENT=9,DT_REL=17,DT_RELSZ=18,DT_JMPREL=23,DT_PLTRELSZ=2,DT_RELR=36,DT_RELRSZ=35,DT_TEXTREL=22 };
#define IMAGE_LIMIT (128UL*1024*1024)
static int bounded(uint64_t off,uint64_t n,uint64_t total){return off<=total&&n<=total-off;}
static size_t page_size(void){
#ifdef __FreeBSD__
 return 0x4000;
#else
 return (size_t)sysconf(_SC_PAGESIZE);
#endif
}
static uintptr_t down(uintptr_t n,size_t p){return n&~(p-1);}
static uintptr_t up(uintptr_t n,size_t p){return (n+p-1)&~(p-1);}
static void *allocate(size_t n){
#ifdef __FreeBSD__
 void *p=0;return sceKernelMmap(0,n,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0,&p)<0?NULL:p;
#else
 void *p=mmap(0,n,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);return p==MAP_FAILED?NULL:p;
#endif
}
static int protect(void *p,size_t n,int flags){
#ifdef __FreeBSD__
 return sceKernelMprotect(p,n,flags);
#else
 return mprotect(p,n,flags);
#endif
}
static void release(void *p,size_t n){
#ifdef __FreeBSD__
 sceKernelMunmap(p,n);
#else
 munmap(p,n);
#endif
}
static int within_segment(const Phdr *h,unsigned count,uint64_t a,uint64_t n,unsigned flags){
 for(unsigned i=0;i<count;i++)if(h[i].type==PT_LOAD&&(h[i].flags&flags)==flags&&a>=h[i].vaddr&&bounded(a-h[i].vaddr,n,h[i].memsz))return 1;
 return 0;
}
int runtime_map(const void *bytes,size_t size,RuntimeImage *out){
 memset(out,0,sizeof(*out));
 if(!bytes||size<sizeof(Ehdr)||size>IMAGE_LIMIT)return -1;
 Ehdr e;memcpy(&e,bytes,sizeof(e));
 if(memcmp(e.ident,"\177ELF\2\1\1",7)||e.ident[7]!=9||e.type!=3||e.machine!=62||e.version!=1||e.phentsize!=sizeof(Phdr)||!e.phnum||e.phnum>64||!bounded(e.phoff,(uint64_t)e.phnum*sizeof(Phdr),size))return -2;
 Phdr h[64];memcpy(h,(const char*)bytes+e.phoff,e.phnum*sizeof(Phdr));
 uint64_t lo=UINT64_MAX,hi=0,segment_end=0;int dynindex=-1;size_t pg=page_size();
 if(!pg||(pg&(pg-1)))return -3;
 for(unsigned i=0;i<e.phnum;i++){
  Phdr *p=&h[i];
  if(p->type==PT_DYNAMIC){if(dynindex>=0)return -4;dynindex=(int)i;}
  if(p->type!=PT_LOAD)continue;
  if(p->filesz>p->memsz||!bounded(p->offset,p->filesz,size)||!bounded(p->vaddr,p->memsz,UINT64_MAX-pg)||(p->flags&(PF_W|PF_X))==(PF_W|PF_X))return -4;
  if(!p->memsz)continue;
  if(p->vaddr<lo)lo=p->vaddr;
  if(p->vaddr+p->memsz>hi)hi=p->vaddr+p->memsz;
 }
 if(lo>=hi||dynindex<0||!within_segment(h,e.phnum,e.entry,1,PF_X))return -5;
 segment_end=hi;lo=down(lo,pg);hi=up(hi,pg);if(hi-lo>IMAGE_LIMIT)return -5;
 size_t span=(size_t)(hi-lo);
 unsigned char *base=allocate(span);if(!base)return -6;
 unsigned char *perms=calloc(span/pg,1);if(!perms){release(base,span);return -6;}
 int rc=-7;
 for(unsigned i=0;i<e.phnum;i++){
  Phdr *p=&h[i];if(p->type!=PT_LOAD||!p->memsz)continue;
  memcpy(base+(p->vaddr-lo),(const char*)bytes+p->offset,p->filesz);
  unsigned char flags=(unsigned char)(p->flags&7);
  for(uint64_t v=down(p->vaddr,pg);v<up(p->vaddr+p->memsz,pg);v+=pg){
   unsigned char *q=&perms[(v-lo)/pg];*q|=flags;
   if((*q&(PF_W|PF_X))==(PF_W|PF_X))goto fail;
  }
 }
 Phdr *dh=&h[dynindex];
 if(!within_segment(h,e.phnum,dh->vaddr,dh->memsz,PF_R)||dh->memsz%sizeof(Dyn))goto fail;
 uint64_t rela=0,relasz=0,relaent=0;int ended=0;
 for(uint64_t j=0;j<dh->memsz/sizeof(Dyn);j++){
  Dyn v;memcpy(&v,base+dh->vaddr-lo+j*sizeof(v),sizeof(v));
  if(v.tag==DT_NULL){ended=1;break;}
  if(v.tag==DT_NEEDED||v.tag==DT_REL||v.tag==DT_RELSZ||v.tag==DT_JMPREL||v.tag==DT_PLTRELSZ||v.tag==DT_RELR||v.tag==DT_RELRSZ||v.tag==DT_TEXTREL)goto fail;
  if(v.tag==DT_RELA)rela=v.value;
  if(v.tag==DT_RELASZ)relasz=v.value;
  if(v.tag==DT_RELAENT)relaent=v.value;
 }
 if(!ended||!rela||!relasz||relaent!=sizeof(Rela)||relasz%sizeof(Rela)||!within_segment(h,e.phnum,rela,relasz,PF_R))goto fail;
 for(uint64_t j=0;j<relasz/sizeof(Rela);j++){
  Rela v;memcpy(&v,base+rela-lo+j*sizeof(v),sizeof(v));
  if(v.info!=8||!within_segment(h,e.phnum,v.offset,8,PF_W)||v.addend<0||(uint64_t)v.addend<lo||(uint64_t)v.addend>segment_end)goto fail;
  uintptr_t value=(uintptr_t)base+((uint64_t)v.addend-lo);
  memcpy(base+v.offset-lo,&value,sizeof(value));
 }
 // Apply actual page permissions. No RWX and no fallback if RX is denied.
 rc=-8;
 for(size_t i=0;i<span/pg;){
  size_t j=i+1;while(j<span/pg&&perms[j]==perms[i])j++;
  int prot=0;if(perms[i]&PF_R)prot|=PROT_READ;if(perms[i]&PF_W)prot|=PROT_WRITE;if(perms[i]&PF_X)prot|=PROT_EXEC;
  if(protect(base+i*pg,(j-i)*pg,prot)!=0)goto fail;
  i=j;
 }
 free(perms);out->base=base;out->size=span;out->entry=(uintptr_t)base+e.entry-lo;return 0;
fail:free(perms);release(base,span);return rc;
}
void runtime_unmap(RuntimeImage *im){if(im->base)release(im->base,im->size);memset(im,0,sizeof(*im));}
#ifdef __FreeBSD__
extern void runtime_jump(uintptr_t entry,uintptr_t *args,void *stack) __attribute__((noreturn));
__asm__(".text\n.global runtime_jump\nruntime_jump:\nmov %rdi,%rax\nmov %rsi,%rdi\nmov %rdx,%rsp\nxor %ebp,%ebp\njmp *%rax\n");
int runtime_enter(const RuntimeImage *im,char *const argv[],char *const envp[]){
 size_t argc=0,envc=0;while(argv[argc]){if(++argc>32)return -1;}while(envp[envc]){if(++envc>32)return -1;}
 size_t size=1024*1024,pg=page_size();unsigned char *stack=allocate(size);
 if(!stack)return -2;
 if(protect(stack,pg,PROT_NONE)!=0){release(stack,size);return -3;}
 uintptr_t *sp=(uintptr_t*)down((uintptr_t)(stack+size)-(argc+envc+7)*sizeof(uintptr_t),16);
 uintptr_t *p=sp;*p++=argc;for(size_t i=0;i<argc;i++)*p++=(uintptr_t)argv[i];*p++=0;
 for(size_t i=0;i<envc;i++)*p++=(uintptr_t)envp[i];*p++=0;*p++=6;*p++=pg;*p++=0;*p++=0;
 runtime_jump(im->entry,sp,sp);
}
#else
int runtime_enter(const RuntimeImage *im,char *const argv[],char *const envp[]){(void)im;(void)argv;(void)envp;return -99;}
#endif
