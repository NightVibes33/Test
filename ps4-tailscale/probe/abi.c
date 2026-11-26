/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ordinary libc calls only. Header sizes are compile-time, not measured
 * kernel layouts. No raw syscalls, executable mapping, offsets, or patches.
 */
#include <stdio.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <pthread.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/mman.h>
#ifdef __FreeBSD__
#include <sys/event.h>
#include <sys/ucontext.h>
#endif

static int failures;
static void result(const char *name,int ok){
 printf("%s: %s\n",name,ok?"PASS":"FAIL");
 if(!ok) failures++;
}
static pthread_key_t key;
static void *thread_test(void *arg){
 if(pthread_setspecific(key,arg)!=0) return NULL;
 return pthread_getspecific(key);
}
int main(void){
 printf("PS4 ABI capability probe v2\n");
 printf("page size=%ld stat header size=%zu sockaddr size=%zu\n",
  sysconf(_SC_PAGESIZE),sizeof(struct stat),sizeof(struct sockaddr));
#ifdef __FreeBSD__
 printf("SDK header kevent=%zu ucontext=%zu mcontext_offset=%zu\n",
  sizeof(struct kevent),sizeof(ucontext_t),offsetof(ucontext_t,uc_mcontext));
 int q=kqueue(), p[2];
 if(q>=0 && pipe(p)==0){
  struct kevent change,event;
  struct timespec timeout={1,0};
  EV_SET(&change,p[0],EVFILT_READ,EV_ADD|EV_ENABLE,0,0,NULL);
  int registered=kevent(q,&change,1,NULL,0,&timeout);
  int written=(write(p[1],"x",1)==1);
  int got=kevent(q,NULL,0,&event,1,&timeout);
  result("kqueue pipe readiness",registered==0&&written&&got==1&&event.ident==(uintptr_t)p[0]);
  close(p[0]);close(p[1]);
 }else result("kqueue pipe readiness",0);
 if(q>=0)close(q);
#else
 puts("kqueue and ucontext SDK check: skipped on non-FreeBSD host");
#endif
 struct timespec before,after;
 int c1=clock_gettime(CLOCK_MONOTONIC,&before);
 struct timespec delay={0,1000000};
 nanosleep(&delay,NULL);
 int c2=clock_gettime(CLOCK_MONOTONIC,&after);
 result("monotonic clock",c1==0&&c2==0&&(after.tv_sec>before.tv_sec||
    (after.tv_sec==before.tv_sec&&after.tv_nsec>=before.tv_nsec)));
 int token=42;
 pthread_t t;
 void *ret=NULL;
 int k=pthread_key_create(&key,NULL);
 int created=k==0?pthread_create(&t,NULL,thread_test,&token):-1;
 int joined=created==0?pthread_join(t,&ret):-1;
 result("pthread and TLS",k==0&&created==0&&joined==0&&ret==&token);
 if(k==0)pthread_key_delete(key);
 int fd=open("/dev/urandom",O_RDONLY);
 unsigned char random_bytes[32];
 if(fd>=0){result("entropy device read",read(fd,random_bytes,sizeof(random_bytes))==(ssize_t)sizeof(random_bytes));close(fd);}
 else result("entropy device read",0);
 long pagesize=sysconf(_SC_PAGESIZE);
 if(pagesize>0){
  void *m=mmap(NULL,(size_t)pagesize,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
  if(m!=MAP_FAILED){memset(m,0x2a,(size_t)pagesize);result("anonymous RW memory",((unsigned char*)m)[0]==0x2a);munmap(m,(size_t)pagesize);}
  else result("anonymous RW memory",0);
 }else result("anonymous RW memory",0);
 printf("failures=%d; no configuration changed\n",failures);
 fflush(stdout);
 return failures?1:0;
}
