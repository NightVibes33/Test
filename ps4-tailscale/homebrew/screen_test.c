#include "screen.h"
#include <assert.h>
#include <string.h>
int main(void){
 Screen s;
 assert(screen_parse(&s,"PS4TS1\nRunning\n100.64.0.1\n1\n0\n"));
 assert(s.ready&&s.n==0);
 assert(screen_parse(&s,"PS4TS1\nNeedsLogin\n-\n0\n2\n10\n01\n"));
 assert(s.n==2&&s.cells[0][0]&&!s.cells[0][1]);
 assert(!screen_parse(&s,"PS4TS1\nNeedsLogin\n-\n0\n122\n"));
 assert(!screen_parse(&s,"PS4TS1\nNeedsLogin\n-\n1\n0\n"));
 assert(!screen_parse(&s,"PS4TS1\nNeedsLogin\n-\n0\n2\n10\n0x\n"));
 return 0;
}
