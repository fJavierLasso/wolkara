#import <UIKit/UIKit.h>
#import "TouchActionLayout.h"

@interface AKTouchActionOverlay : UIView
@property(nonatomic, readonly) AKTouchActionLayout *layout;
@property(nonatomic, readonly) BOOL editing;
@property(nonatomic) BOOL active;
@property(nonatomic, copy) BOOL (^press)(AKTouchAction *action);
@property(nonatomic, copy) void (^released)(AKTouchAction *action);
@property(nonatomic, copy) void (^cancelledAll)(void);
@property(nonatomic, copy) BOOL (^beginDrag)(UITouch *touch, CGPoint origin);
@property(nonatomic, copy) void (^moveDrag)(UITouch *touch);
@property(nonatomic, copy) void (^endDrag)(UITouch *touch, BOOL cancelled);
@property(nonatomic, copy) void (^configurationChanged)(void);
- (void)selectSimpleLayout:(BOOL)simple;
- (void)beginEditing;
- (void)finishEditing;
- (void)releaseTouches;
- (BOOL)editorContainsPoint:(CGPoint)point inView:(UIView *)view;
@end
