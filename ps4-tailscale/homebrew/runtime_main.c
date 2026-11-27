/* SPDX-License-Identifier: GPL-3.0-or-later
 * Experimental foreground runtime launcher. Mapping tests do not enter Go.
 * Running on 14.02 needs a verified syscall ABI and actual hardware testing.
 */
#include "runtime_loader.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <sys/stat.h>
#include <orbis/libkernel.h>
extern const unsigned char runtime_image[],runtime_image_end[];
extern int frontend_main(void);
#ifndef RUNTIME_IMAGE
#error RUNTIME_IMAGE required
#endif
__asm__(".section .rodata\n.balign 16\n.global runtime_image\nruntime_image:\n.incbin \"" RUNTIME_IMAGE "\"\n.global runtime_image_end\nruntime_image_end:\n.text\n");
#if defined(RUNTIME_DAEMON) && !defined(RUNTIME_MAP_ONLY)
static void *ui(void *unused){(void)unused;frontend_main();return NULL;}
#endif
int main(void){
 setvbuf(stdout,NULL,_IONBF,0);
 RuntimeImage im;
 int rc=runtime_map(runtime_image,(size_t)(runtime_image_end-runtime_image),&im);
 printf("PS4TS_RUNTIME_MAP_RESULT %d\n",rc);
 if(rc)return 1;
 puts("PS4TS_RUNTIME_MAP_OK");
#ifdef RUNTIME_MAP_ONLY
 runtime_unmap(&im);
 return frontend_main();
#else
#ifdef RUNTIME_DAEMON
 // No escape from the application sandbox. Refuse if storage is unavailable.
 const char *state="/data/ps4-tailscale";
 if(mkdir(state,0700)!=0&&access(state,W_OK)!=0){puts("PS4TS_STATE_UNAVAILABLE");runtime_unmap(&im);return 2;}
 // UI uses its own C TLS; prevent delivery of Go process-wide signals there.
 sigset_t all,old;sigfillset(&all);
 if(pthread_sigmask(SIG_SETMASK,&all,&old)!=0){runtime_unmap(&im);return 3;}
 pthread_t t;int err=pthread_create(&t,NULL,ui,NULL);
 pthread_sigmask(SIG_SETMASK,&old,NULL);
 if(err){printf("PS4TS_UI_THREAD_FAIL %d\n",err);runtime_unmap(&im);return 3;}
 static char *argv[]={"ps4-tailscale",NULL};
 static char *envp[]={"PS4TS_DATA=/data/ps4-tailscale","HOME=/data/ps4-tailscale","TMPDIR=/data/ps4-tailscale","GOMAXPROCS=2","GODEBUG=asyncpreemptoff=1",NULL};
#else
 static char *argv[]={"ps4-runtime-probe",NULL};
 static char *envp[]={"GOMAXPROCS=2","GODEBUG=asyncpreemptoff=1",NULL};
#endif
 puts("PS4TS_ENTER_GO_EXPERIMENTAL");
 rc=runtime_enter(&im,argv,envp);printf("PS4TS_ENTER_FAIL %d\n",rc);runtime_unmap(&im);return 4;
#endif
}
