// iCarCastPairing.m — built-in Remote Pairing + Local VPN UI.
// MIT idevice FFI for real pairing/RSD, not a fabricated CarPlay transport.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <NetworkExtension/NetworkExtension.h>
#import <Network/Network.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <TargetConditionals.h>
extern void CCLogEvent(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);

#if !TARGET_OS_SIMULATOR
typedef struct RpPairingFileHandle RpPairingFileHandle;
typedef struct AdapterHandle AdapterHandle;
typedef struct RsdHandshakeHandle RsdHandshakeHandle;
typedef struct IdeviceFfiError { int32_t code; int32_t sub_code; const char *message; } IdeviceFfiError;
extern IdeviceFfiError *rp_pairing_file_from_bytes(const uint8_t *, uintptr_t, RpPairingFileHandle **);
extern IdeviceFfiError *rp_pairing_file_read(const char *, RpPairingFileHandle **);
extern IdeviceFfiError *rp_pairing_file_generate(const char *, RpPairingFileHandle **);
extern IdeviceFfiError *rp_pairing_file_write(RpPairingFileHandle *, const char *);
extern void rp_pairing_file_free(RpPairingFileHandle *);
extern void idevice_error_free(IdeviceFfiError *);
extern IdeviceFfiError *tunnel_create_rppairing(const struct sockaddr *, socklen_t, const char *,
                                RpPairingFileHandle *, const char *(*)(void *), void *,
                                AdapterHandle **, RsdHandshakeHandle **);
extern void adapter_free(AdapterHandle *);
extern void rsd_handshake_free(RsdHandshakeHandle *);
#endif

static NSString *const CCHost = @"10.7.0.1";
static NSString *const CCRemotePortKey = @"CarCastRPPortOverride";
static NSString *const CCPairingStatusNotice = @"Local Pairing is for iOS developer services; it does not itself replace CarPlay Wi-Fi transport.";
static NSString *CCPairingPath(void) {
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/CarCastPairing"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"pairingFile.plist"];
}
static NSString *CCFFIErrorText(int32_t code) {
    return [NSString stringWithFormat:@"idevice error %ld (details redacted; inspect compatibility and pairing format)",(long)code];
}
static NSString *CCStatus(void) {
    return [NSFileManager.defaultManager fileExistsAtPath:CCPairingPath()] ? @"RP pairing file imported" : @"No RP pairing file";
}

@interface CCPairingUI : NSObject <UIDocumentPickerDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,strong) NETunnelProviderManager *vpnManager;
@property(nonatomic,strong) NSNetServiceBrowser *browser;
@property(nonatomic,strong) NSMutableArray<NSNetService *> *services;
@property(nonatomic,strong) dispatch_queue_t work;
@property(nonatomic,assign) uint16_t chosenPort;
@property(nonatomic,assign) BOOL connecting;
#if !TARGET_OS_SIMULATOR
@property(nonatomic,assign) AdapterHandle *adapter;
@property(nonatomic,assign) RsdHandshakeHandle *handshake;
#endif
@end

