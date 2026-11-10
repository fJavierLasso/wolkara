#import <UIKit/UIKit.h>

// Posted after saving; the object is the defaults store that changed.
FOUNDATION_EXPORT NSNotificationName const AKGamepadLayoutDidChangeNotification;

// Preferences contain only UI appearance/feedback; never controller or game state.
@interface AKGamepadLayout : NSObject
// The convenience initializer reads the selected controller mode.
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults simple:(BOOL)simple;
@property(nonatomic, readonly) BOOL simple;
@property(nonatomic) CGFloat opacity;
@property(nonatomic) CGFloat rearScale;
@property(nonatomic) CGFloat frontScale;
@property(nonatomic) BOOL hapticsEnabled;
// Swap the visual shoulder slots only; controller element identities are unchanged.
@property(nonatomic) BOOL swapShoulders;
// Global across both layouts: whether the optional performance HUD is shown. Off by default; the in-game
// settings page and the launcher's Performance & UI row both write it, so the
// preference has one home and one meaning.
@property(nonatomic) BOOL performanceOverlayEnabled;
- (CGRect)frameForItem:(NSString *)item defaultFrame:(CGRect)frame inBounds:(CGRect)bounds;
- (void)moveItem:(NSString *)item toFrame:(CGRect)frame inBounds:(CGRect)bounds;
// Toolbar positions use fixed point offsets; top/bottom groups keep their edge
// distances and each group's spacing as the window resizes.
- (NSDictionary<NSString *,NSValue *> *)framesForToolbar:(NSDictionary<NSString *,NSValue *> *)defaults inBounds:(CGRect)bounds;
- (void)moveToolbarItem:(NSString *)item toFrame:(CGRect)frame currentFrames:(NSDictionary<NSString *,NSValue *> *)frames inBounds:(CGRect)bounds;
- (void)save;
- (void)reset;
@end
