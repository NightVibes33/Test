// CarCastWiFiFallback.m
// Optional Wi-Fi identity fallback for user-signed copies of iCarCast.
//
// The signed app may lack Access Wi-Fi Information, so
// NEHotspotNetwork.fetchCurrentWithCompletionHandler: can legitimately return nil.
// After informing the user, this shim supplies the SSID they manually typed.
// It NEVER claims that iOS supplied or verified that SSID. It does not alter
// network configuration, force authorization or bypass system entitlements.
//
// No Apple ID, FairPlay credential or pairing data is used here.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <NetworkExtension/NetworkExtension.h>
#import <objc/runtime.h>
extern void CCLogEvent(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);

static NSString *const CCService = @"ai.rplay.carcast.manual-wifi.v1";
static NSString *const CCAccount = @"selected-network";
static char CCManualNetworkAssociation;
static IMP CCOriginalFetch = NULL;
static NSMutableArray *CCPendingCallbacks;
static BOOL CCShowingPrompt = NO;

static NSDictionary<NSString *, NSString *> *CCReadManualNetwork(void) {
    NSDictionary *request = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: CCService,
        (__bridge id)kSecAttrAccount: CCAccount,
        (__bridge id)kSecReturnData: @1,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef raw = NULL;
    OSStatus result = SecItemCopyMatching((__bridge CFDictionaryRef)request, &raw);
    if (result != errSecSuccess || !raw) { CCLogEvent(@"manual-network Keychain lookup status=%ld", (long)result); return nil; }
    NSData *bytes = CFBridgingRelease(raw);
    if (![bytes isKindOfClass:NSData.class]) return nil;
    NSDictionary *config = [NSPropertyListSerialization propertyListWithData:bytes options:NSPropertyListImmutable format:NULL error:nil];
    if (![config isKindOfClass:NSDictionary.class]) return nil;
    NSString *ssid = config[@"ssid"];
    NSString *password = config[@"password"];
    if (![ssid isKindOfClass:NSString.class] || ssid.length == 0) return nil;
    if (![password isKindOfClass:NSString.class]) return nil;
    return config;
}

static BOOL CCStoreManualNetwork(NSString *ssid, NSString *password) {
    if (ssid.length == 0 || [ssid dataUsingEncoding:NSUTF8StringEncoding].length > 32) return NO;
    // An empty password represents an open network. WPA passwords must be
    // 8-63 UTF-8 characters or 64 hexadecimal characters.
    NSUInteger pwCount = password.length;
    if (pwCount != 0 && (pwCount < 8 || pwCount > 64)) return NO;
    if (pwCount == 64) {
        NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
        if ([[password stringByTrimmingCharactersInSet:hex] length] != 0) return NO;
    }
    NSDictionary *config = @{@"ssid":ssid, @"password":password};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:config format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!data) return NO;
    NSDictionary *match = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: CCService,
        (__bridge id)kSecAttrAccount: CCAccount
    };
    SecItemDelete((__bridge CFDictionaryRef)match);
    NSMutableDictionary *add = match.mutableCopy;
    add[(__bridge id)kSecValueData] = data;
    add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    OSStatus result=SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    CCLogEvent(@"manual-network Keychain save status=%ld; credentials redacted", (long)result);
    return result == errSecSuccess;
}

static NSDictionary *CCDetails(id obj) {
    return objc_getAssociatedObject(obj, &CCManualNetworkAssociation);
}
static id CCGetSSID(id self, SEL cmd) {
    (void)cmd;
    return CCDetails(self)[@"ssid"];
}
static id CCGetBSSID(id self, SEL cmd) {
    (void)self; (void)cmd;
    return @"00:00:00:00:00:00";
}
static NSInteger CCGetSecurityType(id self, SEL cmd) {
    (void)cmd;
    NSString *password = CCDetails(self)[@"password"];
    // The OS cannot confirm security mode when the entitlement is absent.
    // Use the user-provided password to distinguish open vs WPA personal.
    return password.length == 0 ? 0 : 2;
}
static BOOL CCGetIsSecure(id self, SEL cmd) {
    return CCGetSecurityType(self, cmd) != 0;
}
static double CCGetSignalStrength(id self, SEL cmd) {
    (void)self; (void)cmd; return 0.0;
}
static BOOL CCGetFalse(id self, SEL cmd) { (void)self; (void)cmd; return NO; }

