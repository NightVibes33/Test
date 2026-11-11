// This is a *diagnostics component smoke-test host*, not a CarPlay receiver
// and not an iCarCast simulator port (the original app is PLATFORM_IOS only).
#import <UIKit/UIKit.h>
extern void CCLogEvent(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);

@interface CCDiagnosticsHostDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation CCDiagnosticsHostDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)app; (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = UIViewController.new;
    controller.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(18, 150, UIScreen.mainScreen.bounds.size.width-36, 140)];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.text = @"Diagnostic framework simulator smoke test.\\nThis is NOT the original iCarCast app.";
    [controller.view addSubview:label];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    CCLogEvent(@"SIMULATOR_HOST_STARTED (this is not the actual iCarCast app)");
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(CCDiagnosticsHostDelegate.class));
    }
}
