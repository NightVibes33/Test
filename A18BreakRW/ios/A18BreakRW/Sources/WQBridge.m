#import "WQBridge.h"
#import "worse_query.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <errno.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <string.h>
#import <stdlib.h>

// SecTask prototypes are not surfaced by every iOS SDK header,
// although the Security framework exports them (also used by WQFiles).
typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

static NSString *A18Err(int e) {
    return [NSString stringWithFormat:@"errno=%d (%s)", e, strerror(e)];
}

static NSArray<NSString *> *A18SignedGroups(void) {
    SecTaskRef task = SecTaskCreateFromSelf(NULL);
    if (!task) return @[];
    CFErrorRef error = NULL;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.security.application-groups"), &error);
    NSArray *groups = CFBridgingRelease(value);
    if (error) CFRelease(error);
    CFRelease(task);
    if (![groups isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *safe = [NSMutableArray array];
    for (id item in groups) {
        if ([item isKindOfClass:[NSString class]] && [item length] > 0) [safe addObject:item];
    }
    return safe;
}

static NSString *A18UsableGroup(NSArray<NSString *> *groups) {
    for (NSString *group in groups) {
        if ([[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:group]) return group;
    }
    return nil;
}

static BOOL A18MarkerAllowed(NSString *canonical) {
    NSArray *prefixes = @[
        @"/private/var/mobile/Containers/Data/Application/",
        @"/private/var/mobile/Containers/Shared/AppGroup/",
        @"/private/var/mobile/Containers/Data/InternalDaemon/",
        @"/private/var/mobile/Containers/Data/PluginKitPlugin/",
        @"/private/var/containers/Data/System/",
        @"/private/var/containers/Shared/SystemGroup/"
    ];
    for (NSString *prefix in prefixes) {
        if ([canonical hasPrefix:prefix] && canonical.length > prefix.length) return YES;
    }
    return NO;
}

// This function never opens an existing file for writing, deleting or editing.
// All writes are exclusive temporary markers, immediately removed.
// It exists solely to distinguish access acquired with an actual sandbox extension.
NSDictionary<NSString *, id> *A18WQProbe(NSString *path, BOOL attemptMarker) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"path"] = path ?: @"";
    result[@"timeUTC"] = [[NSISO8601DateFormatter new] stringFromDate:[NSDate date]];
    result[@"device"] = [[UIDevice currentDevice] systemVersion];
    result[@"source"] = @"forcequitOS/worse_query GPL-3.0-or-later; independently integrated";
    result[@"claim"] = @"Only measured directory and exclusive temporary marker operations. No root, kernel R/W or sealed-system modification.";
    NSArray *groups = A18SignedGroups();
    result[@"signedGroupCount"] = @(groups.count);
    NSString *group = A18UsableGroup(groups);
    result[@"usableGroup"] = group ?: @"NONE";
    if (!group) {
        result[@"extension"] = @"UNAVAILABLE: Signed app lacks a functional App Group entitlement. SideStore provisioning must preserve a registered group.";
        return result;
    }
    if (![path hasPrefix:@"/"] || [path containsString:@".."]) {
        result[@"extension"] = @"REFUSED: absolute normalized directory path required";
        return result;
    }
    struct stat st;
    int before = open(path.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (before < 0) result[@"normalRead"] = A18Err(errno);
    else { close(before); result[@"normalRead"] = @"PASS: ordinary directory open"; }
    // Original PoC is used unchanged, including app-owned App Group Caches cleanup.
    int64_t handle = worse_query(path, group, false, false);
    result[@"extensionHandleStatus"] = @(handle);
    if (handle < 0) {
        result[@"extension"] = [NSString stringWithFormat:@"FAILED: worse_query returned %lld", (long long)handle];
        return result;
    }
    result[@"extension"] = @"GRANTED: sandbox extension consumed";
    @try {
        int fd = open(path.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (fd < 0) result[@"extendedRead"] = A18Err(errno);
        else {
            close(fd);
            NSError *err = nil;
            NSArray *listing = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&err];
            if (listing) {
                result[@"extendedRead"] = @"PASS: directory opened and enumerated";
                result[@"entryCount"] = @(listing.count);
                // Offer only real, immediate child directories for the next
                // on-device test. Never recurse or read private file contents.
                NSMutableArray<NSString *> *children = [NSMutableArray array];
                for (id name in [listing sortedArrayUsingSelector:@selector(compare:)]) {
                    if (![name isKindOfClass:NSString.class]) continue;
                    NSString *component = (NSString *)name;
                    if ([component isEqualToString:@"."] || [component isEqualToString:@".."] ||
                        [component containsString:@"/"]) continue;
                    NSString *child = [path stringByAppendingPathComponent:component];
                    struct stat cst;
                    if (lstat(child.fileSystemRepresentation, &cst) == 0 && S_ISDIR(cst.st_mode)) {
                        [children addObject:child];
                        if (children.count >= 128) break;
                    }
                }
                result[@"childDirectories"] = children;
            } else result[@"extendedRead"] = [NSString stringWithFormat:@"PARTIAL: open succeeded, enumeration failed: %@", err.localizedDescription ?: @"unknown"];
        }
        if (!attemptMarker) {
            result[@"marker"] = @"NOT_TESTED (user did not enable)";
        } else {
            char resolved[PATH_MAX];
            if (realpath(path.fileSystemRepresentation, resolved) == NULL) {
                result[@"marker"] = [NSString stringWithFormat:@"REFUSED: canonical path unavailable: %@", A18Err(errno)];
            } else if (!A18MarkerAllowed([NSString stringWithUTF8String:resolved])) {
                result[@"marker"] = @"REFUSED: marker writes limited to known data-container descendants";
            } else if (lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) {
                result[@"marker"] = @"REFUSED: destination is not a real directory";
            } else {
                NSString *marker = [path stringByAppendingPathComponent:[NSString stringWithFormat:@".a18break-%@.tmp", [NSUUID UUID].UUIDString]];
                int f = open(marker.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
                if (f < 0) {
                    result[@"marker"] = [NSString stringWithFormat:@"DENIED: %@", A18Err(errno)];
                } else {
                    static const char payload[] = "A18Break-WQ-marker-v1\n";
                    ssize_t amount = write(f, payload, sizeof(payload) - 1);
                    int synced = amount == sizeof(payload) - 1 ? fsync(f) : -1;
                    int writeErr = errno;
                    close(f);
                    char bytes[sizeof(payload)] = {0};
                    int rfd = open(marker.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
                    ssize_t n = rfd >= 0 ? read(rfd, bytes, sizeof(payload)-1) : -1;
                    if (rfd >= 0) close(rfd);
                    BOOL matches = (amount == sizeof(payload)-1 && synced == 0 && n == sizeof(payload)-1 && memcmp(bytes,payload,sizeof(payload)-1) == 0);
                    result[@"marker"] = matches ? @"PASS: exclusive create, write, fsync, exact readback" : [NSString stringWithFormat:@"FAILED: write/readback error %@", A18Err(writeErr)];
                    int rem = unlink(marker.fileSystemRepresentation);
                    result[@"cleanup"] = rem == 0 ? @"PASS: temporary marker removed" : [NSString stringWithFormat:@"FAILED: %@", A18Err(errno)];
                }
            }
        }
    } @finally {
        worse_query_release(handle);
    }
    return result;
}
