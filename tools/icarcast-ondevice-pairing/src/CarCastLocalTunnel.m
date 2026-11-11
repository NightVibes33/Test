// CarCastLocalTunnel — device-local loopback packet tunnel.
// Original algorithm based on SideStore/StosVPN (MIT, attribution in NOTICES).
// It routes 10.7.0.1 to this iPhone; it does NOT implement CarPlay transport.
#import <NetworkExtension/NetworkExtension.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <string.h>

@interface CCPacketTunnelProvider : NEPacketTunnelProvider
@end
@implementation CCPacketTunnelProvider
- (void)startTunnelWithOptions:(NSDictionary<NSString *,NSObject *> *)options
            completionHandler:(void (^)(NSError *))completion {
    (void)options;
    NEPacketTunnelNetworkSettings *settings=[[NEPacketTunnelNetworkSettings alloc]
        initWithTunnelRemoteAddress:@"10.7.0.1"];
    NEIPv4Settings *ipv4=[[NEIPv4Settings alloc]
         initWithAddresses:@[@"10.7.0.0"] subnetMasks:@[@"255.255.255.0"]];
    ipv4.includedRoutes=@[[[NEIPv4Route alloc] initWithDestinationAddress:@"10.7.0.1"
                                subnetMask:@"255.255.255.255"]];
    ipv4.excludedRoutes=@[[[NEIPv4Route alloc] initWithDestinationAddress:@"0.0.0.0"
                                subnetMask:@"0.0.0.0"]];
    settings.IPv4Settings=ipv4;
    [self setTunnelNetworkSettings:settings completionHandler:^(NSError *err) {
        if(!err) [self transferPackets];
        completion(err);
    }];
}
- (void)transferPackets {
    __weak CCPacketTunnelProvider *weakSelf=self;
    [self.packetFlow readPacketsWithCompletionHandler:^(NSArray<NSData *> *packets,NSArray<NSNumber *> *protocols) {
        CCPacketTunnelProvider *strongSelf=weakSelf;
        if(!strongSelf) return;
        NSMutableArray<NSData *> *replies=[NSMutableArray arrayWithCapacity:packets.count];
        for(NSUInteger i=0;i<packets.count;i++) {
            NSData *input=packets[i];
            if(i>=protocols.count || protocols[i].intValue!=AF_INET || input.length<20) {
                [replies addObject:input];continue;
            }
            NSMutableData *copy=[input mutableCopy];
            uint8_t *buf=copy.mutableBytes;
            if((buf[0]>>4)==4) {
                uint8_t previous[4];
                memcpy(previous,buf+12,4);
                memcpy(buf+12,buf+16,4);
                memcpy(buf+16,previous,4);
                // Header and TCP/UDP pseudoheader checksums are invariant to
                // swapping the two IPv4 addresses: the additive sum is identical.
            }
            [replies addObject:copy];
        }
        [strongSelf.packetFlow writePackets:replies withProtocols:protocols];
        [strongSelf transferPackets];
    }];
}
- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))completion {
    (void)reason; completion();
}
@end
