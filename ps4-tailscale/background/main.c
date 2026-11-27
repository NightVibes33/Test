/* Standalone experimental GoldHEN payload. No foreground UI, no kernel patches
 * in this source. SDK CRT and loader compatibility must be proven on hardware. */
#include "../homebrew/runtime_loader.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
extern const unsigned char image[],image_end[];
__asm__(".section .rodata\n.balign 16\n.global image\nimage:\n.incbin \"" RUNTIME_IMAGE "\"\n.global image_end\nimage_end:\n.text\n");
int main(void){
 const char *dir="/data/ps4-tailscale";
 if(mkdir(dir,0700)&&errno!=EEXIST)return 2;
 if(access(dir,W_OK))return 2;
 RuntimeImage im;int rc=runtime_map(image,(size_t)(image_end-image),&im);
 printf("PS4TS_BACKGROUND_MAP %d\n",rc);if(rc)return 3;
 static char *argv[]={"TailScale",NULL};
 static char *envp[]={"PS4TS_DATA=/data/ps4-tailscale","HOME=/data/ps4-tailscale","TMPDIR=/data/ps4-tailscale","GOMAXPROCS=2","GODEBUG=asyncpreemptoff=1",NULL};
 puts("PS4TS_ENTER_GO_EXPERIMENTAL");return runtime_enter(&im,argv,envp);
}
