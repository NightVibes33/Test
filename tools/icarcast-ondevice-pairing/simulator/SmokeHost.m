// Separate simulator executable proves the in-app button appears and the logger runs.
#import <UIKit/UIKit.h>
extern void CCLogEvent(NSString *format, ...);
@interface CCOnDeviceSmoke : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation CCOnDeviceSmoke
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    (void)app;(void)opts;
    UIWindow *window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller=[UIViewController new];
    controller.view.backgroundColor=UIColor.systemBackgroundColor;
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(20,120,UIScreen.mainScreen.bounds.size.width-40,150)];
    label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;
    label.text=@"iCarCast Pairing UI Smoke Test\nNot the CarPlay receiver";
    [controller.view addSubview:label];
    window.rootViewController=controller;[window makeKeyAndVisible];self.window=window;
    CCLogEvent(@"PAIRING_SIMULATOR_HOST_STARTED (NOT genuine CarPlay)");
    return YES;
}
@end
int main(int argc, char **argv){@autoreleasepool{
    return UIApplicationMain(argc,argv,nil,NSStringFromClass(CCOnDeviceSmoke.class));
}}
