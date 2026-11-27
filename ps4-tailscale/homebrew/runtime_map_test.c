#include "runtime_loader.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
int main(int argc,char **argv){
 if(argc!=2)return 2;
 FILE *f=fopen(argv[1],"rb");assert(f);assert(!fseek(f,0,SEEK_END));long n=ftell(f);assert(n>0);rewind(f);
 unsigned char *b=malloc((size_t)n);assert(b);assert(fread(b,1,(size_t)n,f)==(size_t)n);fclose(f);
 RuntimeImage im;assert(runtime_map(b,16,&im)!=0);
 unsigned char old=b[7];b[7]=0;assert(runtime_map(b,(size_t)n,&im)!=0);b[7]=old;
 int rc=runtime_map(b,(size_t)n,&im);printf("runtime map %s: %d\n",argv[1],rc);
 if(rc==0)runtime_unmap(&im);
 free(b);return rc!=0;
}
