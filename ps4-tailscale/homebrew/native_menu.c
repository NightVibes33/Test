/* Native controller UI; no browser or HTML renderer. */
#include "native_menu.h"
#include "goldhen_setup.h"
#include <orbis/Pad.h>
#include <orbis/UserService.h>
#include <orbis/libkernel.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>
#define ROWS 96
typedef struct{char kind,id[81],label[241],value[241];} Row;
static Row rows[ROWS],workrows[ROWS],pending_rows[ROWS];static int workn,pending_n,pending_page=-1;
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static int wanted_page=-1,job_pending,busy;static char job_id[81],job_value[241],result[241];static int job_page,job_available;static int n,page,selected,editing,confirm,handle=-1,letter,refresh;
static char edit[241],message[241];static uint32_t last;
static int qr_visible=1;
int native_show_qr(void){return page==0&&qr_visible;}
static const char *pages[]={"Status / QR","Devices","Settings","Local forwards","Game streaming","Wake-on-LAN","Taildrop","Diagnostics","GoldHEN setup"};
static const char alphabet[]=" abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/,@[]";
static int request(const char *path,const char *body,char *out,size_t cap){
 int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return 0;
 struct timeval tv={15,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv));
 struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(8090);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
 int flags=fcntl(fd,F_GETFL,0);if(flags<0||fcntl(fd,F_SETFL,flags|O_NONBLOCK)<0){close(fd);return 0;}int c=connect(fd,(struct sockaddr*)&a,sizeof(a));if(c<0){struct pollfd p={fd,POLLOUT,0};int e=0;socklen_t sz=sizeof(e);if(errno!=EINPROGRESS||poll(&p,1,700)<=0||getsockopt(fd,SOL_SOCKET,SO_ERROR,&e,&sz)||e){close(fd);return 0;}}if(fcntl(fd,F_SETFL,flags)<0){close(fd);return 0;}
 char req[1024];int len=snprintf(req,sizeof(req),"%s %s HTTP/1.0\r\nHost: 127.0.0.1:8090\r\nX-PS4-Native: 1\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n%s",body?"POST":"GET",path,body?strlen(body):0,body?body:"");
 if(len<0||(size_t)len>=sizeof(req)){close(fd);return 0;}
 size_t off=0;while(off<(size_t)len){ssize_t k=send(fd,req+off,(size_t)len-off,0);if(k<=0){close(fd);return 0;}off+=(size_t)k;}
 off=0;int complete=0;while(off<cap-1){ssize_t k=recv(fd,out+off,cap-1-off,0);if(k==0){complete=1;break;}if(k<0)break;off+=(size_t)k;}close(fd);out[off]=0;
 char *p=strstr(out,"\r\n\r\n");if(!complete||!p||strncmp(out,"HTTP/1.",7))return 0;
 int code=atoi(out+9);memmove(out,p+4,strlen(p+4)+1);return code;
}
static void row(char k,const char *id,const char *label,const char *value){
 if(workn>=ROWS)return;Row *r=&workrows[workn++];r->kind=k;snprintf(r->id,sizeof(r->id),"%s",id);snprintf(r->label,sizeof(r->label),"%s",label);snprintf(r->value,sizeof(r->value),"%s",value);
}
static void fetch_page(int page){
 workn=0;
 if(page==8){
  row('r',"","Payload","Separate GoldHEN daemon ELF");
  row('a',"stage","Stage bundled daemon","No execution or AutoRun");
  row('r',"","AutoRun locked","Physical validation required");
  row('a',"disable","Disable AutoRun","Preserves other entries");
  row('a',"remove","Remove staged payload","Preserves identity and files");
  row('r',"","First launch","Use GoldHEN PayLoader manually");
  row('r',"","Firmware 14.02","Runtime not hardware validated");
 }else{
  char path[64];static char buf[65536];snprintf(path,sizeof(path),"/native?page=%d",page);
  if(request(path,NULL,buf,sizeof(buf))==200&&!strncmp(buf,"TSN1\n",5)){
   char *p=buf+5;while(*p&&workn<ROWS){
    char *end=strchr(p,'\n');if(!end)break;*end=0;char *a=strchr(p,'\t');if(!a)break;*a++=0;char *b=strchr(a,'\t');if(!b)break;*b++=0;char *c=strchr(b,'\t');if(!c)break;*c++=0;
    if(strlen(p)==1&&strchr("rae",*p))row(*p,a,b,c);p=end+1;
   }
  }else row('r',"","Daemon unavailable","Open GoldHEN setup with R1/L1");
 }
 
}
static void run_action(int page,const char *id,const char *value,int available,char *reply){
 if(page==8){int e=-1;
  if(!strcmp(id,"stage"))e=goldhen_stage();
  (void)available;
  if(!strcmp(id,"disable"))e=goldhen_autorun(0);
  if(!strcmp(id,"remove"))e=goldhen_remove();
  snprintf(reply,241,e==0?"Done. Changes saved.":e==-2?"AutoRun locked until hardware validation.":"Failed: check GoldHEN and storage permissions.");return;
 }
 char body[340],out[4096];snprintf(body,sizeof(body),"%s\n%s",id,value);
 int code=request("/native",body,out,sizeof(out));if(!code)snprintf(reply,241,"Daemon did not respond");else snprintf(reply,241,"%d: %.195s",code,out);
}
static void load(int available){(void)available;pthread_mutex_lock(&lock);wanted_page=page;pthread_mutex_unlock(&lock);}
static void execute(const char *id,const char *value,int available){
 pthread_mutex_lock(&lock);
 if(!busy&&!job_pending){snprintf(job_id,sizeof(job_id),"%s",id);snprintf(job_value,sizeof(job_value),"%s",value);job_page=page;job_available=available;job_pending=1;busy=1;snprintf(message,sizeof(message),"Working...");}
 pthread_mutex_unlock(&lock);
}
static void *menu_worker(void *unused){
 (void)unused;
 for(;;){
  char id[81],val[241],reply[241];int jp=-1,ja=0,fp=-1;
  pthread_mutex_lock(&lock);if(job_pending){jp=job_page;ja=job_available;memcpy(id,job_id,sizeof(id));memcpy(val,job_value,sizeof(val));memset(job_value,0,sizeof(job_value));job_pending=0;}else if(wanted_page>=0){fp=wanted_page;wanted_page=-1;}pthread_mutex_unlock(&lock);
  if(jp>=0){run_action(jp,id,val,ja,reply);memset(val,0,sizeof(val));pthread_mutex_lock(&lock);snprintf(result,sizeof(result),"%s",reply);busy=0;pthread_mutex_unlock(&lock);}
  else if(fp>=0){fetch_page(fp);pthread_mutex_lock(&lock);memcpy(pending_rows,workrows,sizeof(workrows));pending_n=workn;pending_page=fp;pthread_mutex_unlock(&lock);}
  sceKernelUsleep(50000);
 }return NULL;
}
void native_init(void){
 int user=-1;sceUserServiceInitialize(NULL);if(sceUserServiceGetInitialUser(&user)==0&&scePadInit()==0)handle=scePadOpen(user,0,0,NULL);
 pthread_t th;if(pthread_create(&th,NULL,menu_worker,NULL)==0){pthread_detach(th);load(0);}else snprintf(message,sizeof(message),"Network worker unavailable");
}
int native_page(void){return page;}
void native_tick(int qr_present){
 pthread_mutex_lock(&lock);if(result[0]){snprintf(message,sizeof(message),"%s",result);result[0]=0;wanted_page=page;}if(!editing&&!confirm&&pending_page==page){memcpy(rows,pending_rows,sizeof(rows));n=pending_n;pending_page=-1;if(selected>=n)selected=n?n-1:0;}int blocked=busy;pthread_mutex_unlock(&lock);
 uint32_t b=0;OrbisPadData d;memset(&d,0,sizeof(d));if(handle>=0&&scePadReadState(handle,&d)>=0)b=d.buttons;uint32_t hit=b&~last;last=b;
 if(page==0&&!editing&&!confirm&&(hit&ORBIS_PAD_BUTTON_OPTIONS)){qr_visible=!qr_visible;return;}
 if(editing){
  size_t len=strlen(edit);
  if(hit&ORBIS_PAD_BUTTON_UP)letter=(letter+1)%(sizeof(alphabet)-1);
  if(hit&ORBIS_PAD_BUTTON_DOWN)letter=(letter+(int)sizeof(alphabet)-2)%(sizeof(alphabet)-1);
  if(hit&ORBIS_PAD_BUTTON_CROSS&&len<240){edit[len]=alphabet[letter];edit[len+1]=0;}
  if(hit&ORBIS_PAD_BUTTON_SQUARE&&len)edit[len-1]=0;
  if(hit&ORBIS_PAD_BUTTON_TRIANGLE){execute(rows[selected].id,edit,qr_present);memset(edit,0,sizeof(edit));editing=0;load(qr_present);}
  if(hit&ORBIS_PAD_BUTTON_CIRCLE){memset(edit,0,sizeof(edit));editing=0;}return;
 }
 if(confirm){if(hit&ORBIS_PAD_BUTTON_CROSS){execute(rows[selected].id,"",qr_present);confirm=0;load(qr_present);}if(hit&ORBIS_PAD_BUTTON_CIRCLE)confirm=0;return;}
 if(hit&ORBIS_PAD_BUTTON_R1){page=(page+1)%9;selected=0;n=0;load(qr_present);}
 if(hit&ORBIS_PAD_BUTTON_L1){page=(page+8)%9;selected=0;n=0;load(qr_present);}
 if(hit&ORBIS_PAD_BUTTON_UP&&selected>0)selected--;
 if(hit&ORBIS_PAD_BUTTON_DOWN&&selected+1<n)selected++;
 if(hit&ORBIS_PAD_BUTTON_CROSS&&n&&!blocked&&!(page==0&&qr_visible&&!qr_present&&n>0&&strcmp(rows[0].label,"Daemon unqr_present"))){Row *r=&rows[selected];if(r->kind=='e'){snprintf(edit,sizeof(edit),"%s",r->value);letter=0;editing=1;}else if(r->kind=='a')confirm=1;}
 if(++refresh>=180){refresh=0;load(qr_present);}
}
void native_draw(NativeText text,NativeRect rect){
 const uint32_t fg=0xffe8eaed,muted=0xff9aa1ab,blue=0xff7fa4ff;
 rect(0,0,1280,720,0xff14161a);text(48,30,3,fg,"TailScale on PS4");text(48,82,2,muted,"L1 / R1  Switch section");
 for(int i=0;i<9;i++){rect(45,125+i*49,300,43,i==page?0xff35466a:0xff1e2126);text(55,134+i*49,1,i==page?blue:fg,pages[i]);}
 text(370,92,3,fg,pages[page]);int top=selected>7?selected-7:0;
 for(int i=top;i<n&&i<top+8;i++){int y=144+(i-top)*61;rect(365,y,870,57,i==selected?0xff35466a:0xff1e2126);char a[49],v[49];snprintf(a,sizeof(a),"%.48s",rows[i].label);snprintf(v,sizeof(v),"%.48s",!strcmp(rows[i].id,"password")?"":rows[i].value);text(378,y+3,2,fg,a);text(378,y+29,2,muted,v);}
 char m[67];snprintf(m,sizeof(m),"%.66s",message);text(48,635,1,blue,m);
 text(48,665,2,muted,"Up/Down Select   X Open   L1/R1 Tabs");if(page==0)text(48,694,1,muted,"OPTIONS: toggle QR / status controls");
 if(editing||confirm){rect(220,250,840,220,0xff30353c);rect(223,253,834,214,0xff1e2126);
  text(245,270,2,fg,editing?"Edit setting":"Confirm selected action");
  if(editing){char val[43],ch[24];size_t l=strlen(edit);snprintf(val,sizeof(val),"%.42s",edit+(l>42?l-42:0));if(!strcmp(rows[selected].id,"password"))memset(val,'*',strlen(val));snprintf(ch,sizeof(ch),"Character: [%c]",alphabet[letter]);text(245,313,2,fg,val);text(245,355,2,blue,ch);text(245,410,1,muted,"Up/Down character | X add | Square delete | Triangle save | Circle cancel");}
  else{text(245,320,2,fg,"X Confirm    Circle Cancel");}
 }
}
