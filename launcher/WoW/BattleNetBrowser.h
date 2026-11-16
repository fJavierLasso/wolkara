#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// No JavaScript bridge, credential fields, automated submissions or TLS overrides.
@interface TKWoWBattleNetBrowser : UIViewController
- (instancetype)initWithRegion:(NSString *)region
    completion:(void (^)(NSString * _Nullable ticket, NSString * _Nullable failure))completion;
@end
NS_ASSUME_NONNULL_END
