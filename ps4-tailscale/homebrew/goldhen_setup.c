#include "goldhen_setup.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>
#define SRC "/app0/assets/TailScale.elf"
#define DST "/data/payloads/TailScale.elf"
#define INI "/data/GoldHEN/payloads.ini"
#define ENTRY "/data/payloads/TailScale.elf = 1"
static int copy_file(const char *src,const char *dst){
 char tmp[256];if(snprintf(tmp,sizeof(tmp),"%s.tmp.XXXXXX",dst)>=(int)sizeof(tmp))return -1;
 FILE *a=fopen(src,"rb");if(!a)return -1;int fd=mkstemp(tmp);if(fd<0){fclose(a);return -1;}FILE *b=fdopen(fd,"wb");if(!b){close(fd);unlink(tmp);fclose(a);return -1;}
 char buf[16384];size_t n;int ok=1;while((n=fread(buf,1,sizeof(buf),a))>0)if(fwrite(buf,1,n,b)!=n){ok=0;break;}
 if(ferror(a)||fflush(b)||fsync(fd))ok=0;fclose(a);if(fclose(b))ok=0;
 if(!ok||rename(tmp,dst)){unlink(tmp);return -1;}return 0;
}
int goldhen_stage(void){
 struct stat s;if(stat("/data/GoldHEN",&s)||!S_ISDIR(s.st_mode))return -1;
 if(stat(SRC,&s)||s.st_size<1000000||s.st_size>128*1024*1024)return -1;
 if(mkdir("/data/payloads",0755)&&errno!=EEXIST)return -1;
 return copy_file(SRC,DST);
}
int goldhen_autorun(int enable){
 struct stat st;if(stat("/data/GoldHEN",&st)||!S_ISDIR(st.st_mode))return -1;
 if(enable&&access(DST,R_OK))return -1;
 FILE *in=fopen(INI,"rb");if(!in&&errno!=ENOENT)return -1;
 if(in){if(fstat(fileno(in),&st)||st.st_size>1024*1024){fclose(in);return -1;}
  // Backup original before editing; never overwrite a previous backup.
  if(access(INI ".tailscale-backup",F_OK)&&copy_file(INI,INI ".tailscale-backup")){fclose(in);return -1;}
 }
 char tmp[]=INI ".tailscale.XXXXXX";int fd=mkstemp(tmp);if(fd<0){if(in)fclose(in);return -1;}
 FILE *out=fdopen(fd,"wb");if(!out){close(fd);unlink(tmp);if(in)fclose(in);return -1;}
 char line[4096];int section=0,inserted=0,ok=1;
 while(in&&fgets(line,sizeof(line),in)){
  if(!strchr(line,'\n')&&!feof(in)){ok=0;break;}
  char check[4096];snprintf(check,sizeof(check),"%s",line);check[strcspn(check,"\r\n")]=0;
  if(check[0]=='['){
   if(section&&enable&&!inserted){fprintf(out,"\n%s\n",ENTRY);inserted=1;}
   section=!strcmp(check,"[AutoRun]");
  }
  if(section&&(!strcmp(check,ENTRY)||!strcmp(check,"/data/payloads/TailScale.elf = 0")))continue;
  if(fputs(line,out)==EOF){ok=0;break;}
 }
 if(in){if(ferror(in))ok=0;fclose(in);}
 if(enable&&!inserted){if(!section)fprintf(out,"\n[AutoRun]\n");fprintf(out,"\n%s\n",ENTRY);}
 if(fflush(out)||fsync(fd))ok=0;if(fclose(out))ok=0;
 if(!ok||rename(tmp,INI)){unlink(tmp);return -1;}return 0;
}
