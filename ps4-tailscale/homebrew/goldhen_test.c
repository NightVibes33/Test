#include "goldhen_setup.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
int main(void){
 mkdir("/tmp/ps4ts-test",0700);mkdir("/tmp/ps4ts-test/GoldHEN",0700);
 const char *path="/tmp/ps4ts-test/GoldHEN/payloads.ini";
 FILE *f=fopen(path,"wb");assert(f);fputs("[Other]\nkeep=1\n [aUtOrUn] ; comment\r\n /user/data/payloads/TailScale.elf=1\r\n/data/payloads/other.elf = 1\n[Else]\n/data/payloads/TailScale.elf=0\n",f);fclose(f);
 assert(goldhen_autorun(1)==-2);assert(goldhen_autorun(0)==0);assert(goldhen_autorun(0)==0);
 char b[1024]={0};f=fopen(path,"rb");assert(f);fread(b,1,sizeof(b)-1,f);fclose(f);
 assert(!strcmp(b,"[Other]\nkeep=1\n [aUtOrUn] ; comment\r\n/data/payloads/other.elf = 1\n[Else]\n/data/payloads/TailScale.elf=0\n"));
 puts("GoldHEN configuration preservation PASS");return 0;
}
