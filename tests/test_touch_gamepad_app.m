// Original fixture: tests our lifecycle with fake transports, then permits
// manual testing of Apple's real virtual controller. No game or network.
#import <UIKit/UIKit.h>
#import "../translation/AppKit/TouchGamepad.h"
#import "../translation/AppKit/TouchGamepadLayout.h"
#import "../translation/AppKit/TouchHaptics.h"
#import "../translation/AppKit/TouchStickButtons.h"
#include <assert.h>
#include <math.h>
#import <objc/runtime.h>

@interface AKTouchGamepad (FixtureSeams)
- (NSArray<GCController *> *)connectedControllers;
- (GCVirtualController *)makeController;
- (AKTouchHaptics *)makeHaptics;
- (void)clickStick:(BOOL)left;
@end
@interface AKTouchHaptics (FixtureSeams)
- (void)emitImpact:(BOOL)limit;
@end
@interface AKFixtureHaptics : AKTouchHaptics
@property NSUInteger buttons;
@property NSUInteger limits;
@end
@implementation AKFixtureHaptics
- (void)emitImpact:(BOOL)limit { if (limit) self.limits++; else self.buttons++; }
@end

static void TestHaptics(void) {
    AKFixtureHaptics *haptics=[AKFixtureHaptics new];
    [haptics buttonPressed]; [haptics stickMoved:CGPointMake(1,0) left:YES];
    assert(!haptics.buttons && !haptics.limits);
    haptics.enabled=YES; [haptics buttonPressed]; assert(haptics.buttons==1);
    [haptics stickMoved:CGPointMake(.7,.7) left:YES]; assert(!haptics.limits);
    [haptics stickMoved:CGPointMake(sqrt(.5),sqrt(.5)) left:YES]; assert(haptics.limits==1);
    // Holding, sliding around the edge and small radial jitter do not repeat.
    for (NSUInteger i=0; i<100; i++) {
        [haptics stickMoved:CGPointMake(.98,0) left:YES];
        [haptics stickMoved:CGPointMake(0,1) left:YES];
    }
    assert(haptics.limits==1);
    [haptics stickMoved:CGPointMake(0,-1) left:NO]; assert(haptics.limits==2);
    [haptics stickMoved:CGPointMake(.84,0) left:YES];
    [haptics stickMoved:CGPointMake(1,0) left:YES]; assert(haptics.limits==3);
    [haptics reset];
    [haptics stickMoved:CGPointMake(1,0) left:YES];
    [haptics stickMoved:CGPointMake(1,0) left:NO]; assert(haptics.limits==5);
    haptics.enabled=NO;
    [haptics buttonPressed]; [haptics stickMoved:CGPointZero left:YES];
    [haptics stickMoved:CGPointMake(1,0) left:YES];
    assert(haptics.buttons==1 && haptics.limits==5);
    haptics.enabled=YES;
    [haptics stickMoved:CGPointMake(NAN,0) left:YES];
    [haptics stickMoved:CGPointMake(INFINITY,0) left:NO]; assert(haptics.limits==5);
    [haptics stickMoved:CGPointMake(1,0) left:YES]; assert(haptics.limits==6);
    puts("TOUCH_HAPTICS_PASS: independent stick edges, held/jitter suppression, inward rearm, cancellation and disabled feedback.");
}
@interface AKFixtureController : NSObject
@property BOOL isSnapshot;
@property id extendedGamepad;
@property id microGamepad;
@end
@implementation AKFixtureController
@end
@interface AKFixtureConnection : NSObject
@property GCController *controller;
@property(copy) void (^reply)(NSError *);
@property NSUInteger disconnects;
- (void)finish:(NSError *)error;
@end
@implementation AKFixtureConnection
- (void)connectWithReplyHandler:(void (^)(NSError *))reply { self.reply=reply; }
- (void)disconnect { self.disconnects++; self.controller=nil; }
- (void)finish:(NSError *)error {
    if (!error) {
        AKFixtureController *controller=[AKFixtureController new]; controller.extendedGamepad=@YES;
        self.controller=(id)controller;
    }
    void (^reply)(NSError *)=self.reply; self.reply=nil; reply(error);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.03,false);
}
@end
@interface AKFixtureGamepad : AKTouchGamepad
@property NSArray<GCController *> *devices;
@property AKFixtureConnection *lastConnection;
@property NSUInteger connections;
@end
@implementation AKFixtureGamepad
- (NSArray<GCController *> *)connectedControllers { return self.devices?:@[]; }
- (GCVirtualController *)makeController {
    self.connections++; self.lastConnection=[AKFixtureConnection new]; return (id)self.lastConnection;
}
@end

// The simulator can forward a host controller after lazy discovery. This
// fixture-only option still uses Apple's real controller, but lets us inspect it
// without disconnecting the user's hardware. Production always prioritizes it.
@interface AKPreviewGamepad : AKTouchGamepad
@property GCVirtualController *created;
@property BOOL clicksAtConnection;
@property id connectionObserver;
@property AKFixtureHaptics *feedback;
@end
@implementation AKPreviewGamepad
- (AKTouchHaptics *)makeHaptics { self.feedback=[AKFixtureHaptics new]; return self.feedback; }
- (GCVirtualController *)makeController {
    __weak AKPreviewGamepad *weakSelf = self;
    self.connectionObserver = [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidConnectNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        AKPreviewGamepad *self = weakSelf;
        if (self && note.object == self.created.controller) {
            GCController *controller = note.object;
            self.clicksAtConnection = controller.extendedGamepad.leftThumbstickButton != nil &&
                controller.physicalInputProfile.buttons[GCInputRightThumbstickButton] != nil;
            [NSNotificationCenter.defaultCenter removeObserver:self.connectionObserver]; self.connectionObserver = nil;
        }
    }];
    self.created=[super makeController]; return self.created;
}
- (NSArray<GCController *> *)connectedControllers {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--ignore-other-controllers"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"]) return @[];
    return [super connectedControllers];
}
@end


