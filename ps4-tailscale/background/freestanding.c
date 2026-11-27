#include "freestanding.h"
void *memcpy(void *d,const void *s,size_t n){unsigned char *a=d;const unsigned char *b=s;while(n--)*a++=*b++;return d;}
void *memset(void *d,int c,size_t n){unsigned char *a=d;while(n--)*a++=(unsigned char)c;return d;}
int memcmp(const void *a,const void *b,size_t n){const unsigned char *x=a,*y=b;while(n--){if(*x!=*y)return (int)*x-(int)*y;x++;y++;}return 0;}
void *calloc(size_t n,size_t z){if(z&&n>(SIZE_MAX-16)/z)return 0;size_t sz=n*z+16;void *p=mmap(0,sz,3,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);if(p==MAP_FAILED)return 0;*(size_t*)p=sz;return (unsigned char*)p+16;}
void free(void *p){if(p){size_t *base=(size_t*)((unsigned char*)p-16);munmap(base,*base);}}
