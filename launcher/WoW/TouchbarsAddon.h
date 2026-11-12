#import <Foundation/Foundation.h>
#import "AddonStore.h"

NS_ASSUME_NONNULL_BEGIN

// A launcher-only opt-in. The addon remains unchanged and uses ordinary game
// clicks; no native input bridge, bindings or control-profile changes.
@interface TKTouchbarsAddon : NSObject
- (instancetype)initWithStore:(TKAddonStore *)store;
- (void)reload;
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly) BOOL canToggle;
// Worker queue only. First enable downloads a pinned package; subsequent
// toggles use the existing managed copy offline and retain SavedVariables.
- (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
