// Synthetic UIKit touches only; no game is loaded or controlled by this fixture.
#import "AppKit.h"
#import "TouchControls.h"
#import "TouchGamepad.h"
#import "TouchActionOverlay.h"
#include <assert.h>
#include <math.h>
extern CGError CGWarpMouseCursorPosition(CGPoint point);
@interface UIView (CameraPointerFixture)
- (void)moveHoverTo:(CGPoint)point inside:(BOOL)inside;
@end

@interface CameraTouch : UITouch
@property CGPoint point;
@property UITouchPhase testPhase;
@property UITouchType testType;
@property(nonatomic,weak) UIView *host;
@end
@implementation CameraTouch
- (CGPoint)locationInView:(UIView *)view { return self.host ? [self.host convertPoint:self.point toView:view] : self.point; }
- (UITouchPhase)phase { return self.testPhase; }
- (UITouchType)type { return self.testType; }
- (UIView *)view { return self.host; }
@end
@interface CameraEvent : UIEvent
@property(nonatomic,strong) NSSet<UITouch *> *touches;
@property UIEventButtonMask buttons;
@end
@implementation CameraEvent
- (NSSet<UITouch *> *)allTouches { return self.touches; }
- (UIEventButtonMask)buttonMask { return self.buttons; }
- (UIKeyModifierFlags)modifierFlags { return 0; }
- (NSTimeInterval)timestamp { return NSProcessInfo.processInfo.systemUptime; }
@end
static NSEvent *Next(unsigned line) {
    NSEvent *e=[NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES];
    if (!e) { fprintf(stderr,"Missing camera event at fixture line %u\n",line); abort(); } return e;
}
static void Empty(void) {
    assert(![NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES]);
}
static void Warp(CGPoint point) {
    assert(CGWarpMouseCursorPosition(point)==kCGErrorSuccess);
}
static void CheckDelta(NSEvent *e,CGFloat dx,CGFloat dy) {
    if (fabs(e.deltaX-dx)>.001 || fabs(e.deltaY-dy)>.001) {
        fprintf(stderr,"CAMERA_DELTA_MISMATCH expected=(%g,%g) actual=(%g,%g)\n",dx,dy,e.deltaX,e.deltaY);
        abort();
    }
}
static NSEvent *CheckEventAt(NSEventType type, CGPoint point, CGSize size, CGFloat dx, CGFloat dy, unsigned line) {
    NSEvent *e=Next(line);
    assert(e.type==type);
    assert(CGPointEqualToPoint(e.locationInWindow,CGPointMake(point.x,size.height-point.y)));
    CheckDelta(e,dx,dy);
    return e;
}
#define CheckEvent(t,p,s,x,y) CheckEventAt(t,p,s,x,y,__LINE__)
static void Send(UIView *host, CameraEvent *event, CameraTouch *touch, UITouchPhase phase, CGPoint point) {
    touch.point=point; touch.testPhase=phase;
    NSSet *changed=[NSSet setWithObject:touch];
    switch (phase) {
        case UITouchPhaseBegan: [host touchesBegan:changed withEvent:event]; break;
        case UITouchPhaseMoved: [host touchesMoved:changed withEvent:event]; break;
        case UITouchPhaseEnded: [host touchesEnded:changed withEvent:event]; break;
        case UITouchPhaseCancelled: [host touchesCancelled:changed withEvent:event]; break;
        default: abort();
    }
}
static CGPoint CursorMoved(CGPoint anchor, CGFloat dx, CGFloat dy, CGSize size) {
    return CGPointMake(MAX(0,MIN(size.width,anchor.x+dx)), MAX(0,MIN(size.height,anchor.y+dy)));
}
static void CheckPolled(NSWindow *window, CGPoint point, CGSize size) {
    CGPoint local=CGPointMake(point.x,size.height-point.y);
    assert(CGPointEqualToPoint(window.mouseLocationOutsideOfEventStream,local));
    assert(CGPointEqualToPoint(NSEvent.mouseLocation,[window convertPointToScreen:local]));
}
static void CheckCamera(CGSize size, CGPoint start, BOOL right) {
    AKMouseSetCaptured(false);
    NSWindow *window=[[NSWindow alloc] initWithContentRect:(CGRect){CGPointZero,size} styleMask:0 backing:2 defer:NO];
    UIView<AKTouchDragHost> *host=[[NSClassFromString(@"AKHostView") alloc] initWithFrame:(CGRect){CGPointZero,size}];
    [host setValue:window forKey:@"nsWindow"];
    AKTouchControls *controls=[host valueForKey:@"_touchControls"]; controls.trackpadEnabled=NO;
    [host layoutSubviews]; Empty();
    CameraTouch *finger=[CameraTouch new]; finger.host=host;
    CameraEvent *event=[CameraEvent new]; event.touches=[NSSet setWithObject:finger];
    event.buttons=right ? UIEventButtonMaskSecondary : 0;
    NSEventType down=right ? NSEventTypeRightMouseDown : NSEventTypeLeftMouseDown;
    NSEventType drag=right ? NSEventTypeRightMouseDragged : NSEventTypeLeftMouseDragged;
    NSEventType up=right ? NSEventTypeRightMouseUp : NSEventTypeLeftMouseUp;
    CGPoint center=CGPointMake(size.width/2,size.height/2); Warp(center);
    CGPoint anchor=CGPointMake(window.mouseLocationOutsideOfEventStream.x,size.height-window.mouseLocationOutsideOfEventStream.y);
    CGPoint screen=NSEvent.mouseLocation;
    // Touch-down and small jitter never change either polled position or events.
    Send(host,event,finger,UITouchPhaseBegan,start); Empty();
    // A delayed UIKit pointer-region refresh must not re-anchor a new finger.
    [host moveHoverTo:CGPointMake(size.width-2,2) inside:YES]; Empty();
    CheckPolled(window,anchor,size);
    Send(host,event,finger,UITouchPhaseMoved,CGPointMake(start.x+3,start.y+2)); Empty();
    assert(CGPointEqualToPoint(window.mouseLocationOutsideOfEventStream,CGPointMake(anchor.x,size.height-anchor.y)));
    assert(CGPointEqualToPoint(NSEvent.mouseLocation,screen));
    CGPoint moved=CGPointMake(start.x+10,start.y+5);
    Send(host,event,finger,UITouchPhaseMoved,moved);
    assert(CheckEvent(down,anchor,size,0,0).buttonNumber==(right?1:0));
    CheckEvent(drag,CursorMoved(anchor,10,5,size),size,10,5);
    CheckPolled(window,CursorMoved(anchor,10,5,size),size);
    // Capture can arrive late. Relative motion already works before it arrives.
    AKMouseSetCaptured(true); CGPoint edge=CGPointMake(size.width-1,size.height-1); Warp(edge); CheckPolled(window,edge,size);
    Send(host,event,finger,UITouchPhaseMoved,moved); Empty();
    moved=CGPointMake(moved.x+4,moved.y-3);
    Send(host,event,finger,UITouchPhaseMoved,moved); CheckEvent(drag,edge,size,4,-3);
    [host moveHoverTo:CGPointMake(2,2) inside:YES]; Empty(); CheckPolled(window,edge,size);
    CameraTouch *other=[CameraTouch new]; other.host=host;
    event.touches=[NSSet setWithObjects:finger,other,nil];
    Send(host,event,other,UITouchPhaseBegan,CGPointMake(20,20)); Empty();
    Send(host,event,other,UITouchPhaseMoved,CGPointMake(800,500)); Empty();
    Send(host,event,other,UITouchPhaseEnded,CGPointMake(800,500)); Empty();
    AKMouseSetCaptured(false);
    moved=CGPointMake(moved.x-6,moved.y+8);
    edge=CursorMoved(edge,-6,8,size);
    Send(host,event,finger,UITouchPhaseMoved,moved); CheckEvent(drag,edge,size,-6,8);
    Send(host,event,finger,UITouchPhaseEnded,moved); CheckEvent(up,edge,size,0,0); Empty();
    event.touches=[NSSet setWithObject:finger];
    // Lifting and restarting far away must keep the last guest anchor too.
    CGPoint restart=CGPointMake(size.width-start.x,size.height-start.y);
    screen=NSEvent.mouseLocation;
    Send(host,event,finger,UITouchPhaseBegan,restart); Empty(); assert(CGPointEqualToPoint(screen,NSEvent.mouseLocation));
    Send(host,event,finger,UITouchPhaseMoved,CGPointMake(restart.x-12,restart.y-8));
    CheckEvent(down,edge,size,0,0); edge=CursorMoved(edge,-12,-8,size); CheckEvent(drag,edge,size,-12,-8);
    Send(host,event,finger,UITouchPhaseEnded,restart); CheckEvent(up,edge,size,0,0);
    // A tap still clicks its screen position, but only after intent is known.
    Send(host,event,finger,UITouchPhaseBegan,start); Empty();
    CGPoint tap=CGPointMake(start.x+2,start.y+1);
    Send(host,event,finger,UITouchPhaseEnded,tap);
    CheckEvent(NSEventTypeMouseMoved,tap,size,0,0); CheckEvent(down,tap,size,0,0); CheckEvent(up,tap,size,0,0); Empty();
    Send(host,event,finger,UITouchPhaseBegan,start); Empty();
    Send(host,event,finger,UITouchPhaseCancelled,start); Empty();
    // Cancellation after a drag releases once; no stale sample becomes a tap.
    for (unsigned reason=0;reason<4;reason++) {
        Warp(center);
        Send(host,event,finger,UITouchPhaseBegan,start); Empty();
        Send(host,event,finger,UITouchPhaseMoved,moved);
        CGPoint cursor=CursorMoved(center,moved.x-start.x,moved.y-start.y,size);
        CheckEvent(down,center,size,0,0); CheckEvent(drag,cursor,size,moved.x-start.x,moved.y-start.y);
        switch (reason) {
            case 0: [controls cancelTouches]; break;
            case 1: [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil]; break;
            case 2: controls.trackpadEnabled=YES; break;
            case 3: host.bounds=(CGRect){CGPointZero,CGSizeMake(size.width-10,size.height-10)}; [host layoutSubviews]; break;
        }
        CheckEvent(up,cursor,host.bounds.size,0,0); [controls cancelTouches]; Empty();
        Send(host,event,finger,UITouchPhaseMoved,moved); Empty();
        event.touches=[NSSet setWithObjects:finger,other,nil];
        Send(host,event,other,UITouchPhaseBegan,start); Send(host,event,other,UITouchPhaseMoved,moved); Empty();
        Send(host,event,other,UITouchPhaseEnded,moved); Empty();
        event.touches=[NSSet setWithObject:finger]; Send(host,event,finger,UITouchPhaseEnded,moved); Empty();
        controls.trackpadEnabled=NO; host.bounds=(CGRect){CGPointZero,size}; [host layoutSubviews]; Empty();
    }
    // A dropped UIKit end after focus loss cannot poison the next gesture.
    Send(host,event,finger,UITouchPhaseBegan,start); [controls cancelTouches]; Empty();
    event.touches=[NSSet setWithObject:other];
    Send(host,event,other,UITouchPhaseBegan,start); Send(host,event,other,UITouchPhaseCancelled,start); Empty();
    // A real circle tracking gesture hands off to the host, in both mouse modes.
    AKTouchActionOverlay *overlay=[[AKTouchActionOverlay alloc] initWithFrame:host.bounds]; [host addSubview:overlay];
    [overlay.layout reset]; overlay.layout.enabled=YES; overlay.active=YES; [overlay layoutIfNeeded];
    __block NSUInteger presses=0;
    overlay.press=^BOOL(AKTouchAction *a) { (void)a; presses++; return YES; };
    __weak AKTouchActionOverlay *weakOverlay=overlay;
    overlay.beginDrag=^BOOL(UITouch *touch,CGPoint origin) { return [host ak_beginTouchDrag:touch origin:[weakOverlay convertPoint:origin toView:host]]; };
    overlay.moveDrag=^(UITouch *touch) { [host ak_moveTouchDrag:touch]; };
    overlay.endDrag=^(UITouch *touch,BOOL cancelled) { [host ak_endTouchDrag:touch cancelled:cancelled]; };
    UIControl *circle=(id)overlay.subviews.firstObject;
    for (unsigned mouse=0;mouse<2;mouse++) {
        controls.trackpadEnabled=mouse; Warp(center);
        CGPoint origin=[circle convertPoint:CGPointMake(circle.bounds.size.width/2,circle.bounds.size.height/2) toView:host];
        finger.point=origin; assert([circle beginTrackingWithTouch:finger withEvent:nil]); Empty();
        finger.point=CGPointMake(origin.x+12,origin.y+9); [circle continueTrackingWithTouch:finger withEvent:nil];
        if (!mouse) { CheckEvent(NSEventTypeLeftMouseDown,center,size,0,0); CheckEvent(NSEventTypeLeftMouseDragged,CursorMoved(center,12,9,size),size,12,9); }
        else CheckEvent(NSEventTypeMouseMoved,CGPointMake(center.x+12,center.y+9),size,12,9);
        [circle endTrackingWithTouch:finger withEvent:nil];
        if (!mouse) CheckEvent(NSEventTypeLeftMouseUp,CursorMoved(center,12,9,size),size,0,0);
        Empty(); assert(!presses);
    }
    overlay.beginDrag=nil; overlay.moveDrag=nil; overlay.endDrag=nil; [overlay removeFromSuperview];
    controls.trackpadEnabled=NO;
    // Model a client that starts capture only once event positions move.
    // Each new gesture must wake it without needing a controller movement.
    for (unsigned gesture=0;gesture<6;gesture++) {
        AKMouseSetCaptured(false); Warp(center); CheckPolled(window,center,size);
        CGPoint origin=gesture%2 ? CGPointMake(30,40) : CGPointMake(size.width-40,size.height-50);
        Send(host,event,finger,UITouchPhaseBegan,origin); Empty(); CheckPolled(window,center,size);
        CGPoint next=CGPointMake(origin.x+12,origin.y-9);
        Send(host,event,finger,UITouchPhaseMoved,next);
        NSEvent *downEvent=CheckEvent(down,center,size,0,0);
        NSEvent *motion=CheckEvent(drag,CursorMoved(center,12,-9,size),size,12,-9);
        assert(!CGPointEqualToPoint(downEvent.locationInWindow,motion.locationInWindow));
        CheckPolled(window,CursorMoved(center,12,-9,size),size);
        AKMouseSetCaptured(true); Warp(center); CheckPolled(window,center,size);
        next=CGPointMake(next.x+5,next.y+3);
        Send(host,event,finger,UITouchPhaseMoved,next); CheckEvent(drag,center,size,5,3);
        CheckPolled(window,center,size);
        Send(host,event,finger,UITouchPhaseEnded,next); CheckEvent(up,center,size,0,0); Empty();
    }
    // Trackpad and indirect pointer behavior remains unchanged.
    controls.trackpadEnabled=YES; AKMouseSetCaptured(true); Warp(center);
    [(id<AKTouchControlsDelegate>)host touchMoveBy:CGPointMake(9,-4)]; CheckEvent(NSEventTypeMouseMoved,center,size,9,-4);
    AKMouseSetCaptured(false); controls.trackpadEnabled=NO;
    other.testType=UITouchTypeIndirectPointer;
    Send(host,event,other,UITouchPhaseBegan,start); CheckEvent(down,start,size,0,0);
    Send(host,event,other,UITouchPhaseMoved,moved); CheckEvent(drag,moved,size,moved.x-start.x,moved.y-start.y);
    Send(host,event,other,UITouchPhaseEnded,moved); CheckEvent(up,moved,size,0,0); Empty();
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    const CGSize sizes[]={{852,393},{932,430},{951,669},{1194,834}};
    for (unsigned i=0;i<sizeof sizes/sizeof *sizes;i++) {
        CGSize size=sizes[i];
        const CGPoint starts[]={{40,40},{size.width/2,size.height/2},{size.width-30,size.height-30}};
        for (unsigned j=0;j<sizeof starts/sizeof *starts;j++) @autoreleasepool {
            CheckCamera(size,starts[j],j==2);
        }
    }
    puts("DIRECT_TOUCH_CAMERA_PASS");
} return 0; }
