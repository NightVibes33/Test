/* SPDX-License-Identifier: GPL-3.0-or-later
 * Read-only socket capability probe. No kernel offsets, patches, DNS changes,
 * routing changes, persistent writes, or listening on the external interface.
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>

int main(void) {
    struct sockaddr_in a;
    socklen_t len = sizeof(a);
    struct timeval tv = {2, 0};
    char in[8] = {0};
    int ok = 0;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int u = socket(AF_INET, SOCK_DGRAM, 0);
    printf("PS4 Remote Play capability probe (no configuration changes)\n");
    if (u < 0) { printf("UDP socket: %s\n", strerror(errno)); return 1; }
    if (setsockopt(u,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv)) == 0 &&
        bind(u,(struct sockaddr *)&a,sizeof(a)) == 0 &&
        getsockname(u,(struct sockaddr *)&a,&len) == 0 &&
        sendto(u,"ps4",3,0,(struct sockaddr *)&a,len) == 3 &&
        recvfrom(u,in,sizeof(in),0,NULL,NULL) == 3 &&
        memcmp(in,"ps4",3) == 0) {
        printf("UDP loopback: PASS\n"); ok=1;
    } else printf("UDP loopback: FAIL (%s)\n",strerror(errno));
    close(u);
    int t=socket(AF_INET,SOCK_STREAM,0);
    if(t>=0) {
        a.sin_port=htons(9295);
        if(connect(t,(struct sockaddr *)&a,sizeof(a))==0)
            printf("Remote Play TCP 9295 loopback: reachable\n");
        else printf("Remote Play TCP 9295 loopback: %s (enable Remote Play first)\n",strerror(errno));
        close(t);
    } else printf("TCP socket: %s\n",strerror(errno));
    printf("Done; no Tailscale session has been started.\n");
    fflush(stdout);
    return ok?0:1;
}