static UIView *Find(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *child in view.subviews) { UIView *found=Find(child,identifier); if (found) return found; }
    return nil;
}
static UIControl *Button(UIView *host, NSString *name) {
    UIControl *control=(id)Find(host,[@"tolkara.gamepad." stringByAppendingString:name]);
    assert(control && !control.hidden); return control;
}
static void Drain(void) { CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.03,false); }
@interface AKFixtureTouch : UITouch
@property CGPoint point;
@property(nonatomic,weak) UIView *targetView;
@property UITouchType inputType;
@end
@implementation AKFixtureTouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.point; }
- (UIView *)view { return self.targetView; }
- (UITouchType)type { return self.inputType; }
@end
@interface AKFixturePan : UIPanGestureRecognizer
@property CGPoint movement;
@property UIGestureRecognizerState testState;
@end
@implementation AKFixturePan
- (CGPoint)translationInView:(UIView *)view { (void)view; return self.movement; }
- (UIGestureRecognizerState)state { return self.testState; }
@end
@interface UIView (LayoutFixture)
- (void)drag:(UIPanGestureRecognizer *)pan;
@end
static void TestPreferences(void) {
    NSString *suite=[@"org.tolkara.layout-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
    // Existing installations keep layout, opacity, size and haptic settings.
    [defaults setObject:@{@"opacity":@0.6,@"rearScale":@1.2,@"frontScale":@0.9,
        @"hapticsEnabled":@NO,@"positions":@{@"menu":@[@0.5,@0.5]}} forKey:@"WowkaraTouchLayoutV1"];
    AKGamepadLayout *migrated=[[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(fabs(migrated.opacity-.6)<.001 && fabs(migrated.rearScale-1.2)<.001 &&
           fabs(migrated.frontScale-.9)<.001 && !migrated.hapticsEnabled);
    assert([defaults dictionaryForKey:@"WolkaraForeverTouchLayoutV1"] && !migrated.swapShoulders);
    CGRect migratedFrame=[migrated frameForItem:@"menu" defaultFrame:CGRectMake(0,0,100,100) inBounds:CGRectMake(0,0,500,300)];
    assert(CGRectEqualToRect(migratedFrame,CGRectMake(200,100,100,100)));
    migrated.opacity=.3;[migrated save];
    assert(fabs([[AKGamepadLayout alloc] initWithDefaults:defaults].opacity-.3)<.001);
    // Explicit current values (even malformed ones) must not resurrect old values.
    [defaults setObject:@{@"opacity":@"bad",@"rearScale":@99,@"frontScale":@(-2),
        @"positions":@{@"broken":@[@"x",@0],@"left":@[@(-1),@4]}} forKey:@"WolkaraForeverTouchLayoutV1"];
    AKGamepadLayout *layout=[[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(layout.opacity==0.8 && layout.rearScale==1.5 && layout.frontScale==0.65 && layout.hapticsEnabled);
    layout.opacity=NAN; layout.rearScale=INFINITY; layout.frontScale=-INFINITY;
    assert(layout.opacity==0.8 && layout.rearScale==1 && layout.frontScale==1);
    CGRect bounds=CGRectMake(20,10,500,300), frame=CGRectMake(200,60,120,120);
    [layout moveItem:@"menu" toFrame:frame inBounds:bounds]; layout.opacity=.4; layout.hapticsEnabled=NO; layout.swapShoulders=NO; [layout save];
    layout=[[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(layout.opacity==.4 && !layout.hapticsEnabled && !layout.swapShoulders);
    assert(CGRectEqualToRect([layout frameForItem:@"menu" defaultFrame:frame inBounds:bounds],frame));
    CGRect small=CGRectMake(0,0,220,120);
    assert(CGRectContainsRect(small,[layout frameForItem:@"menu" defaultFrame:frame inBounds:small]));
    [layout reset]; assert(layout.opacity==.8 && layout.frontScale==1 && layout.hapticsEnabled && layout.swapShoulders);
    assert(CGRectEqualToRect([layout frameForItem:@"menu" defaultFrame:frame inBounds:bounds],frame));
    [defaults removePersistentDomainForName:suite];
}
static BOOL SameFrame(CGRect a, CGRect b) {
    return fabs(a.origin.x-b.origin.x)<.01 && fabs(a.origin.y-b.origin.y)<.01 &&
           fabs(a.size.width-b.size.width)<.01 && fabs(a.size.height-b.size.height)<.01;
}
static void EditShoulders(UIView *host, AKPreviewGamepad *manager, CGPoint movement, BOOL cancel) {
    [manager toggleSettings]; [host layoutIfNeeded];
    UISwitch *edit=(id)Find(host,@"wolkaraforever.controls.edit"); assert(edit);
    edit.on=YES; [edit sendActionsForControlEvents:UIControlEventValueChanged]; [host layoutIfNeeded];
    assert(manager.editing);
    for (NSString *name in @[GCInputLeftShoulder,GCInputRightShoulder]) {
        UIControl *button=Button(host,name); assert(button.enabled);
        CGPoint center=[button convertPoint:CGPointMake(button.bounds.size.width/2,button.bounds.size.height/2) toView:host];
        assert([host hitTest:center withEvent:nil]==button);
        AKFixturePan *pan=[AKFixturePan new]; [button addGestureRecognizer:pan];
        pan.testState=UIGestureRecognizerStateBegan; [button.superview drag:pan];
        pan.movement=CGPointMake([name isEqual:GCInputLeftShoulder]?movement.x:-movement.x,movement.y);
        pan.testState=UIGestureRecognizerStateChanged; [button.superview drag:pan];
        pan.testState=cancel?UIGestureRecognizerStateCancelled:UIGestureRecognizerStateEnded; [button.superview drag:pan];
        [button removeGestureRecognizer:pan];
        assert(!manager.created.controller.physicalInputProfile.buttons[name].pressed);
    }
    [(UIControl *)Find(host,@"wolkaraforever.layout.done") sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(!manager.configuring);
}
static void TestSimpleShoulderPositions(UIView *host, AKPreviewGamepad *manager) {
    GCVirtualController *connection=manager.created;
    UIView *overlay=Button(host,GCInputLeftShoulder).superview;
    NSArray *names=@[GCInputLeftShoulder,GCInputRightShoulder];
    for (NSUInteger swapped=0;swapped<2;swapped++) {
        manager.simple=NO; [manager.layout reset]; manager.layout.swapShoulders=swapped;
        [manager.layout save]; [overlay setNeedsLayout]; [host layoutIfNeeded];
        EditShoulders(host,manager,CGPointMake(10,45),NO);
        CGRect full[2],simple[2];
        for (NSUInteger i=0;i<2;i++) full[i]=Button(host,names[i]).frame;
        manager.simple=YES; [host layoutIfNeeded];
        EditShoulders(host,manager,CGPointMake(35,90),NO);
        for (NSUInteger i=0;i<2;i++) { simple[i]=Button(host,names[i]).frame; assert(!SameFrame(full[i],simple[i])); }
        // Saving/reloading keeps separate keys without changing legacy full slots.
        AKGamepadLayout *saved=[[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        CGRect safe=UIEdgeInsetsInsetRect(overlay.bounds,overlay.safeAreaInsets);
        for (NSUInteger i=0;i<2;i++) {
            NSString *key=i?@"simple.RB":@"simple.LB";
            NSString *fullKey=i?(swapped?@"RT":@"RB"):(swapped?@"LT":@"LB");
            assert(SameFrame([saved frameForItem:key defaultFrame:simple[i] inBounds:safe],simple[i]));
            assert(SameFrame([saved frameForItem:fullKey defaultFrame:full[i] inBounds:safe],full[i]));
            CGRect small=CGRectMake(10,10,300,200);
            assert(CGRectContainsRect(small,[saved frameForItem:key defaultFrame:simple[i] inBounds:small]));
            assert(SameFrame([saved frameForItem:key defaultFrame:simple[i] inBounds:safe],simple[i]));
        }
        EditShoulders(host,manager,CGPointMake(15,15),YES);
        for (NSUInteger i=0;i<2;i++) assert(SameFrame(Button(host,names[i]).frame,simple[i]));
        for (NSUInteger cycle=0;cycle<3;cycle++) {
            manager.simple=NO; [host layoutIfNeeded];
            for (NSUInteger i=0;i<2;i++) assert(SameFrame(Button(host,names[i]).frame,full[i]));
            manager.simple=YES; [host layoutIfNeeded];
            for (NSUInteger i=0;i<2;i++) assert(SameFrame(Button(host,names[i]).frame,simple[i]));
            assert(manager.created==connection && manager.visible);
        }
        manager.simple=NO; [host layoutIfNeeded]; EditShoulders(host,manager,CGPointMake(5,12),NO);
        manager.layout.swapShoulders=!swapped; [manager.layout save];
        manager.simple=YES; [host layoutIfNeeded];
        for (NSUInteger i=0;i<2;i++) assert(SameFrame(Button(host,names[i]).frame,simple[i]));
    }
    manager.simple=NO; [manager.layout reset]; [overlay setNeedsLayout]; [host layoutIfNeeded];
    puts("SIMPLE_SHOULDER_POSITIONS_PASS: independent Full/Simple drags, cancelled edits, save/reload, slot swapping, clamping and same connected controller.");
}
static void TestNativeInput(UIView *host, AKPreviewGamepad *manager) {
    GCExtendedGamepad *pad=manager.created.controller.extendedGamepad;
    assert(pad && manager.visible);
    assert(manager.clicksAtConnection && pad.leftThumbstickButton && pad.rightThumbstickButton);
    GCPhysicalInputProfile *physical = manager.created.controller.physicalInputProfile;
    assert(pad.buttons[GCInputLeftThumbstickButton] == pad.leftThumbstickButton);
    assert(physical[GCInputRightThumbstickButton] == pad.rightThumbstickButton);
    assert([pad.allButtons containsObject:pad.leftThumbstickButton] && [physical.allElements containsObject:pad.rightThumbstickButton]);
    __block NSUInteger presses = 0, releases = 0, profileChanges = 0, physicalChanges = 0;
    pad.leftThumbstickButton.pressedChangedHandler = ^(GCControllerButtonInput *button,float value,BOOL pressed) {
        (void)button; (void)value; if (pressed) presses++; else releases++;
    };
    pad.valueChangedHandler = ^(GCExtendedGamepad *profile,GCControllerElement *element) {
        assert(profile == pad); if (element == pad.leftThumbstickButton) profileChanges++;
    };
    physical.valueDidChangeHandler = ^(GCPhysicalInputProfile *profile,GCControllerElement *element) {
        assert(profile == physical); if (element == pad.leftThumbstickButton) physicalChanges++;
    };
    [manager clickStick:YES]; Drain(); assert(pad.leftThumbstickButton.pressed && !pad.rightThumbstickButton.pressed);
    assert([manager.created.controller capture].extendedGamepad.leftThumbstickButton.pressed);
    assert([(GCExtendedGamepad *)[pad capture] leftThumbstickButton].pressed);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.12,false); assert(!pad.leftThumbstickButton.pressed);
    assert(presses == 1 && releases == 1 && profileChanges == 2 && physicalChanges == 2);
    pad.valueChangedHandler = nil; physical.valueDidChangeHandler = nil; pad.leftThumbstickButton.pressedChangedHandler = nil;
    [manager clickStick:NO]; Drain(); assert(pad.rightThumbstickButton.pressed && !pad.leftThumbstickButton.pressed);
    manager.simple = YES; Drain(); assert(!pad.rightThumbstickButton.pressed);
    [manager clickStick:YES]; [manager toggleSettings]; Drain(); assert(!pad.leftThumbstickButton.pressed);
    [manager clickStick:NO]; Drain(); assert(!pad.rightThumbstickButton.pressed);
    [manager toggleSettings]; manager.simple = NO;
    // Developer snapshots keep their native profiles.
    GCController *snapshot = [GCController controllerWithExtendedGamepad];
    assert(![NSStringFromClass(object_getClass(snapshot.extendedGamepad)) hasPrefix:@"AKClickable_"]);
    [snapshot.extendedGamepad.leftThumbstickButton setValue:1]; assert(snapshot.extendedGamepad.leftThumbstickButton.pressed);
    UITapGestureRecognizer *leftTap = [manager valueForKey:@"_leftDoubleTap"];
    UITapGestureRecognizer *rightTap = [manager valueForKey:@"_rightDoubleTap"];
    UITapGestureRecognizer *areaTap = [manager valueForKey:@"_areaDoubleTap"];
    assert(leftTap.numberOfTapsRequired == 2 && rightTap.numberOfTapsRequired == 2 && areaTap.numberOfTapsRequired == 2);
    assert(!leftTap.delaysTouchesEnded && !leftTap.cancelsTouchesInView && !areaTap.delaysTouchesBegan);
    assert(areaTap.delaysTouchesEnded && areaTap.cancelsTouchesInView); // No mouse click from recognized R3.
    AKFixtureTouch *probe = [AKFixtureTouch new]; probe.targetView = host;
    CGRect safe = UIEdgeInsetsInsetRect(host.bounds,host.safeAreaInsets);
    probe.point = CGPointMake(CGRectGetMidX(safe)+20,CGRectGetMidY(safe)+20);
    assert([areaTap.delegate gestureRecognizer:areaTap shouldReceiveTouch:probe]);
    probe.targetView = leftTap.view; assert(![areaTap.delegate gestureRecognizer:areaTap shouldReceiveTouch:probe]);
    probe.targetView = host; probe.inputType = UITouchTypeIndirectPointer;
    assert(![areaTap.delegate gestureRecognizer:areaTap shouldReceiveTouch:probe]);
    probe.inputType = UITouchTypeDirect; probe.point = CGPointMake(CGRectGetMinX(safe)+10,CGRectGetMinY(safe)+10);
    assert(![areaTap.delegate gestureRecognizer:areaTap shouldReceiveTouch:probe]);
    manager.simple = YES; assert(leftTap.enabled && areaTap.enabled && !rightTap.enabled);
    [manager toggleSettings]; assert(!leftTap.enabled && !areaTap.enabled); [manager toggleSettings]; manager.simple = NO;
    puts("STICK_CLICK_PROFILE_PASS: initial discovery, L3/R3 polling, button/profile callbacks, captures, pulse release, mode/settings cancellation, snapshot isolation and gesture filtering.");
    [host layoutIfNeeded];
    // Ring sectors own their visible area, leave the stick and separator gaps
    // untouched, and put + on the same row as the bottom labels.
    UIButton *top=(id)Button(host,@"dpad.up");
    CALayer *guestSurface=[CALayer layer];
    guestSurface.frame=host.bounds; [host.layer addSublayer:guestSurface];
    assert(top.superview.superview.layer.zPosition > guestSurface.zPosition);
    [guestSurface removeFromSuperlayer];
    assert([top pointInside:CGPointMake(108,26) withEvent:nil]);
    assert(![top pointInside:CGPointMake(108,108) withEvent:nil]);
    assert(![top pointInside:CGPointMake(26,108) withEvent:nil]);
    assert(![top pointInside:CGPointMake(166,50) withEvent:nil]);
    UIButton *a=(id)Button(host,GCInputButtonA), *plus=(id)Button(host,GCInputButtonMenu);
    assert(fabs([a convertPoint:a.titleLabel.center toView:host].y-[plus convertPoint:plus.titleLabel.center toView:host].y)<1);
    assert(Find(host,@"tolkara.gamepad.minus")==nil);
    NSArray *names=@[GCInputButtonA,GCInputButtonB,GCInputButtonX,GCInputButtonY,GCInputLeftShoulder,
        GCInputRightShoulder,GCInputLeftTrigger,GCInputRightTrigger,GCInputButtonMenu];
    for (NSString *name in names) {
        UIControl *button=Button(host,name);
        NSUInteger pulses=manager.feedback.buttons;
        assert(CGRectContainsRect(host.bounds,[button convertRect:button.bounds toView:host]));
        [button sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
        assert(manager.created.controller.physicalInputProfile.buttons[name].value==1);
        assert(manager.feedback.buttons==pulses+1);
        [button sendActionsForControlEvents:UIControlEventTouchDown];
        assert(manager.feedback.buttons==pulses+1); // Still held, no new press.
        [button sendActionsForControlEvents:UIControlEventTouchUpOutside]; Drain();
        assert(manager.created.controller.physicalInputProfile.buttons[name].value==0);
        assert(manager.feedback.buttons==pulses+1); // Releasing is silent.
    }
    UIControl *up=Button(host,@"dpad.up"), *right=Button(host,@"dpad.right"), *left=Button(host,@"dpad.left");
    [up sendActionsForControlEvents:UIControlEventTouchDown];
    [right sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(pad.dpad.xAxis.value==1 && pad.dpad.yAxis.value==1);
    [up sendActionsForControlEvents:UIControlEventTouchCancel]; Drain();
    assert(pad.dpad.xAxis.value==1 && pad.dpad.yAxis.value==0);
    [left sendActionsForControlEvents:UIControlEventTouchDown]; Drain(); assert(pad.dpad.xAxis.value==0);
    [left sendActionsForControlEvents:UIControlEventTouchUpInside];
    [right sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain(); assert(pad.dpad.xAxis.value==0);
    UIControl *leftStick=(id)Find(host,@"tolkara.gamepad.leftStick"), *rightStick=(id)Find(host,@"tolkara.gamepad.rightStick");
    AKFixtureTouch *touch=[AKFixtureTouch new]; touch.point=CGPointMake(leftStick.bounds.size.width,leftStick.bounds.size.height/2);
    assert([leftStick beginTrackingWithTouch:touch withEvent:nil]);
    touch.point=CGPointZero; assert([rightStick beginTrackingWithTouch:touch withEvent:nil]);
    [Button(host,GCInputLeftShoulder) sendActionsForControlEvents:UIControlEventTouchDown];
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(pad.leftThumbstick.xAxis.value==1 && pad.leftThumbstick.yAxis.value==0);
    assert(manager.feedback.limits==2);
    [leftStick continueTrackingWithTouch:touch withEvent:nil]; // Move around rim.
    assert(manager.feedback.limits==2);
    [leftStick cancelTrackingWithEvent:nil];
    [leftStick beginTrackingWithTouch:touch withEvent:nil];
    assert(manager.feedback.limits==3);
    assert(pad.rightThumbstick.xAxis.value < -0.70 && pad.rightThumbstick.yAxis.value > 0.70);
    assert(pad.leftShoulder.pressed && pad.buttonA.pressed);
    // The empty surface continues to belong to the existing trackpad/guest.
    assert([host hitTest:CGPointMake(host.bounds.size.width/2,host.bounds.size.height/2) withEvent:nil]==host);
    GCVirtualController *connection=manager.created;
    CGRect leftFrame=leftStick.superview.frame, rightFrame=rightStick.superview.frame;
    for (NSUInteger cycle=0;cycle<3;cycle++) {
        manager.simple=YES; [host layoutIfNeeded]; Drain();
        assert(manager.created==connection && manager.visible && !manager.configuring);
        assert(!pad.buttonA.pressed && !pad.leftShoulder.pressed && pad.leftThumbstick.xAxis.value==0 && pad.rightThumbstick.yAxis.value==0);
        assert(rightStick.superview.hidden && !leftStick.hidden && !leftStick.superview.hidden);
        for (NSString *name in @[@"dpad.up",@"dpad.right",@"dpad.down",@"dpad.left",GCInputLeftTrigger,GCInputRightTrigger]) {
            UIControl *hidden=(id)Find(host,[@"tolkara.gamepad." stringByAppendingString:name]);
            assert(hidden.hidden && !hidden.enabled);
            CGPoint center=[hidden convertPoint:CGPointMake(hidden.bounds.size.width/2,hidden.bounds.size.height/2) toView:host];
            UIView *hit=[host hitTest:center withEvent:nil]; assert(hit!=hidden && ![hit isDescendantOfView:hidden]);
        }
        for (NSString *name in @[GCInputLeftShoulder,GCInputRightShoulder]) {
            UIControl *shoulder=Button(host,name); assert(shoulder.enabled);
            [shoulder sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
            assert(connection.controller.physicalInputProfile.buttons[name].pressed);
            [shoulder sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain();
            assert(!connection.controller.physicalInputProfile.buttons[name].pressed);
        }
        CGPoint arrow=[top convertPoint:CGPointMake(108,26) toView:host];
        assert([host hitTest:arrow withEvent:nil]==host);
        CGPoint rightCenter=[rightStick convertPoint:CGPointMake(52,52) toView:host];
        assert([host hitTest:rightCenter withEvent:nil]==host);
        touch.point=CGPointMake(leftStick.bounds.size.width,leftStick.bounds.size.height/2);
        [leftStick beginTrackingWithTouch:touch withEvent:nil]; Drain(); assert(pad.leftThumbstick.xAxis.value==1);
        [leftStick cancelTrackingWithEvent:nil]; Drain(); assert(pad.leftThumbstick.xAxis.value==0);
        manager.simple=NO; [host layoutIfNeeded]; Drain();
        assert(manager.created==connection && manager.visible && !rightStick.superview.hidden && !top.hidden);
        assert(CGRectEqualToRect(leftFrame,leftStick.superview.frame) && CGRectEqualToRect(rightFrame,rightStick.superview.frame));
    }
    puts("TOUCH_SIMPLE_MODE_PASS: same controller, neutral axes/buttons, left stick, shoulders and menu, hidden areas pass through, full layout restored.");
    // Entering settings releases held inputs and prevents editing from sending
    // gameplay input. Preferences and dragged positions survive a new model.
    [manager toggleSettings]; [host layoutIfNeeded]; Drain();
    assert(!pad.leftShoulder.pressed && !pad.buttonA.pressed && pad.leftThumbstick.xAxis.value==0);
    UIView *settings=Find(host,@"wolkaraforever.controls.settings"); assert(settings);
    // Settings use a scrollable body with a fixed footer, including on small phones.
    NSMutableArray<UIView *> *settingsControls=[NSMutableArray new];
    for(UIView *view in settings.subviews) {
        assert(CGRectContainsRect(settings.bounds,view.frame));
        assert(CGRectContainsRect(host.bounds,[view convertRect:view.bounds toView:host]));
        if([view isKindOfClass:UIControl.class]) [settingsControls addObject:view];
    }
    for(NSUInteger i=0;i<settingsControls.count;i++) for(NSUInteger j=i+1;j<settingsControls.count;j++)
        assert(!CGRectIntersectsRect(settingsControls[i].frame,settingsControls[j].frame));
    UIView *done=Find(settings,@"wolkaraforever.controls.done"); assert(done);
    CGPoint donePoint=[done convertPoint:CGPointMake(done.bounds.size.width/2,done.bounds.size.height/2) toView:settings];
    assert([settings hitTest:donePoint withEvent:nil]==done);
    CGRect lt=Button(host,GCInputLeftTrigger).frame, lb=Button(host,GCInputLeftShoulder).frame;
    CGRect rt=Button(host,GCInputRightTrigger).frame, rb=Button(host,GCInputRightShoulder).frame;
    UISwitch *swap=(id)Find(host,@"wolkaraforever.controls.swapShoulders"); assert(!swap.on);
    assert(CGRectGetMidX(lt)>CGRectGetMidX(lb) && CGRectGetMidX(rt)<CGRectGetMidX(rb));
    swap.on=YES; [swap sendActionsForControlEvents:UIControlEventValueChanged]; [host layoutIfNeeded];
    assert(CGRectEqualToRect(Button(host,GCInputLeftTrigger).frame,lb));
    assert(CGRectEqualToRect(Button(host,GCInputLeftShoulder).frame,lt));
    assert(CGRectEqualToRect(Button(host,GCInputRightTrigger).frame,rb));
    assert(CGRectEqualToRect(Button(host,GCInputRightShoulder).frame,rt));
    assert(![[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults].swapShoulders);
    NSUInteger silentButtons=manager.feedback.buttons, silentLimits=manager.feedback.limits;
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(!pad.buttonA.pressed);
    assert(!manager.feedback.enabled && manager.feedback.buttons==silentButtons && manager.feedback.limits==silentLimits);
    UISwitch *haptics=(id)Find(host,@"wolkaraforever.controls.haptics"); assert(haptics.on);
    haptics.on=NO; [haptics sendActionsForControlEvents:UIControlEventValueChanged];
    UISlider *scale=(id)Find(host,@"wolkaraforever.controls.frontScale");
    scale.value=1.3; [scale sendActionsForControlEvents:UIControlEventValueChanged]; [host layoutIfNeeded];
    UIView *cluster=Find(host,@"wolkaraforever.layout.left"); assert(cluster.frame.size.width>216);
    UISlider *opacity=(id)Find(host,@"wolkaraforever.controls.transparency");
    opacity.value=.7; [opacity sendActionsForControlEvents:UIControlEventValueChanged];
    assert(fabs(cluster.alpha-.3)<.001);
    UISwitch *edit=(id)Find(host,@"wolkaraforever.controls.edit");
    edit.on=YES; [edit sendActionsForControlEvents:UIControlEventValueChanged]; [host layoutIfNeeded];
    assert(!Find(host,@"wolkaraforever.controls.settings"));
    // Standalone buttons must remain hit-testable for their pan recognizer;
    // disabling them would allow groups to move but trap shoulders and +.
    for (NSString *name in @[GCInputLeftTrigger,GCInputLeftShoulder,GCInputRightTrigger,GCInputRightShoulder,GCInputButtonMenu]) {
        UIControl *button=Button(host,name);
        assert(button.enabled);
        CGPoint center=[button convertPoint:CGPointMake(CGRectGetMidX(button.bounds),CGRectGetMidY(button.bounds)) toView:host];
        assert([host hitTest:center withEvent:nil]==button);
        [button sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
        assert(manager.created.controller.physicalInputProfile.buttons[name].value==0);
        assert(manager.feedback.buttons==silentButtons && manager.feedback.limits==silentLimits);
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        AKFixturePan *buttonPan=[AKFixturePan new]; [button addGestureRecognizer:buttonPan];
        UIView *overlay=button.superview; CGRect original=button.frame;
        buttonPan.testState=UIGestureRecognizerStateBegan; [overlay drag:buttonPan];
        buttonPan.movement=CGPointMake(12,20); buttonPan.testState=UIGestureRecognizerStateChanged; [overlay drag:buttonPan];
        buttonPan.testState=UIGestureRecognizerStateEnded; [overlay drag:buttonPan];
        assert(!CGRectEqualToRect(button.frame,original));
        [button removeGestureRecognizer:buttonPan];
    }
    CGRect before=cluster.frame;
    AKFixturePan *pan=[AKFixturePan new]; [cluster addGestureRecognizer:pan];
    pan.testState=UIGestureRecognizerStateBegan; [cluster.superview drag:pan];
    pan.movement=CGPointMake(120,-40); pan.testState=UIGestureRecognizerStateChanged; [cluster.superview drag:pan];
    pan.testState=UIGestureRecognizerStateEnded; [cluster.superview drag:pan];
    assert(cluster.frame.origin.x>before.origin.x && cluster.frame.origin.y<before.origin.y);
    [cluster removeGestureRecognizer:pan];
    AKGamepadLayout *saved=[[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    assert(fabs(saved.frontScale-1.3)<.001 && fabs(saved.opacity-.3)<.001);
    assert(!saved.hapticsEnabled && !saved.swapShoulders);
    [(UIButton *)Find(host,@"wolkaraforever.layout.done") sendActionsForControlEvents:UIControlEventTouchUpInside];
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(pad.buttonA.pressed && manager.feedback.buttons==silentButtons);
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchUpInside];
    [manager toggleSettings];
    assert(((UISwitch *)Find(host,@"wolkaraforever.controls.swapShoulders")).on);
    [(UIButton *)Find(host,@"wolkaraforever.controls.reset") sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(((UISwitch *)Find(host,@"wolkaraforever.controls.haptics")).on);
    assert(!((UISwitch *)Find(host,@"wolkaraforever.controls.swapShoulders")).on);
    [manager toggleSettings]; [host layoutIfNeeded];
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchDown];
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(manager.feedback.buttons==silentButtons+1 && manager.feedback.enabled);
    assert(fabs(cluster.frame.size.width-216)<.01);
    assert(CGRectGetMidX(Button(host,GCInputLeftTrigger).frame)>CGRectGetMidX(Button(host,GCInputLeftShoulder).frame));
    assert(CGRectGetMidX(Button(host,GCInputRightTrigger).frame)<CGRectGetMidX(Button(host,GCInputRightShoulder).frame));
    TestSimpleShoulderPositions(host,manager);
    TestPreferences();
    manager.keyboardVisible=YES; Drain();
    assert(!manager.visible && !pad.leftShoulder.pressed && !pad.buttonA.pressed);
    assert(!manager.feedback.enabled);
    assert(pad.leftThumbstick.xAxis.value==0 && pad.rightThumbstick.yAxis.value==0);
    [leftStick cancelTrackingWithEvent:nil]; [rightStick cancelTrackingWithEvent:nil];
    [manager invalidate];
    puts("TOUCH_GAMEPAD_INPUT_PASS: all nine buttons, D-pad diagonals/opposition/cancel, both sticks, held modifiers, neutral reset and trackpad passthrough.");
}
static void TestStickMapping(void) {
    CGSize size=CGSizeMake(100,100);
    assert(CGPointEqualToPoint(AKTouchGamepadStickPosition(CGPointMake(50,50),size),CGPointZero));
    assert(CGPointEqualToPoint(AKTouchGamepadStickPosition(CGPointMake(52,50),size),CGPointZero));
    CGPoint value=AKTouchGamepadStickPosition(CGPointMake(500,50),size); assert(value.x==1 && value.y==0);
    value=AKTouchGamepadStickPosition(CGPointMake(0,0),size); assert(fabs(hypot(value.x,value.y)-1)<0.0001 && value.y>0 && value.x<0);
    assert(CGPointEqualToPoint(AKTouchGamepadStickPosition(CGPointMake(NAN,1),size),CGPointZero));
    assert(CGPointEqualToPoint(AKTouchGamepadStickPosition(CGPointZero,CGSizeZero),CGPointZero));
    assert(CGPointEqualToPoint(AKTouchGamepadStickPosition(CGPointMake(CGFLOAT_MAX,CGFLOAT_MAX),CGSizeMake(0.001,0.001)),CGPointZero));
}

static void TestLifecycle(UIView *host) {
    TestStickMapping();
    TestHaptics();
    AKFixtureGamepad *pad=[[AKFixtureGamepad alloc] initWithHostView:host];
    [pad refresh]; assert(pad.connections==1 && !pad.visible);
    AKFixtureController *physical=[AKFixtureController new]; physical.extendedGamepad=@YES;
    pad.devices=@[(id)physical]; [pad refresh];
    [pad.lastConnection finish:nil]; assert(!pad.visible && pad.lastConnection.disconnects);
    pad.devices=@[]; [pad refresh]; [pad.lastConnection finish:nil]; assert(pad.visible);
    // Our own connect event must never be mistaken for physical hardware.
    pad.devices=@[pad.lastConnection.controller];
    [NSNotificationCenter.defaultCenter postNotificationName:GCControllerDidConnectNotification object:pad.lastConnection.controller];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.03,false);
    assert(pad.visible && pad.connections==2);
    pad.devices=@[]; pad.keyboardVisible=YES; assert(!pad.visible && pad.lastConnection.disconnects);
    pad.keyboardVisible=NO; [pad.lastConnection finish:nil]; assert(pad.visible);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    assert(!pad.visible);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    // Keyboard opening while connect is pending cancels a late success.
    pad.keyboardVisible=YES; [pad.lastConnection finish:nil]; assert(!pad.visible);
    NSUInteger count=pad.connections;
    [pad refresh]; assert(pad.connections==count);
    pad.keyboardVisible=NO;
    [pad.lastConnection finish:[NSError errorWithDomain:@"Fixture" code:1 userInfo:nil]];
    assert(!pad.visible); count=pad.connections;
    [pad refresh]; [pad refresh]; assert(pad.connections==count); // no retry loop
    pad.enabled=NO; pad.enabled=YES; [pad.lastConnection finish:nil]; assert(pad.visible);
    [pad toggleSettings]; assert(pad.configuring);
    pad.devices=@[(id)physical]; [pad refresh]; assert(!pad.visible && !pad.configuring);
    physical.isSnapshot=YES; [pad refresh]; [pad.lastConnection finish:nil]; assert(pad.visible);
    host.hidden=YES; [pad refresh]; assert(!pad.visible);
    host.hidden=NO; [pad refresh];
    [pad invalidate]; [pad.lastConnection finish:nil]; assert(!pad.visible);
    count=pad.connections; [pad refresh]; assert(pad.connections==count);
    puts("TOUCH_GAMEPAD_LIFECYCLE_PASS: physical priority, own/snapshot filtering, keyboard/focus cancellation, late replies, failure, retry and teardown.");
}

@interface AKGamepadFixtureScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@property AKTouchGamepad *gamepad;
@property UILabel *status;
@property UILabel *input;
@property NSUInteger events;
@property NSUInteger presses;
@property NSUInteger axisUpdates;
@property BOOL inputTestScheduled;
@end
@implementation AKGamepadFixtureScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *vc=[UIViewController new]; vc.view.backgroundColor=[UIColor colorWithRed:.04 green:.07 blue:.12 alpha:1];
    self.window.rootViewController=vc;
    self.status=[UILabel new]; self.input=[UILabel new];
    for (UILabel *label in @[self.status,self.input]) {
        label.textColor=UIColor.whiteColor; label.numberOfLines=0;
        label.font=[UIFont systemFontOfSize:18]; label.translatesAutoresizingMaskIntoConstraints=NO;
        [vc.view addSubview:label];
    }
    self.status.text=@"Touch controller test · Waiting for activation";
    self.input.text=@"Original input fixture — no game runs here";
    [NSLayoutConstraint activateConstraints:@[
        [self.status.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:68],
        [self.status.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [self.status.widthAnchor constraintLessThanOrEqualToAnchor:vc.view.widthAnchor constant:-100],
        [self.input.topAnchor constraintEqualToAnchor:self.status.bottomAnchor constant:10],
        [self.input.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [self.input.widthAnchor constraintLessThanOrEqualToAnchor:vc.view.widthAnchor constant:-100]
    ]];
    [self.window makeKeyAndVisible];
    [self performSelector:@selector(start) withObject:nil afterDelay:.5];
}
- (void)start {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--unregistered-controller-test"]) {
        GCVirtualControllerConfiguration *config = [GCVirtualControllerConfiguration new]; config.hidden = YES;
        config.elements = [NSSet setWithObjects:GCInputLeftThumbstick,GCInputRightThumbstick,nil];
        GCVirtualController *registered = [[GCVirtualController alloc] initWithConfiguration:config];
        AKRegisterTouchStickButtons(registered); // Install the bridge; this device stays disconnected.
        GCVirtualController *other = [[GCVirtualController alloc] initWithConfiguration:config];
        [other connectWithReplyHandler:^(NSError *error) {
            assert(!error);
            assert(!other.controller.extendedGamepad.leftThumbstickButton);
            assert(![NSStringFromClass(object_getClass(other.controller.physicalInputProfile)) hasPrefix:@"AKClickable_"]);
            [other disconnect]; AKUnregisterTouchStickButtons(registered);
            puts("TOUCH_GAMEPAD_INPUT_PASS: unregistered native controller remains unchanged."); fflush(stdout); exit(0);
        }];
        return;
    }
    BOOL test=[NSProcessInfo.processInfo.arguments containsObject:@"--self-test"];
    if (test || [NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"])
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverTouchLayoutV1"];
    if (test) { TestLifecycle(self.window.rootViewController.view); fflush(stdout); exit(0); }
    self.gamepad=[[AKPreviewGamepad alloc] initWithHostView:self.window.rootViewController.view];
    UIButton *settings=[UIButton buttonWithType:UIButtonTypeSystem];
    [settings setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    settings.accessibilityLabel=@"Touch control settings";
    settings.frame=CGRectMake(self.window.bounds.size.width/2-22,8,44,44);
    settings.layer.zPosition=100001;
    [settings addTarget:self.gamepad action:@selector(toggleSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.window.rootViewController.view addSubview:settings];
    __weak AKGamepadFixtureScene *weakSelf=self;
    self.gamepad.visibilityChanged=^(BOOL visible) {
        weakSelf.status.text=visible?@"Touch controller active":@"Touch controller hidden";
        NSLog(@"VIRTUAL_CONTROLLER_VISIBLE=%d",visible);
        if (visible && [NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"]) {
            if (!weakSelf.inputTestScheduled) {
                weakSelf.inputTestScheduled=YES;
                [weakSelf performSelector:@selector(testInput) withObject:nil afterDelay:0.1];
            }
            return;
        }
        GCController *own=((AKPreviewGamepad *)weakSelf.gamepad).created.controller;
        if (visible) for (GCController *controller in own ? @[own] : @[]) {
            controller.extendedGamepad.valueChangedHandler=^(GCExtendedGamepad *pad, GCControllerElement *element) {
                BOOL press=[element isKindOfClass:GCControllerButtonInput.class] && ((GCControllerButtonInput *)element).isPressed;
                BOOL axis=[element isKindOfClass:GCControllerDirectionPad.class];
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.events++; weakSelf.presses+=press; weakSelf.axisUpdates+=axis;
                    weakSelf.input.text=[NSString stringWithFormat:@"Events %lu · Presses %lu · Axes %lu\nA %.1f · B %.1f · X %.1f · Y %.1f · + %.1f\nL (%.2f, %.2f) · R (%.2f, %.2f) · Pad (%.0f, %.0f)",
                        (unsigned long)weakSelf.events,(unsigned long)weakSelf.presses,(unsigned long)weakSelf.axisUpdates,
                        pad.buttonA.value,pad.buttonB.value,pad.buttonX.value,pad.buttonY.value,
                        pad.buttonMenu.value,
                        pad.leftThumbstick.xAxis.value,pad.leftThumbstick.yAxis.value,
                        pad.rightThumbstick.xAxis.value,pad.rightThumbstick.yAxis.value,pad.dpad.xAxis.value,pad.dpad.yAxis.value];
                });
            };
        }
    };
    NSLog(@"FIXTURE_CONTROLLER_COUNT=%lu",(unsigned long)GCController.controllers.count);
    [self.gamepad refresh];
    [self performSelector:@selector(report) withObject:nil afterDelay:2];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-settings"])
        [self.gamepad performSelector:@selector(toggleSettings) withObject:nil afterDelay:1];
}
- (void)testInput { extern void TestTouchAbilitiesUI(UIView *,AKTouchGamepad *,GCVirtualController *); if (![NSProcessInfo.processInfo.arguments containsObject:@"--stick-clicks-only"]) TestTouchAbilitiesUI(self.window.rootViewController.view,self.gamepad,((AKPreviewGamepad *)self.gamepad).created); TestNativeInput(self.window.rootViewController.view,(id)self.gamepad); fflush(stdout); exit(0); }
- (void)report {
    NSLog(@"FIXTURE_GAMEPAD: active=%d key=%d hidden=%d visible=%d controllers=%lu",UIApplication.sharedApplication.applicationState==UIApplicationStateActive,self.window.isKeyWindow,self.window.hidden,self.gamepad.visible,(unsigned long)GCController.controllers.count);
}
@end
@interface AKGamepadFixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation AKGamepadFixtureApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *config=[[UISceneConfiguration alloc] initWithName:@"Gamepad fixture" sessionRole:session.role];
    config.delegateClass=AKGamepadFixtureScene.class; return config;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL inputTest=[NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"];
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test"] || inputTest)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(inputTest?60:30)*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
                fputs("TOUCH_GAMEPAD_LIFECYCLE_TIMEOUT\n",stderr); _Exit(1);
            });
        return UIApplicationMain(argc,argv,nil,NSStringFromClass(AKGamepadFixtureApp.class));
    }
}
