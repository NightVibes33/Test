/* Experimental standalone user-mode launcher. No SDK CRT or kernel patching. */
#include "freestanding.h"
#include "../homebrew/runtime_loader.h"
extern const unsigned char image[],image_end[];
__asm__(".section .rodata\n.balign 16\n.global image\n.hidden image\nimage:\n.incbin \"" RUNTIME_IMAGE "\"\n.global image_end\n.hidden image_end\nimage_end:\n.text\n");
static void logline(const char *s){size_t n=0;while(s[n])n++;ps4_call(4,2,(long)s,n,0,0,0);}
int _start(void){
 static const char dir[]="/data/ps4-tailscale";
 long rc=ps4_call(136,(long)dir,0700,0,0,0,0);
 if(rc<0&&rc!=-17){logline("PS4TS_STORAGE_FAIL\n");return 2;}
 RuntimeImage im;int mapped=runtime_map(image,(size_t)(image_end-image),&im);
 if(mapped){logline("PS4TS_BACKGROUND_MAP_FAIL\n");return 3;}
 logline("PS4TS_BACKGROUND_MAP_OK\n");
#ifdef MAP_PROBE
 runtime_unmap(&im);return 0;
#else
 // Explicit volatile stores prevent clang from generating a relocated pointer table.
 char *volatile argv[2], *volatile envp[6];
 argv[0]="TailScale";argv[1]=0;
 envp[0]="PS4TS_DATA=/data/ps4-tailscale";envp[1]="HOME=/data/ps4-tailscale";
 envp[2]="TMPDIR=/data/ps4-tailscale";envp[3]="GOMAXPROCS=2";envp[4]="GODEBUG=asyncpreemptoff=1";envp[5]=0;
 logline("PS4TS_ENTER_GO_EXPERIMENTAL\n");return runtime_enter(&im,(char *const*)argv,(char *const*)envp);
#endif
}
