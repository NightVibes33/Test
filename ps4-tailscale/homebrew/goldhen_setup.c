#define _POSIX_C_SOURCE 200809L
#include "goldhen_setup.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>
#ifndef TS_DATA_ROOT
#define TS_DATA_ROOT "/data"
#endif
#define SRC "/app0/assets/TailScale.elf"
#define DST TS_DATA_ROOT "/payloads/TailScale.elf"
#define INI TS_DATA_ROOT "/GoldHEN/payloads.ini"
static char *trim(char *s){while(isspace((unsigned char)*s))s++;char *e=s+strlen(s);while(e>s&&isspace((unsigned char)e[-1]))*--e=0;return s;}
static int copy_file(const char *src,const char *dst){
 struct stat st;if(lstat(src,&st)||!S_ISREG(st.st_mode))return -1;
 char tmp[256];if(snprintf(tmp,sizeof(tmp),"%s.tmp.XXXXXX",dst)>=(int)sizeof(tmp))return -1;
 FILE *a=fopen(src,"rb");if(!a)return -1;int fd=mkstemp(tmp);if(fd<0){fclose(a);return -1;}
 FILE *b=fdopen(fd,"wb");if(!b){close(fd);unlink(tmp);fclose(a);return -1;}
 char buf[16384];size_t n;int ok=1;while((n=fread(buf,1,sizeof(buf),a))>0)if(fwrite(buf,1,n,b)!=n){ok=0;break;}
 if(ferror(a)||fflush(b)||fsync(fd))ok=0;
 fclose(a);if(fclose(b))ok=0;if(!ok||rename(tmp,dst)){unlink(tmp);return -1;}return 0;
}
static int owned(char *line){
 char *eq=strchr(line,'=');if(!eq)return 0;*eq=0;char *k=trim(line);
 return !strcmp(k,"/data/payloads/TailScale.elf")||!strcmp(k,"/user/data/payloads/TailScale.elf");
}
int goldhen_autorun(int enable){
 if(enable)return -2;
 struct stat st;if(lstat(INI,&st))return errno==ENOENT?0:-1;
 if(!S_ISREG(st.st_mode)||st.st_size>1024*1024)return -1;
 FILE *in=fopen(INI,"rb");if(!in)return -1;
 char tmp[]=INI ".tailscale.XXXXXX";int fd=mkstemp(tmp);if(fd<0){fclose(in);return -1;}
 FILE *out=fdopen(fd,"wb");if(!out){close(fd);unlink(tmp);fclose(in);return -1;}
 char line[4096],check[4096];int section=0,changed=0,ok=1;
 while(fgets(line,sizeof(line),in)){
  if(!strchr(line,'\n')&&!feof(in)){ok=0;break;}
  memcpy(check,line,strlen(line)+1);char *p=trim(check);
  if(*p=='['){char *end=strchr(p,']');if(!end){ok=0;break;}*end=0;section=!strcasecmp(trim(p+1),"autorun");}
  else if(section&&owned(p)){changed=1;continue;}
  if(fputs(line,out)==EOF){ok=0;break;}
 }
 if(ferror(in))ok=0;fclose(in);
 if(fchmod(fd,st.st_mode&0777)||fflush(out)||fsync(fd))ok=0;if(fclose(out))ok=0;
 if(!ok||!changed){unlink(tmp);return ok?0:-1;}
 if(access(INI ".tailscale-backup",F_OK)&&copy_file(INI,INI ".tailscale-backup")){unlink(tmp);return -1;}
 struct stat now;if(lstat(INI,&now)||now.st_ino!=st.st_ino||now.st_size!=st.st_size||now.st_mtime!=st.st_mtime){unlink(tmp);return -1;}
 if(rename(tmp,INI)){unlink(tmp);return -1;}return 0;
}
int goldhen_stage(void){
 struct stat s;if(lstat(TS_DATA_ROOT "/GoldHEN",&s)||!S_ISDIR(s.st_mode))return -1;
 if(lstat(SRC,&s)||!S_ISREG(s.st_mode)||s.st_size<1000000||s.st_size>128*1024*1024)return -1;
 if(mkdir(TS_DATA_ROOT "/payloads",0755)&&errno!=EEXIST)return -1;
 if(goldhen_autorun(0))return -1;return copy_file(SRC,DST);
}
int goldhen_remove(void){
 if(goldhen_autorun(0))return -1;
 if(unlink(DST)&&errno!=ENOENT)return -1;
 return 0;
}