@implementation CCPairingUI
+ (instancetype)shared {
    static CCPairingUI *instance; static dispatch_once_t once;
    dispatch_once(&once, ^{ instance=[CCPairingUI new]; });
    return instance;
}
- (instancetype)init {
    if ((self=[super init])) {
        _work=dispatch_queue_create("ai.rplay.carcast.pairing",DISPATCH_QUEUE_SERIAL);
        _services=[NSMutableArray new];
        _chosenPort=0;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scheduleButton)
             name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(vpnChanged)
             name:NEVPNStatusDidChangeNotification object:nil];
    }
    return self;
}
- (void)scheduleButton {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.6*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        [self installButton];
    });
}
- (UIWindow *)activeWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow && w.rootViewController) return w;
        }
    }
    return UIApplication.sharedApplication.keyWindow;
}
- (UIViewController *)top {
    UIViewController *c=[self activeWindow].rootViewController;
    while (c.presentedViewController) c=c.presentedViewController;
    return c;
}
- (void)installButton {
    UIWindow *w=[self activeWindow];
    if (!w || !w.rootViewController) return;
    if (self.window!=w) { [self.button removeFromSuperview]; self.button=nil; self.window=w; }
    if (self.button) return;
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    b.frame=CGRectMake(MAX(8,w.bounds.size.width-111),w.safeAreaInsets.top+7,101,34);
    b.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleBottomMargin;
    b.layer.cornerRadius=11.0;
    b.backgroundColor=[UIColor colorWithRed:0.10 green:0.17 blue:0.25 alpha:0.90];
    [b setTitle:@"Pairing" forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    [b addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    b.accessibilityLabel=@"iCarCast device pairing and local VPN";
    [w addSubview:b];
    self.button=b;
    CCLogEvent(@"Embedded iDevicePair UI ready");
}
- (void)message:(NSString *)title detail:(NSString *)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *c=[self top]; if (!c) return;
        UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:detail
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [c presentViewController:a animated:YES completion:nil];
    });
}
- (void)showMenu {
    NSString *details=[NSString stringWithFormat:@"%@\nRemote Pairing endpoint: %@:%@\n%@",
        CCStatus(),CCHost, self.chosenPort ? [NSString stringWithFormat:@"%u",self.chosenPort] : @"Discover automatically",
        CCPairingStatusNotice];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"iCarCast • Device Pairing"
        message:details preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Import RP Pairing File" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {[self importPairing];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Generate New RP Host Keys" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {[self generatePairing];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Start Built-In Local VPN" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {[self startVPN];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Stop Built-In Local VPN" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {[self stopVPN];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Discover Pairing Port" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {[self discoverPort];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Set Pairing Port" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {[self setPort];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Connect / Pair This iPhone" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {[self connectPairing];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete Pairing File" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *act) {
        NSError *e=nil; [NSFileManager.defaultManager removeItemAtPath:CCPairingPath() error:&e];
        CCLogEvent(@"RP pairing record deletion %@",e?@"FAILED":@"complete");
        [self message:@"Pairing File" detail:e.localizedDescription?:@"Saved pairing record deleted."];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *pop=a.popoverPresentationController;
    if (pop) {pop.sourceView=self.button;pop.sourceRect=self.button.bounds;}
    [[self top] presentViewController:a animated:YES completion:nil];
}
- (void)importPairing {
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
           initForOpeningContentTypes:@[UTTypePropertyList, UTTypeXML, UTTypeData] asCopy:YES];
    picker.delegate=self; picker.allowsMultipleSelection=NO;
    [[self top] presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url=urls.firstObject; if (!url) return;
    BOOL scoped=[url startAccessingSecurityScopedResource];
    NSData *data=[NSData dataWithContentsOfURL:url];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!data || data.length<32 || data.length>1024*1024) {
        [self message:@"Invalid pairing file" detail:@"The selected file could not be read or has an invalid size."];
        return;
    }
    NSError *e=nil;
    NSDictionary *plist=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&e];
    if (![plist isKindOfClass:NSDictionary.class]) {
        [self message:@"Invalid pairing file" detail:@"Expected a Remote Pairing property list (.plist or .mobiledevicepairing)."];
        return;
    }
    if (plist[@"HostID"] || plist[@"HostCertificate"]) {
        [self message:@"Classic Lockdown file" detail:@"This is a classic idevicepair record. The local RSD tunnel requires an RP record with public_key, private_key and identifier. Generate one in this menu or export Remote Pairing from idevice_pair."];
        return;
    }
#if !TARGET_OS_SIMULATOR
    RpPairingFileHandle *handle=NULL;
    IdeviceFfiError *err=rp_pairing_file_from_bytes(data.bytes,(uintptr_t)data.length,&handle);
    if (err || !handle) {
        int code=err?err->code:-1;
        if (err) idevice_error_free(err);
        if (handle) rp_pairing_file_free(handle);
        CCLogEvent(@"RP pairing file rejected by idevice (code=%ld)",(long)code);
        [self message:@"Invalid RP record" detail:@"The idevice parser rejected this file. Select a modern Remote Pairing record (public_key/private_key/identifier)."];
        return;
    }
    rp_pairing_file_free(handle);
#else
    if (!plist[@"public_key"] || !plist[@"private_key"] || !plist[@"identifier"]) {
        [self message:@"Invalid RP record" detail:@"Missing modern Remote Pairing fields."];
        return;
    }
#endif
    NSString *path=CCPairingPath();
    if (![data writeToFile:path options:NSDataWritingAtomic error:&e]) {
        [self message:@"Import failed" detail:e.localizedDescription?:@"Could not write pairing file."];
        return;
    }
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,
        NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication}
        ofItemAtPath:path error:NULL];
    CCLogEvent(@"RP pairing record imported and protected (%lu bytes; contents redacted)",(unsigned long)data.length);
    [self message:@"Pairing imported" detail:@"RP pairing file stored privately in Application Support. Connect the built-in VPN, then use Connect / Pair This iPhone."];
}
- (void)generatePairing {
#if TARGET_OS_SIMULATOR
    [self message:@"Simulator" detail:@"Remote Pairing is available only in the physical iOS build."];
#else
    [self message:@"Generating host keys" detail:@"New RP keys are not yet paired. Accept any iOS trust prompt when you connect."];
    dispatch_async(self.work, ^{
        RpPairingFileHandle *handle=NULL;
        IdeviceFfiError *e=rp_pairing_file_generate("CarCast",&handle);
        if (e || !handle) {
            int code=e?e->code:-1; if(e)idevice_error_free(e);
            if(handle)rp_pairing_file_free(handle);
            CCLogEvent(@"RP key generation failed code=%ld",(long)code);
            [self message:@"Generation failed" detail:CCFFIErrorText(code)]; return;
        }
        NSString *path=CCPairingPath();
        IdeviceFfiError *write=rp_pairing_file_write(handle,path.fileSystemRepresentation);
        int status=write?write->code:0; if(write)idevice_error_free(write);
        rp_pairing_file_free(handle);
        if(status!=0) { [self message:@"Save failed" detail:CCFFIErrorText(status)];return; }
        [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,
            NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication}
            ofItemAtPath:path error:NULL];
        CCLogEvent(@"New RP host keys generated (secrets redacted; not yet paired)");
        [self message:@"Host keys created" detail:@"Start the local VPN, then tap Connect / Pair This iPhone. Creating keys does not establish trust by itself."];
    });
