#import <UIKit/UIKit.h>

@interface AKTouchAction : NSObject
@property(nonatomic, copy) NSString *identifier, *button;
@property(nonatomic, copy) NSString *groupIdentifier;
@property(nonatomic) NSUInteger modifiers;
@property(nonatomic) CGPoint position;
@property(nonatomic) CGFloat diameter;
@property(nonatomic) BOOL enabled;
@property(nonatomic, readonly) NSString *label;
@end

@interface AKTouchActionLayout : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property(nonatomic) BOOL enabled;
@property(nonatomic) CGFloat scale, borderOpacity;
@property(nonatomic) CGPoint center;
@property(nonatomic, readonly) NSArray<AKTouchAction *> *actions;
- (CGFloat)unitScaleInBounds:(CGRect)bounds;
// Convert a reference offset from the layout's center (640,700 in the photo).
- (CGPoint)pointForPosition:(CGPoint)position inBounds:(CGRect)bounds;
- (CGRect)frameForAction:(AKTouchAction *)action inBounds:(CGRect)bounds;
- (void)moveGroupBy:(CGPoint)delta inBounds:(CGRect)bounds;
- (void)moveAction:(AKTouchAction *)action by:(CGPoint)delta inBounds:(CGRect)bounds;
- (NSArray<AKTouchAction *> *)groupForAction:(AKTouchAction *)action;
- (void)moveButtonGroupForAction:(AKTouchAction *)action by:(CGPoint)delta inBounds:(CGRect)bounds;
- (void)resizeButtonGroupForAction:(AKTouchAction *)action diameter:(CGFloat)diameter inBounds:(CGRect)bounds;
- (AKTouchAction *)addAction;
- (void)removeAction:(AKTouchAction *)action;
- (void)reset;
- (void)save;
@end
