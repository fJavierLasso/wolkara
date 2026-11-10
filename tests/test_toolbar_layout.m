#import "TouchGamepadLayout.h"
#include <assert.h>
#include <math.h>

static NSDictionary *Defaults(CGRect bounds) {
    return @{@"mouse":[NSValue valueWithCGRect:CGRectMake(CGRectGetMidX(bounds)-74,bounds.origin.y,44,44)],
             @"microphone":[NSValue valueWithCGRect:CGRectMake(CGRectGetMidX(bounds)-22,bounds.origin.y,96,44)]};
}
static void CheckSpacing(NSDictionary *frames) {
    CGRect mouse = [frames[@"mouse"] CGRectValue], mic = [frames[@"microphone"] CGRectValue];
    assert(fabs(mic.origin.x-mouse.origin.x-52)<0.001);
    assert(fabs(mic.origin.y-mouse.origin.y)<0.001);
    assert(mouse.size.width==44 && mic.size.width==96);
}
int main(void) { @autoreleasepool {
    NSString *suite = [@"org.tolkara.toolbar-layout-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    AKGamepadLayout *layout = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    CGRect full = CGRectMake(28,8,950,640), side = CGRectMake(8,28,500,420);
    NSDictionary *initial = Defaults(full);
    [layout moveToolbarItem:@"mouse" toFrame:[initial[@"mouse"] CGRectValue] currentFrames:initial inBounds:full];
    [layout save];
    // Real spacing and target sizes survive resizing, different safe insets,
    // repeated round trips and relaunching directly into the smaller window.
    layout = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    for (unsigned i=0; i<3; i++) {
        NSDictionary *resized = [layout framesForToolbar:Defaults(side) inBounds:side];
        CheckSpacing(resized);
        for (NSValue *value in resized.allValues) assert(CGRectContainsRect(side,value.CGRectValue));
        NSDictionary *restored = [layout framesForToolbar:Defaults(full) inBounds:full];
        assert([restored isEqualToDictionary:initial]);
    }
    // Near an edge, both items receive the same translation rather than
    // individually clamping into each other.
    CGRect edge = CGRectOffset([initial[@"mouse"] CGRectValue],380,80);
    NSMutableDictionary *moved = [initial mutableCopy];
    moved[@"microphone"] = [NSValue valueWithCGRect:CGRectOffset([initial[@"microphone"] CGRectValue],380,80)];
    [layout moveToolbarItem:@"mouse" toFrame:edge currentFrames:moved inBounds:full];
    CheckSpacing([layout framesForToolbar:Defaults(side) inBounds:side]);
    // A too-small window uses its fallback without destroying the saved layout.
    NSDictionary *before = [layout framesForToolbar:Defaults(full) inBounds:full];
    CGRect narrow = CGRectMake(0,0,120,180);
    NSDictionary *compact = @{@"mouse":[NSValue valueWithCGRect:CGRectMake(0,0,44,44)],
                              @"microphone":[NSValue valueWithCGRect:CGRectMake(0,52,96,44)]};
    assert([[layout framesForToolbar:compact inBounds:narrow] isEqualToDictionary:compact]);
    assert([[layout framesForToolbar:Defaults(full) inBounds:full] isEqualToDictionary:before]);
    [layout reset];
    assert([[[[AKGamepadLayout alloc] initWithDefaults:defaults] framesForToolbar:initial inBounds:full] isEqualToDictionary:initial]);
    // Legacy normalized coordinates are resolved once and persisted. The
    // reference dimensions were not stored by the former version.
    CGRect legacyMouse = CGRectMake(400,100,44,44), legacyMic = CGRectMake(452,100,96,44);
    [layout moveItem:@"mouse" toFrame:legacyMouse inBounds:full];
    [layout moveItem:@"microphone" toFrame:legacyMic inBounds:full];
    [layout save];
    NSDictionary *migrated = [layout framesForToolbar:initial inBounds:full];
    CheckSpacing(migrated);
    assert(fabs([migrated[@"mouse"] CGRectValue].origin.x-400)<0.001);
    layout = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    CheckSpacing([layout framesForToolbar:Defaults(side) inBounds:side]);
    // The user's toolbar has separate top and bottom groups. A shorter Duo
    // window must retain both rows and their edge distances, not reset the bar.
    [layout reset];
    NSMutableDictionary *twoRows = [Defaults(full) mutableCopy];
    twoRows[@"bottomMouse"] = [NSValue valueWithCGRect:CGRectMake(650,CGRectGetMaxY(full)-44,44,44)];
    twoRows[@"bottomMic"] = [NSValue valueWithCGRect:CGRectMake(702,CGRectGetMaxY(full)-44,96,44)];
    [layout moveToolbarItem:@"mouse" toFrame:[twoRows[@"mouse"] CGRectValue] currentFrames:twoRows inBounds:full];
    [layout save];
    layout = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    NSDictionary *shorter = [layout framesForToolbar:twoRows inBounds:side];
    CGRect bottomMouse = [shorter[@"bottomMouse"] CGRectValue], bottomMic = [shorter[@"bottomMic"] CGRectValue];
    assert(fabs(bottomMic.origin.x-bottomMouse.origin.x-52)<0.001);
    assert(bottomMic.origin.y==bottomMouse.origin.y && CGRectGetMaxY(bottomMic)==CGRectGetMaxY(side));
    assert([shorter[@"mouse"] CGRectValue].origin.y==side.origin.y);
    CheckSpacing(shorter);
    for (NSValue *value in shorter.allValues) assert(CGRectContainsRect(side,value.CGRectValue));
    assert([[layout framesForToolbar:twoRows inBounds:full] isEqualToDictionary:twoRows]);
    [defaults removePersistentDomainForName:suite];
    puts("toolbar layout: fixed spacing, safe-area translation, persistence, legacy migration, compact fallback and reset: PASS");
} }
