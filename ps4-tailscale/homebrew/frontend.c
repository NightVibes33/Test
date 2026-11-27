/* SPDX-License-Identifier: GPL-3.0-or-later
 * Normal OpenOrbis application. No kernel access or network modifications.
 * Live mode reads a local daemon. Fixture mode is ONLY an emulator UI test.
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <orbis/libkernel.h>
#include <orbis/VideoOut.h>
#include "screen.h"
#include "generated.h"

#define W 1280
#define H 720
#define LIMIT 19000
static uint32_t *pixels;
static void rect(int x,int y,int w,int h,uint32_t color){
 if(x<0||y<0||x+w>W||y+h>H)return;
 for(int j=y;j<y+h;j++)for(int i=x;i<x+w;i++)pixels[j*W+i]=color;
}
static void text(int x,int y,int scale,uint32_t color,const char *s){
 for(;*s;s++,x+=9*scale){
  unsigned c=(unsigned char)*s;if(c<32||c>126)c='?';
  const unsigned char *g=font[c-32];
  for(int j=0;j<12;j++)for(int i=0;i<8;i++)if(g[j]&(1<<(7-i)))rect(x+i*scale,y+j*scale,scale,scale,color);
 }
}
static int read_live(Screen *s){
 char buf[LIMIT];size_t n=0;int fd=socket(AF_INET,SOCK_STREAM,0);
 if(fd<0)return 0;
 int flags=fcntl(fd,F_GETFL,0);
 if(flags<0||fcntl(fd,F_SETFL,flags|O_NONBLOCK)<0){close(fd);return 0;}
 struct sockaddr_in a;memset(&a,0,sizeof(a));a.sin_family=AF_INET;a.sin_port=htons(8090);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
 int rc=connect(fd,(struct sockaddr *)&a,sizeof(a));
 if(rc<0&&errno!=EINPROGRESS){close(fd);return 0;}
 struct pollfd p={fd,POLLOUT,0};
 if(rc<0){int err=0;socklen_t len=sizeof(err);if(poll(&p,1,600)<=0||getsockopt(fd,SOL_SOCKET,SO_ERROR,&err,&len)<0||err){close(fd);return 0;}}
 const char req[]="GET /screen.txt HTTP/1.0\r\nHost: 127.0.0.1:8090\r\nConnection: close\r\n\r\n";
 size_t sent=0;
 while(sent<sizeof(req)-1){
  p.events=POLLOUT;if(poll(&p,1,600)<=0){close(fd);return 0;}
  ssize_t k=send(fd,req+sent,sizeof(req)-1-sent,0);if(k<=0){close(fd);return 0;}sent+=(size_t)k;
 }
 int complete=0;
 for(int tries=0;tries<40&&n<sizeof(buf)-1;tries++){
  p.events=POLLIN;if(poll(&p,1,600)<=0)break;
  ssize_t k=recv(fd,buf+n,sizeof(buf)-1-n,0);
  if(k==0){complete=1;break;}if(k<0)break;n+=(size_t)k;
 }
 close(fd);buf[n]=0;
 if(!complete||strncmp(buf,"HTTP/1.",7)||strncmp(buf+9,"200 ",4))return 0;
 const char *body=strstr(buf,"\r\n\r\n");return body&&screen_parse(s,body+4);
}
static void draw(const Screen *s,int available){
 rect(0,0,W,H,0xff101827);rect(36,32,1208,656,0xff192538);
 rect(36,32,1208,8,0xff55a9ff);
 text(70,78,4,0xfff1f5f9,"PS4 TAILSCALE");
#ifdef UI_FIXTURE
 text(70,144,2,0xffffc46b,"EMULATOR FIXTURE - NOT AUTHENTICATED");
#else
 text(70,144,2,0xff94a3b8,"PRIVATE REMOTE PLAY");
#endif
 rect(70,190,650,350,0xff101827);rect(746,190,462,350,0xff101827);
 text(94,214,2,0xff94a3b8,"CONNECTION");
 text(94,252,3,s->ready?0xff75e0ad:0xffffc46b,available?s->state:"Backend unavailable");
 text(94,316,2,0xff94a3b8,"TAILNET ADDRESS");
 text(94,352,3,0xffe2e8f0,available?s->ip:"-");
 text(94,420,2,0xff94a3b8,"REMOTE PLAY");
 text(94,454,2,0xffe2e8f0,s->ready?"READY - OPEN PXPLAY":"WAITING FOR BACKEND");
 if(available&&s->n>0){
  int k=300/s->n,span=k*s->n,x=977-span/2,y=208;
  rect(x,y,span,span,0xffffffff);
  for(int j=0;j<s->n;j++)for(int i=0;i<s->n;i++)if(s->cells[j][i])rect(x+i*k,y+j*k,k,k,0xff000000);
#ifdef UI_FIXTURE
  text(783,512,2,0xffffc46b,"DEMO QR - DO NOT SCAN");
#else
  text(795,512,2,0xffe2e8f0,"SCAN WITH IPHONE");
#endif
 }else{
  text(782,300,2,0xff94a3b8,s->ready?"LOGIN COMPLETE":"NO LOGIN QR YET");
 }
 text(72,580,2,0xff94a3b8,"NO PSN LOGIN OR PUBLIC PORT FORWARDING");
 text(72,625,2,0xff94a3b8,"LOCAL STATUS UI - NETWORK SETTINGS UNCHANGED");
}
#ifdef EMBED_RUNTIME
int frontend_main(void){
#else
int main(void){
#endif
 setvbuf(stdout,NULL,_IONBF,0);
 int v=sceVideoOutOpen(ORBIS_VIDEO_USER_MAIN,ORBIS_VIDEO_OUT_BUS_MAIN,0,0);
 if(v<0){printf("PS4TS_VIDEO_FAIL %d\n",v);return 1;}
 size_t frame=(W*H*4+0x1fffff)&~(size_t)0x1fffff;
 off_t off=0;void *mem=NULL;
 if(sceKernelAllocateDirectMemory(0,sceKernelGetDirectMemorySize(),frame*2,0x200000,3,&off)<0||
    sceKernelMapDirectMemory(&mem,frame*2,0x33,0,off,0x200000)<0){puts("PS4TS_MEMORY_FAIL");return 2;}
 void *buffers[2]={mem,(char*)mem+frame};
 OrbisVideoOutBufferAttribute attr;
 sceVideoOutSetBufferAttribute(&attr,0x80000000,1,0,W,H,W);
 if(sceVideoOutRegisterBuffers(v,0,buffers,2,&attr)<0){puts("PS4TS_REGISTER_FAIL");return 3;}
 sceVideoOutSetFlipRate(v,0);
 Screen s;int frameid=1,idx=0,available;
 for(;;){
  memset(&s,0,sizeof(s));strcpy(s.ip,"-");
#ifdef UI_FIXTURE
  available=screen_parse(&s,fixture);
#else
  available=read_live(&s);
#endif
  pixels=(uint32_t*)buffers[idx];draw(&s,available);
  int rc=sceVideoOutSubmitFlip(v,idx,ORBIS_VIDEO_OUT_FLIP_VSYNC,frameid);
  if(rc<0){printf("PS4TS_FLIP_FAIL %d\n",rc);return 4;}
  int shown=0;for(int i=0;i<120;i++){
   OrbisVideoOutFlipStatus st;memset(&st,0,sizeof(st));
   if(sceVideoOutGetFlipStatus(v,&st)==0&&st.flipArg==frameid){shown=1;break;}
   sceKernelUsleep(16000);
  }
  if(!shown){puts("PS4TS_FLIP_TIMEOUT");return 5;}
  if(frameid==1)puts("PS4TS_UI_FRAME_PRESENTED");
  idx^=1;frameid++;sceKernelUsleep(500000);
 }
}