#endif
}
- (void)vpnChanged {
    if (!self.vpnManager) return;
    CCLogEvent(@"Embedded local VPN state=%ld",(long)self.vpnManager.connection.status);
}
- (void)loadVPN:(void (^)(NETunnelProviderManager *,NSError *))completion {
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers,NSError *err) {
        if (err) {completion(nil,err);return;}
        NSString *bundle=NSBundle.mainBundle.bundleIdentifier ?: @"";
        NSString *extensionID=[bundle stringByAppendingString:@".CarCastLocalTunnel"];
        // The resigning tool may rewrite the appex identifier: derive it from the installed bundle.
        NSString *plistPath=[NSBundle.mainBundle.builtInPlugInsPath
            stringByAppendingPathComponent:@"CarCastLocalTunnel.appex/Info.plist"];
        NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:plistPath];
        if ([info[@"CFBundleIdentifier"] isKindOfClass:NSString.class]) extensionID=info[@"CFBundleIdentifier"];
        NETunnelProviderManager *manager=nil;
        for (NETunnelProviderManager *candidate in managers)
            if ([candidate.protocolConfiguration isKindOfClass:NETunnelProviderProtocol.class] &&
                [((NETunnelProviderProtocol *)candidate.protocolConfiguration).providerBundleIdentifier isEqualToString:extensionID])
                manager=candidate;
        if (!manager) manager=[NETunnelProviderManager new];
        NETunnelProviderProtocol *proto=[NETunnelProviderProtocol new];
        proto.providerBundleIdentifier=extensionID;
        proto.serverAddress=@"Local device only";
        proto.providerConfiguration=@{@"TunnelDeviceIP":@"10.7.0.0",@"TunnelFakeIP":@"10.7.0.1"};
        manager.protocolConfiguration=proto;
        manager.localizedDescription=@"iCarCast Local Pairing Tunnel";
        manager.enabled=YES;
        [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
            if (saveError) {completion(nil,saveError);return;}
            [manager loadFromPreferencesWithCompletionHandler:^(NSError *reloadError) {
                completion(reloadError?nil:manager,reloadError);
            }];
        }];
    }];
}
- (void)startVPN {
#if TARGET_OS_SIMULATOR
    [self message:@"Simulator" detail:@"Packet Tunnel extensions cannot be tested in an ordinary simulator smoke test."];
#else
    [self loadVPN:^(NETunnelProviderManager *manager,NSError *err) {
        if (err || !manager) {
            CCLogEvent(@"Local VPN configuration failed code=%ld",(long)err.code);
            [self message:@"Local VPN unavailable" detail:@"The signed app and extension need the packet-tunnel-provider entitlement and compatible provisioning profiles. See CarCastDebug logs."];
            return;
        }
        self.vpnManager=manager;
        NSError *startError=nil;
        BOOL ok=[manager.connection startVPNTunnelAndReturnError:&startError];
        CCLogEvent(@"Local VPN start requested=%d errorCode=%ld",ok,(long)startError.code);
        [self message:ok?@"VPN activation requested":@"VPN start failed"
                detail:ok?@"Approve the iOS VPN configuration prompt and return to iCarCast. This is an on-device development tunnel, not a CarPlay transport.":
                    (startError.localizedDescription?:@"VPN could not start; verify signing entitlements.")];
    }];
#endif
}
- (void)stopVPN {
    if (!self.vpnManager) { [self message:@"Local VPN" detail:@"No tunnel started by iCarCast in this session."];return; }
    [self.vpnManager.connection stopVPNTunnel];
    CCLogEvent(@"Local VPN stop requested");
    [self message:@"Local VPN" detail:@"Stop requested."];
}
- (void)setPort {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Remote Pairing Port"
         message:@"Use the real port advertised by _remotepairing._tcp. Leave blank to rediscover automatically."
         preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType=UIKeyboardTypeNumberPad;
        field.placeholder=@"e.g. 54833";
        NSString *n=[NSUserDefaults.standardUserDefaults stringForKey:CCRemotePortKey];
        if(n)field.text=n;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act){
        NSString *s=a.textFields.firstObject.text ?: @"";
        NSInteger p=s.integerValue;
        if (s.length && (p<1 || p>65535 || [s rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound)) {
            [self message:@"Invalid port" detail:@"Use a port from 1 to 65535, or leave it empty."];return;
        }
        [NSUserDefaults.standardUserDefaults setObject:s forKey:CCRemotePortKey];
        self.chosenPort=(uint16_t)p;
        CCLogEvent(@"Remote Pairing port override %s",s.length?"set":"cleared");
        [self message:@"Pairing port" detail:s.length?[NSString stringWithFormat:@"Port %@ selected.",s]:@"Automatic Bonjour discovery enabled."];
    }]];
    [[self top] presentViewController:a animated:YES completion:nil];
}
- (void)discoverPort {
    NSString *manual=[NSUserDefaults.standardUserDefaults stringForKey:CCRemotePortKey];
    if (manual.integerValue>0 && manual.integerValue<65536) {
        self.chosenPort=(uint16_t)manual.integerValue;
        [self message:@"Port override" detail:[NSString stringWithFormat:@"Using manually entered port %u.",self.chosenPort]];
        return;
    }
    [self.browser stop];self.browser=nil;[self.services removeAllObjects];self.chosenPort=0;
    self.browser=[NSNetServiceBrowser new];self.browser.delegate=self;
    self.browser.includesPeerToPeer=YES;
    [self.browser searchForServicesOfType:@"_remotepairing._tcp." inDomain:@"local."];
    CCLogEvent(@"Discovering _remotepairing._tcp for local RSD port");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self.browser stop];self.browser=nil;
        if (!self.chosenPort) {
            [self message:@"Port not found" detail:@"Remote Pairing Bonjour service was not resolved. Check Local Network permission and VPN, or enter the actual port manually. Do not assume 49152."];
        } else {
            [self message:@"Remote Pairing discovered" detail:[NSString stringWithFormat:@"Port %u selected. You can now connect.",self.chosenPort]];
        }
    });
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    (void)browser;(void)moreComing;
    [self.services addObject:service];
    service.delegate=self;service.includesPeerToPeer=YES;[service resolveWithTimeout:4];
}
- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    if(sender.port<=0 || sender.port>65535) return;
    // Only the selected local device should be used. Do not blindly join a remote host.
    NSString *host=sender.hostName.lowercaseString ?: @"";
    if(![host hasSuffix:@".local."] && ![host hasSuffix:@".local"]) return;
    if(!self.chosenPort) {
        self.chosenPort=(uint16_t)sender.port;
        CCLogEvent(@"Bonjour Remote Pairing port discovered=%u; endpoint IP fixed to local VPN",self.chosenPort);
    }
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    (void)browser;(void)errorDict;CCLogEvent(@"Remote Pairing Bonjour discovery failed");
}
- (void)connectPairing {
#if TARGET_OS_SIMULATOR
    [self message:@"Simulator" detail:@"RSD pairing only runs on the physical iPhone."];
#else
    if (self.connecting) {[self message:@"Pairing" detail:@"A connection attempt is already running."];return;}
    if(![NSFileManager.defaultManager fileExistsAtPath:CCPairingPath()]) {
        [self message:@"Pairing file required" detail:@"Import a modern Remote Pairing file or generate host keys first."];return;
    }
    uint16_t port=self.chosenPort;
    NSString *manual=[NSUserDefaults.standardUserDefaults stringForKey:CCRemotePortKey];
    if(!port && manual.integerValue>0 && manual.integerValue<65536) port=(uint16_t)manual.integerValue;
    if(!port) { [self message:@"Discover port first" detail:@"Use Discover Pairing Port before connecting. Fixed port 49152 is unreliable on iOS 27."];return;}
    self.connecting=YES;
    CCLogEvent(@"Starting real idevice RPPairing handshake to local VPN port=%u",port);
    [self message:@"Connecting…" detail:@"Attempting a real remote-pairing/RSD handshake via the local VPN. The original CarPlay receiver is unchanged."];
    dispatch_async(self.work, ^{
        RpPairingFileHandle *record=NULL;
        IdeviceFfiError *readError=rp_pairing_file_read(CCPairingPath().fileSystemRepresentation,&record);
        if(readError||!record) {
            int32_t code=readError?readError->code:-1;
            if(readError)idevice_error_free(readError);
            if(record)rp_pairing_file_free(record);
            CCLogEvent(@"RPPairing read failed code=%ld",(long)code);
            self.connecting=NO;[self message:@"Pairing file invalid" detail:CCFFIErrorText(code)];return;
        }
        struct sockaddr_in target={0};
        target.sin_len=sizeof(target);
        target.sin_family=AF_INET;
        target.sin_port=htons(port);
        inet_pton(AF_INET,CCHost.UTF8String,&target.sin_addr);
        AdapterHandle *adapter=NULL;RsdHandshakeHandle *handshake=NULL;
        IdeviceFfiError *err=tunnel_create_rppairing((const struct sockaddr *)&target,sizeof(target),
             "CarCast",record,NULL,NULL,&adapter,&handshake);
        int32_t code=err?err->code:0;
        if(err)idevice_error_free(err);
        // The record may have been updated by a first-time pair setup; save it securely.
        if(!err && adapter && handshake) {
            IdeviceFfiError *save=rp_pairing_file_write(record,CCPairingPath().fileSystemRepresentation);
            if(save){CCLogEvent(@"RPPairing save update failed code=%ld",(long)save->code);idevice_error_free(save);}
            [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,
                NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication}
                ofItemAtPath:CCPairingPath() error:NULL];
            if(self.handshake)rsd_handshake_free(self.handshake);
            if(self.adapter)adapter_free(self.adapter);
            self.adapter=adapter;self.handshake=handshake;
            CCLogEvent(@"REAL idevice RPPairing + RSD handshake established; no CarPlay transport claims");
            [self message:@"Device pairing connected" detail:@"The on-device RSD tunnel is active. This verifies developer-service connectivity, NOT Wi-Fi-free CarPlay. The original receiver has not been replaced."];
        } else {
            if(adapter)adapter_free(adapter);
            if(handshake)rsd_handshake_free(handshake);
            CCLogEvent(@"RPPairing/RSD tunnel failed code=%ld",(long)code);
            [self message:@"Pairing connection failed"
                   detail:[NSString stringWithFormat:@"%@. Check VPN, port, local-network authorization, and RP record.",CCFFIErrorText(code)]];
        }
        rp_pairing_file_free(record);
        self.connecting=NO;
    });
#endif
}
@end

__attribute__((constructor)) static void CCInstallPairing(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            CCPairingUI *ui=[CCPairingUI shared];
            [ui scheduleButton];
            CCLogEvent(@"Embedded pairing module loaded (original CarPlay networking untouched)");
        });
    }
}
