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
 char *argv[]={"TailScale",0};
 char *envp[]={"PS4TS_DATA=/data/ps4-tailscale","HOME=/data/ps4-tailscale","TMPDIR=/data/ps4-tailscale","GOMAXPROCS=2","GODEBUG=asyncpreemptoff=1",0};
 logline("PS4TS_ENTER_GO_EXPERIMENTAL\n");return runtime_enter(&im,argv,envp);
#endif
}