static id CCSyntheticNetwork(NSDictionary *network) {
    if (!network) return nil;
    Class base = NSClassFromString(@"NEHotspotNetwork");
    if (!base) return nil;
    static Class fakeClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fakeClass = objc_lookUpClass("CCUserSuppliedNetwork");
        if (!fakeClass) {
            fakeClass = objc_allocateClassPair(base, "CCUserSuppliedNetwork", 0);
            if (!fakeClass) return;
            class_addMethod(fakeClass, @selector(SSID), (IMP)CCGetSSID, "@@:");
            class_addMethod(fakeClass, @selector(BSSID), (IMP)CCGetBSSID, "@@:");
            class_addMethod(fakeClass, @selector(securityType), (IMP)CCGetSecurityType, "q@:");
            class_addMethod(fakeClass, @selector(isSecure), (IMP)CCGetIsSecure, "B@:");
            class_addMethod(fakeClass, @selector(signalStrength), (IMP)CCGetSignalStrength, "d@:");
            class_addMethod(fakeClass, @selector(didAutoJoin), (IMP)CCGetFalse, "B@:");
            class_addMethod(fakeClass, @selector(isAutoJoined), (IMP)CCGetFalse, "B@:");
            class_addMethod(fakeClass, @selector(didJustJoin), (IMP)CCGetFalse, "B@:");
            class_addMethod(fakeClass, @selector(isJustJoined), (IMP)CCGetFalse, "B@:");
            objc_registerClassPair(fakeClass);
        }
    });
    if (!fakeClass) return nil;
    // Do not invoke NEHotspotNetwork's unavailable/private designated initializer.
    id obj = CFBridgingRelease((__bridge CFTypeRef)class_createInstance(fakeClass, 0));
    if (obj) objc_setAssociatedObject(obj, &CCManualNetworkAssociation, network, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return obj;
}

static UIViewController *CCTopViewController(void) {
    UIApplication *application = UIApplication.sharedApplication;
    UIWindow *activeWindow = nil;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) { activeWindow = window; break; }
        }
        if (activeWindow) break;
    }
    UIViewController *top = activeWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

static void CCResolvePending(id network) {
    NSArray *pending = CCPendingCallbacks.copy;
    [CCPendingCallbacks removeAllObjects];
    CCShowingPrompt = NO;
    for (id callback in pending) {
        void (^completion)(id) = (void (^)(id))callback;
        completion(network);
    }
}

static void CCShowManualPrompt(void) {
    NSCAssert(NSThread.isMainThread, @"Wi-Fi prompt must run on main thread");
    if (CCShowingPrompt) return;
    UIViewController *presenter = CCTopViewController();
    if (!presenter) { CCLogEvent(@"fallback prompt: no foreground view controller"); CCResolvePending(nil); return; }
    CCShowingPrompt = YES;
    CCLogEvent(@"manual Wi-Fi fallback prompt presented");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Wi-Fi for CarPlay"
            message:@"iOS did not provide the current Wi-Fi name to this signed app. Enter the SSID of the Wi-Fi you are already joined to, and its real password. This does NOT join, reconfigure or verify a network."
            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Exact network name (SSID)";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Wi-Fi password (empty if open)";
        field.secureTextEntry = YES;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        (void)action; CCLogEvent(@"manual Wi-Fi fallback cancelled"); CCResolvePending(nil);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Use This Network" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        NSString *ssid = alert.textFields.firstObject.text ?: @"";
        NSString *password = alert.textFields.count > 1 ? (alert.textFields[1].text ?: @"") : @"";
        CCLogEvent(@"manual Wi-Fi fallback submitted (SSID/password redacted)");
        if (!CCStoreManualNetwork(ssid, password)) {
            CCResolvePending(nil);
            return;
        }
        // The app's original workflow still receives a typed NEHotspotNetwork.
        // It remains responsible for password prompts and starting CarPlay.
        CCResolvePending(CCSyntheticNetwork(CCReadManualNetwork()));
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void CCFallbackFetch(id klass, SEL sel, void (^completion)(id)) {
    if (!completion) return;
    CCLogEvent(@"NEHotspotNetwork.fetchCurrent called");
    if (!CCOriginalFetch) { CCLogEvent(@"Wi-Fi hook original IMP unavailable"); completion(nil); return; }
    void (^saved)(id) = [completion copy];
    ((void (*)(id, SEL, id))CCOriginalFetch)(klass, sel, ^(id osNetwork) {
        if (osNetwork) { CCLogEvent(@"OS returned current Wi-Fi network (name redacted)"); saved(osNetwork); return; }
        CCLogEvent(@"OS current Wi-Fi lookup returned nil; fallback begins");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!CCPendingCallbacks) CCPendingCallbacks = NSMutableArray.new;
            [CCPendingCallbacks addObject:saved];
            NSDictionary *manual = CCReadManualNetwork();
            if (manual) {
                CCLogEvent(@"using saved manual Wi-Fi profile (values redacted)");
                CCResolvePending(CCSyntheticNetwork(manual));
                return;
            }
            CCShowManualPrompt();
        });
    });
}

__attribute__((constructor)) static void CCInstallWiFiFallback(void) {
    @autoreleasepool {
        // Link NetworkExtension and install only for applications explicitly
        // containing this shim. The original API is always called first.
        Class type = NSClassFromString(@"NEHotspotNetwork");
        if (!type) { CCLogEvent(@"NEHotspotNetwork class missing; Wi-Fi hook not installed"); return; }
        Method fetch = class_getClassMethod(type, @selector(fetchCurrentWithCompletionHandler:));
        if (!fetch) { CCLogEvent(@"fetchCurrentWithCompletionHandler: unavailable; Wi-Fi hook not installed"); return; }
        CCOriginalFetch = method_setImplementation(fetch, (IMP)CCFallbackFetch);
        CCLogEvent(@"NEHotspotNetwork fetchCurrent method hook installed");
    }
}
