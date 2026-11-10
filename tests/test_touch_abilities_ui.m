#import "../translation/AppKit/TouchGamepad.h"
#import "../translation/AppKit/TouchActionOverlay.h"
#include <assert.h>
#include <math.h>
static UIView *Find(UIView *view,NSString *identifier) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *v in view.subviews) { UIView *found=Find(v,identifier); if (found) return found; } return nil;
}
static void Drain(void) { CFRunLoopRunInMode(kCFRunLoopDefaultMode,.12,false); }
static void Tap(UIView *host,NSString *identifier) {
    UIControl *control=(id)Find(host,identifier); assert(control); [control sendActionsForControlEvents:UIControlEventTouchUpInside];
}
@interface AKAbilityTestPan : UIPanGestureRecognizer
@property CGPoint movement;
@property UIGestureRecognizerState phase;
@end
@implementation AKAbilityTestPan
- (CGPoint)translationInView:(UIView *)view { (void)view; return self.movement; }
- (void)setTranslation:(CGPoint)p inView:(UIView *)view { (void)view; self.movement=p; }
- (UIGestureRecognizerState)state { return self.phase; }
@end
@interface AKTouchActionOverlay (Fixture)
- (void)drag:(UIPanGestureRecognizer *)pan;
- (void)resetLayout;
@end
static void Capture(UIView *host,NSString *name) {
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat]; format.scale=1;
    UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:host.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [host.layer renderInContext:ctx.CGContext];
    }];
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    [UIImagePNGRepresentation(image) writeToFile:[documents stringByAppendingPathComponent:name] atomically:YES];
}
@interface AKAbilityTouch : UITouch
@property CGPoint point;
@property(nonatomic,weak) UIView *reference;
@end
@implementation AKAbilityTouch
- (CGPoint)locationInView:(UIView *)view { return [self.reference convertPoint:self.point toView:view]; }
@end
static AKAbilityTouch *StartCircle(UIControl *circle,UIView *host) {
    AKAbilityTouch *touch=[AKAbilityTouch new]; touch.reference=host;
    touch.point=[circle convertPoint:CGPointMake(circle.bounds.size.width/2,circle.bounds.size.height/2) toView:host];
    assert([circle beginTrackingWithTouch:touch withEvent:nil]); return touch;
}
static void CircleTap(UIControl *circle,UIView *host) {
    AKAbilityTouch *touch=StartCircle(circle,host); [circle endTrackingWithTouch:touch withEvent:nil];
}
void TestTouchAbilitiesUI(UIView *host,AKTouchGamepad *manager,GCVirtualController *controller) {
    for (NSString *key in @[@"WolkaraTouchAbilitiesV1",@"WolkaraTouchAbilitiesV2.full",@"WolkaraTouchAbilitiesV2.simple"])
        [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    [manager toggleSettings]; Tap(host,@"wolkara.controls.abilities");
    assert(manager.configuring && manager.editing);
    UIControl *first=(id)Find(host,@"wolkara.ability.0.up"); assert(first);
    AKTouchActionOverlay *overlay=(id)first.superview;
    Tap(host,@"wolkara.abilities.reset"); first=(id)Find(host,@"wolkara.ability.0.up"); [overlay layoutIfNeeded];
    UISwitch *enabled=(id)Find(host,@"wolkara.abilities.enabled"); enabled.on=YES;
    [enabled sendActionsForControlEvents:UIControlEventValueChanged];
    GCExtendedGamepad *pad=controller.controller.extendedGamepad;
    AKAbilityTouch *editingTouch=[AKAbilityTouch new];
    assert(![first beginTrackingWithTouch:editingTouch withEvent:nil]); assert(!pad.dpad.up.pressed);
    UISlider *size=(id)Find(host,@"wolkara.abilities.size");
    CGRect before=first.frame; size.value=1.3; [size sendActionsForControlEvents:UIControlEventValueChanged]; [overlay layoutIfNeeded];
    assert(fabs(first.frame.size.width/before.size.width-1.3)<.01);
    AKAbilityTestPan *pan=[AKAbilityTestPan new]; [first addGestureRecognizer:pan]; pan.phase=UIGestureRecognizerStateBegan;
    pan.movement=CGPointMake(12,-10); CGPoint old=overlay.layout.center; [overlay drag:pan];
    assert(overlay.layout.center.x>old.x && overlay.layout.center.y<old.y);
    UISegmentedControl *mode=(id)Find(host,@"wolkara.abilities.mode"); assert(mode.numberOfSegments==3);
    mode.selectedSegmentIndex=1; [mode sendActionsForControlEvents:UIControlEventValueChanged];
    NSMutableArray *positions=[NSMutableArray new];
    for (AKTouchAction *action in overlay.layout.actions) [positions addObject:[NSValue valueWithCGPoint:action.position]];
    pan.movement=CGPointMake(10,5); [overlay drag:pan];
    for (NSUInteger i=0;i<overlay.layout.actions.count;i++)
        assert(CGPointEqualToPoint(overlay.layout.actions[i].position,[positions[i] CGPointValue])==(i>=4));
    CGFloat oldSize=overlay.layout.actions[0].diameter;
    size.value=oldSize*1.2; [size sendActionsForControlEvents:UIControlEventValueChanged];
    assert(fabs(overlay.layout.actions[0].diameter-oldSize*1.2)<.01);
    assert(overlay.layout.actions[4].diameter==42);
    Capture(host,@"abilities-editor.png");
    mode.selectedSegmentIndex=2; [mode sendActionsForControlEvents:UIControlEventValueChanged];
    CGPoint other=overlay.layout.actions[1].position,position=overlay.layout.actions[0].position;
    pan.movement=CGPointMake(10,5); [overlay drag:pan];
    assert(!CGPointEqualToPoint(position,overlay.layout.actions[0].position)); assert(CGPointEqualToPoint(other,overlay.layout.actions[1].position));
    size.value=65; [size sendActionsForControlEvents:UIControlEventValueChanged]; assert(overlay.layout.actions[0].diameter==65);
    [first removeGestureRecognizer:pan];
    Tap(host,@"wolkara.abilities.done"); assert(!manager.configuring && !manager.editing);
    AKTouchActionLayout *saved=[[AKTouchActionLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    assert(saved.enabled && saved.actions[0].diameter==65 && [saved groupForAction:saved.actions[0]].count==4);
    // Real tracking, not sendActions: holding/jitter cannot press a modifier.
    // Only lifting a tap commits one chord; dragging and returning is sticky.
    for (AKTouchAction *action in overlay.layout.actions) {
        UIControl *circle=(id)Find(host,[@"wolkara.ability." stringByAppendingString:action.identifier]);
        NSDictionary *buttons=@{@"A":pad.buttonA,@"B":pad.buttonB,@"X":pad.buttonX,@"Y":pad.buttonY,
            @"up":pad.dpad.up,@"right":pad.dpad.right,@"down":pad.dpad.down,@"left":pad.dpad.left};
        GCControllerButtonInput *target=buttons[action.button];
        __block NSUInteger downs=0,ups=0,modifierDowns=0,modifierUps=0;
        GCControllerButtonValueChangedHandler modifier=^(GCControllerButtonInput *button,float value,BOOL pressed) {
            (void)button; (void)value; assert(!target.pressed);
            if (pressed) modifierDowns++; else modifierUps++;
        };
        pad.leftTrigger.pressedChangedHandler=modifier; pad.rightTrigger.pressedChangedHandler=modifier;
        target.pressedChangedHandler=^(GCControllerButtonInput *button,float value,BOOL pressed) {
            (void)button; (void)value;
            assert(pad.leftTrigger.pressed==!!(action.modifiers&1)); assert(pad.rightTrigger.pressed==!!(action.modifiers&2));
            if (pressed) downs++; else ups++;
        };
        AKAbilityTouch *touch=StartCircle(circle,host); Drain();
        assert(!downs && !modifierDowns && !target.pressed && !pad.leftTrigger.pressed && !pad.rightTrigger.pressed);
        touch.point=CGPointMake(touch.point.x+2,touch.point.y+1); [circle continueTrackingWithTouch:touch withEvent:nil];
        [circle endTrackingWithTouch:touch withEvent:nil]; Drain(); Drain();
        assert(downs==1 && ups==1);
        NSUInteger modifiers=!!(action.modifiers&1)+!!(action.modifiers&2);
        assert(modifierDowns==modifiers && modifierUps==modifiers);
        // A fast tap uses exactly the same delivery phases.
        CircleTap(circle,host); Drain(); Drain(); assert(downs==2 && ups==2);
        touch=StartCircle(circle,host); CGPoint origin=touch.point; Drain();
        touch.point=CGPointMake(origin.x+18,origin.y+10); [circle continueTrackingWithTouch:touch withEvent:nil];
        touch.point=origin; [circle continueTrackingWithTouch:touch withEvent:nil];
        [circle endTrackingWithTouch:touch withEvent:nil]; Drain();
        assert(downs==2 && ups==2 && modifierDowns==2*modifiers && modifierUps==2*modifiers);
        touch=StartCircle(circle,host); [circle cancelTrackingWithEvent:nil];
        [circle endTrackingWithTouch:touch withEvent:nil]; Drain(); assert(downs==2);
        target.pressedChangedHandler=nil; pad.leftTrigger.pressedChangedHandler=nil; pad.rightTrigger.pressedChangedHandler=nil;
    }
    // Shoulder bindings use the real controller in simple mode too. Retain
    // manual ownership if the physical on-screen shoulder overlaps a circle tap.
    AKTouchAction *mapped=overlay.layout.actions[0]; NSString *oldButton=mapped.button;
    NSUInteger oldModifiers=mapped.modifiers;
    for (NSString *name in @[@"LB",@"RB"]) {
        manager.simple=YES;
        mapped=overlay.layout.actions[0]; mapped.button=name;
        overlay.layout.enabled=YES;
        first=(id)Find(host,@"wolkara.ability.0.up");
        GCControllerButtonInput *target=[name isEqual:@"LB"] ? pad.leftShoulder : pad.rightShoulder;
        NSString *element=[name isEqual:@"LB"] ? GCInputLeftShoulder : GCInputRightShoulder;
        for (NSUInteger mod=0;mod<4;mod++) {
            mapped.modifiers=mod; [host layoutIfNeeded];
            __block NSUInteger presses=0;
            target.pressedChangedHandler=^(GCControllerButtonInput *button,float value,BOOL pressed) {
                (void)button; (void)value;
                assert(pad.leftTrigger.pressed==!!(mod&1) && pad.rightTrigger.pressed==!!(mod&2));
                if (pressed) presses++;
            };
            CircleTap(first,host); Drain(); Drain();
            assert(presses==1 && !target.pressed); target.pressedChangedHandler=nil;
        }
        manager.simple=NO;
        mapped=overlay.layout.actions[0]; mapped.button=name; mapped.modifiers=0;
        first=(id)Find(host,@"wolkara.ability.0.up"); [host layoutIfNeeded];
        CircleTap(first,host);
        UIControl *manual=(id)Find(host,[@"tolkara.gamepad." stringByAppendingString:element]);
        [manual sendActionsForControlEvents:UIControlEventTouchDown]; Drain(); Drain();
        assert(target.pressed); // Ending the circle must not release the manual owner.
        [manual sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain(); assert(!target.pressed);
    }
    mapped.button=oldButton; mapped.modifiers=oldModifiers;
    manager.simple=YES; [host layoutIfNeeded]; Capture(host,@"controller-simple.png");
    manager.simple=NO;
    // Settings cancel both a candidate touch and a committed but pending tap.
    UIControl *pending=(id)Find(host,@"wolkara.ability.1.X");
    __block NSUInteger latePresses=0;
    pad.buttonX.pressedChangedHandler=^(GCControllerButtonInput *button,float value,BOOL pressed) {
        (void)button; (void)value; if (pressed) latePresses++;
    };
    AKAbilityTouch *resizedTouch=StartCircle(pending,host); CGRect originalBounds=overlay.bounds;
    overlay.bounds=CGRectInset(originalBounds,2,2); [overlay layoutSubviews];
    [pending endTrackingWithTouch:resizedTouch withEvent:nil]; Drain(); assert(!latePresses);
    overlay.bounds=originalBounds; [overlay layoutSubviews];
    AKAbilityTouch *touch=StartCircle(pending,host); [manager toggleSettings];
    [pending endTrackingWithTouch:touch withEvent:nil]; Drain(); assert(!latePresses);
    [manager toggleSettings]; CircleTap(pending,host); [manager toggleSettings]; Drain();
    assert(!latePresses && !pad.leftTrigger.pressed && !pad.buttonX.pressed); [manager toggleSettings];
    UIControl *lt=(id)Find(host,[@"tolkara.gamepad." stringByAppendingString:GCInputLeftTrigger]);
    UIControl *rt=(id)Find(host,[@"tolkara.gamepad." stringByAppendingString:GCInputRightTrigger]);
    [lt sendActionsForControlEvents:UIControlEventTouchDown]; Drain(); CircleTap(pending,host); Drain();
    assert(latePresses==1 && pad.leftTrigger.pressed && !pad.buttonX.pressed);
    [lt sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain();
    [rt sendActionsForControlEvents:UIControlEventTouchDown]; CircleTap(pending,host); Drain();
    assert(latePresses==1 && pad.rightTrigger.pressed && !pad.leftTrigger.pressed);
    assert(pending.layer.borderWidth==2); // A rejected tap remains visibly marked.
    [rt sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain(); pad.buttonX.pressedChangedHandler=nil;
    AKTouchActionOverlay *preview=[[AKTouchActionOverlay alloc] initWithFrame:CGRectMake(0,0,1280,900)];
    [preview resetLayout]; preview.layout.enabled=YES; preview.layout.borderOpacity=.7; preview.active=YES; [preview layoutIfNeeded];
    UIView *canvas=[[UIView alloc] initWithFrame:preview.bounds];
    NSString *reference=[NSBundle.mainBundle pathForResource:@"Reference" ofType:@"jpg"];
    if (reference) { UIImageView *background=[[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:reference]]; background.frame=canvas.bounds; [canvas addSubview:background]; }
    [canvas addSubview:preview]; Capture(canvas,@"abilities-reference.png");
    overlay.layout.enabled=NO; [overlay.layout save]; overlay.active=NO;
    puts("TOUCH_ABILITIES_UI_PASS: three edit modes, independent groups, persistence, 32 tap-on-lift and quick-tap sequences, no input during hold/drag/cancel, manual ownership and settings cancellation.");
}
