#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

NS_ASSUME_NONNULL_BEGIN
@class AKGamepadLayout;
enum { AKTouchDragThreshold = 8 };
// Ability circles hand an intentional drag to the host without a gamepad press.
@protocol AKTouchDragHost <NSObject>
- (BOOL)ak_beginTouchDrag:(UITouch *)touch origin:(CGPoint)origin;
- (void)ak_moveTouchDrag:(UITouch *)touch;
- (void)ak_endTouchDrag:(UITouch *)touch cancelled:(BOOL)cancelled;
@end
// Radial analog mapping with a small dead zone and clamped magnitude.
CGPoint AKTouchGamepadStickPosition(CGPoint point, CGSize size);
// Owns only our virtual device. Physical controllers and their handlers stay
// with GameController/the guest. No game events or memory are inspected.
@interface AKTouchGamepad : NSObject
- (instancetype)initWithHostView:(UIView *)host;
@property(nonatomic) BOOL enabled;
/// Selects independent Full/Simple appearance, positions and ability layouts.
/// Keeps the same connected controller and releases any held input.
@property(nonatomic) BOOL simple;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic, readonly) BOOL visible;
@property(nonatomic, readonly) BOOL configuring;
@property(nonatomic, readonly) BOOL editing;
/// Shared with the toolbar so a settings save cannot overwrite moved buttons.
@property(nonatomic, readonly) AKGamepadLayout *layout;
@property(nonatomic, copy, nullable) void (^visibilityChanged)(BOOL visible);
/// Keep Done and the settings sheet reachable even when a toolbar button overlaps.
- (BOOL)configurationContainsPoint:(CGPoint)point inView:(UIView *)view;
- (void)refresh;
- (void)toggleSettings;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
