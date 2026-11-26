/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "screen.h"
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
static int line(const char **p,char *out,size_t n){
 const char *e=strchr(*p,'\n');if(!e||e-*p>=(long)n)return 0;
 size_t k=(size_t)(e-*p);memcpy(out,*p,k);out[k]=0;*p=e+1;return 1;
}
static int number(const char *s,int max,int *out){
 int n=0;if(!*s)return 0;
 for(;*s;s++){if(*s<'0'||*s>'9')return 0;n=n*10+*s-'0';if(n>max)return 0;}*out=n;return 1;
}
int screen_parse(Screen *out,const char *p){
 Screen tmp;memset(&tmp,0,sizeof(tmp));char s[QR_MAX+2];
 if(!line(&p,s,sizeof(s))||strcmp(s,"PS4TS1"))return 0;
 if(!line(&p,tmp.state,sizeof(tmp.state))||!line(&p,tmp.ip,sizeof(tmp.ip)))return 0;
 for(const char *q=tmp.state;*q;q++)if(!isalnum((unsigned char)*q)&&*q!=' '&&*q!='-')return 0;
 for(const char *q=tmp.ip;*q;q++)if(!isdigit((unsigned char)*q)&&*q!='.'&&*q!='-')return 0;
 if(!line(&p,s,sizeof(s))||!number(s,1,&tmp.ready))return 0;
 if(!line(&p,s,sizeof(s))||!number(s,QR_MAX,&tmp.n))return 0;
 for(int y=0;y<tmp.n;y++){
  if(!line(&p,s,sizeof(s))||strlen(s)!=(size_t)tmp.n)return 0;
  for(int x=0;x<tmp.n;x++){if(s[x]!='0'&&s[x]!='1')return 0;tmp.cells[y][x]=(unsigned char)(s[x]=='1');}
 }
 if(*p|| (tmp.ready&&strcmp(tmp.state,"Running")))return 0;
 *out=tmp;return 1;
}
