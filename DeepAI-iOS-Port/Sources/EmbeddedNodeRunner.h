#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface EmbeddedNodeRunner : NSObject
/// Starts Node.js exactly once on a dedicated background thread.
/// Blocking until Node exits; never invoke from the main thread.
+ (int)startScript:(NSString *)script
       workspace:(NSString *)workspace
            home:(NSString *)home
         logFile:(NSString *)logFile;
@end
NS_ASSUME_NONNULL_END
