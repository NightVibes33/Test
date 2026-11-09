// CarCastDiagnosticsOnly.m: original CarPlay behavior, persistent read-only diagnostics.
// Does not grant network entitlements, modify Wi-Fi, or access system logs.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <Security/Security.h>
#import <Network/Network.h>
#import <NetworkExtension/NetworkExtension.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdarg.h>

static int CCLogFD = -1;
static NSUncaughtExceptionHandler *CCPreviousHandler = NULL;
static nw_path_monitor_t CCPathMonitor;
static void CCSetup(void);

void CCLogEvent(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
void CCLogEvent(NSString *format, ...) {
    if (CCLogFD < 0) return;
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ [CarCastDebug] %@\n", NSDate.date, msg];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data) (void)write(CCLogFD, data.bytes, data.length);
}

static void CCException(NSException *exception) {
    CCLogEvent(@"uncaught exception: name=%@ reason=%@ stack=%@",
               exception.name, exception.reason,
               [exception.callStackSymbols componentsJoinedByString:@" | "]);
    if (CCPreviousHandler) CCPreviousHandler(exception);
}

static void CCLogEntitlement(NSString *name) {
    // SecTask entitlement inspection is not available through the public iOS SDK
    // used by this runner. Inspect the actual SideStore-signed IPA instead.
    CCLogEvent(@"entitlement %@ = inspect signed IPA externally (not queried in-app)", name);
}
static void CCSystemState(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    CCLogEvent(@"app bundle=%@ version=%@ iOS=%@ Files=%d openInPlace=%d",
        NSBundle.mainBundle.bundleIdentifier ?: @"unknown",
        info[@"CFBundleShortVersionString"] ?: @"unknown",
        UIDevice.currentDevice.systemVersion,
        [info[@"UIFileSharingEnabled"] boolValue],
        [info[@"LSSupportsOpeningDocumentsInPlace"] boolValue]);
    CCLogEvent(@"location authorization=%ld (no permission request made)",
        (long)[[CLLocationManager alloc] init].authorizationStatus);
    CCLogEntitlement(@"com.apple.developer.networking.wifi-info");
    CCLogEntitlement(@"com.apple.developer.networking.multicast");
    CCLogEntitlement(@"com.apple.developer.networking.HotspotConfiguration");
}
static void CCReadOnlyWiFiProbe(void) {
    [NEHotspotNetwork fetchCurrentWithCompletionHandler:^(NEHotspotNetwork * _Nullable network) {
        CCLogEvent(@"independent read-only Wi-Fi probe: %@; network identifiers redacted",
                   network ? @"network returned" : @"nil");
    }];
}
static void CCSetup(void) {
    NSString *folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/CarCastDebug"];
    if (![NSFileManager.defaultManager createDirectoryAtPath:folder
             withIntermediateDirectories:YES attributes:nil error:nil]) return;
    NSString *readme = @"CarCastDebug session logs\n\nFiles > On My iPhone > iCarCast > CarCastDebug\n\n"
        @"Each launch creates a new session log. Look for the 'instrumentation loaded' marker.\n"
        @"Includes app startup, network path, independent Wi-Fi lookup results, "
        @"signing-entitlement inspection instructions, app lifecycle and stdout/stderr.\n"
        @"This is NOT a complete iOS system log or daemon trace.\n"
        @"App stdout/stderr might contain sensitive details. Review and redact before sharing.\n"
        @"The shim does not intentionally log SSIDs, passwords or FairPlay credentials.\n";
    [readme writeToFile:[folder stringByAppendingPathComponent:@"README.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSDateFormatter *formatter = NSDateFormatter.new;
    formatter.dateFormat = @"yyyyMMdd-HHmmss-SSS";
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *path = [folder stringByAppendingPathComponent:
        [NSString stringWithFormat:@"session-%@-%d.log", [formatter stringFromDate:NSDate.date], getpid()]];
    CCLogFD = open(path.fileSystemRepresentation, O_CREAT | O_WRONLY | O_APPEND | O_CLOEXEC, 0600);
    if (CCLogFD < 0) return;
    fflush(stdout); fflush(stderr);
    (void)dup2(CCLogFD, STDOUT_FILENO);
    (void)dup2(CCLogFD, STDERR_FILENO);
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    CCLogEvent(@"=== Original iCarCast diagnostic-only framework loaded; no networking API replacements ===");
    NSArray<NSString *> *all = [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil];
    NSMutableArray<NSString *> *logs = NSMutableArray.new;
    for (NSString *name in all) {
        if ([name hasPrefix:@"session-"] && [name hasSuffix:@".log"]) [logs addObject:name];
    }
    [logs sortUsingSelector:@selector(compare:)];
    for (NSUInteger i=0; i+8<logs.count; i++)
        [NSFileManager.defaultManager removeItemAtPath:[folder stringByAppendingPathComponent:logs[i]] error:nil];

    CCPreviousHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(CCException);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
                   usingBlock:^(NSNotification *n) { (void)n; CCLogEvent(@"app active"); CCSystemState(); CCReadOnlyWiFiProbe(); }];
    [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
                   usingBlock:^(NSNotification *n) { (void)n; CCLogEvent(@"app resign active"); }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil
                   usingBlock:^(NSNotification *n) { (void)n; CCLogEvent(@"app background"); }];
    [center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil
                   usingBlock:^(NSNotification *n) { (void)n; CCLogEvent(@"memory warning"); }];
    CCPathMonitor = nw_path_monitor_create();
    nw_path_monitor_set_update_handler(CCPathMonitor, ^(nw_path_t path) {
        CCLogEvent(@"network path status=%ld wifi=%d cellular=%d",
                   (long)nw_path_get_status(path),
                   nw_path_uses_interface_type(path, nw_interface_type_wifi),
                   nw_path_uses_interface_type(path, nw_interface_type_cellular));
    });
    nw_path_monitor_set_queue(CCPathMonitor, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    nw_path_monitor_start(CCPathMonitor);
    dispatch_async(dispatch_get_main_queue(), ^{ CCSystemState(); CCReadOnlyWiFiProbe(); });
}
__attribute__((constructor)) static void CCStartDiagnostics(void) {
    @autoreleasepool { CCSetup(); }
}
