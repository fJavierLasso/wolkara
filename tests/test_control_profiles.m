#import "TouchGamepadLayout.h"
#import "TouchActionLayout.h"
#include <assert.h>
#include <math.h>

static BOOL Near(CGFloat a,CGFloat b) { return fabs(a-b)<.001; }
static CGRect Frame(AKGamepadLayout *layout,NSString *key) {
    return [layout frameForItem:key defaultFrame:CGRectMake(0,0,50,40) inBounds:CGRectMake(0,0,800,600)];
}
int main(void) { @autoreleasepool {
    NSString *suite=[@"org.wolkara.tests.profiles." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
    NSDictionary *legacy=@{@"opacity":@.6,@"rearScale":@1.2,@"frontScale":@.9,
        @"hapticsEnabled":@NO,@"swapShoulders":@NO,@"performanceOverlayEnabled":@YES,
        @"positions":@{@"left":@[@.1,@.8],@"LB":@[@.2,@.1],@"simple.LB":@[@.4,@.6],@"simple.RB":@[@.7,@.6]},
        @"toolbarPositions":@{@"mouse":@[@(-150),@20,@NO]}};
    [defaults setObject:legacy forKey:@"WolkaraForeverTouchLayoutV1"];
    NSDictionary *legacyAbilities=@{@"enabled":@YES,@"scale":@1.3,@"border":@.3,@"x":@.4,@"y":@.7,
        @"actions":@[@{@"id":@"0.A",@"button":@"A",@"modifiers":@3,@"x":@20,@"y":@(-10),@"diameter":@55,@"enabled":@YES}]};
    [defaults setObject:legacyAbilities forKey:@"WolkaraTouchAbilitiesV1"];
    AKGamepadLayout *full=[[AKGamepadLayout alloc] initWithDefaults:defaults simple:NO];
    assert(!full.simple && Near(full.opacity,.6) && !full.hapticsEnabled && !full.swapShoulders);
    CGRect legacyLeft=Frame(full,@"left"),legacySimpleLB=Frame(full,@"simple.LB");
    assert(Near(legacySimpleLB.origin.x,300));
    NSDictionary *toolbar=@{@"mouse":[NSValue valueWithCGRect:CGRectMake(0,0,44,44)]};
    CGRect bounds=CGRectMake(0,0,800,600);
    NSDictionary *legacyToolbar=[full framesForToolbar:toolbar inBounds:bounds];
    full.opacity=.25; full.frontScale=1.4; full.rearScale=1.5; full.hapticsEnabled=YES; full.swapShoulders=YES;
    [full moveItem:@"left" toFrame:CGRectMake(300,200,50,40) inBounds:bounds];
    [full moveToolbarItem:@"mouse" toFrame:CGRectMake(500,400,44,44) currentFrames:toolbar inBounds:bounds];
    [full save];
    // Visiting Simple for the first time after editing Full must still inherit
    // the user's old settings, not the just-edited profile.
    AKGamepadLayout *simple=[[AKGamepadLayout alloc] initWithDefaults:defaults simple:YES];
    assert(simple.simple && Near(simple.opacity,.6) && Near(simple.rearScale,1.2) && Near(simple.frontScale,.9));
    assert(!simple.hapticsEnabled && !simple.swapShoulders);
    assert(CGRectEqualToRect(Frame(simple,@"left"),legacyLeft));
    assert(CGRectEqualToRect(Frame(simple,@"simple.LB"),legacySimpleLB));
    assert([[simple framesForToolbar:toolbar inBounds:bounds] isEqual:legacyToolbar]);
    simple.opacity=.75; simple.frontScale=.7; simple.rearScale=.8;
    [simple moveItem:@"left" toFrame:CGRectMake(80,300,50,40) inBounds:bounds];
    [simple moveToolbarItem:@"mouse" toFrame:CGRectMake(100,300,44,44) currentFrames:toolbar inBounds:bounds];
    [simple save];
    for (unsigned i=0;i<3;i++) {
        NSUserDefaults *reopened=[[NSUserDefaults alloc] initWithSuiteName:suite];
        full=[[AKGamepadLayout alloc] initWithDefaults:reopened simple:NO];
        simple=[[AKGamepadLayout alloc] initWithDefaults:reopened simple:YES];
        assert(Near(full.opacity,.25) && Near(full.frontScale,1.4) && Near(full.rearScale,1.5));
        assert(full.hapticsEnabled && full.swapShoulders);
        assert(Near(simple.opacity,.75) && Near(simple.frontScale,.7) && Near(simple.rearScale,.8));
        assert(!simple.hapticsEnabled && !simple.swapShoulders);
        assert(Near(Frame(full,@"left").origin.x,300) && Near(Frame(simple,@"left").origin.x,80));
        assert(Near([full framesForToolbar:toolbar inBounds:bounds][@"mouse"].CGRectValue.origin.x,500));
        assert(Near([simple framesForToolbar:toolbar inBounds:bounds][@"mouse"].CGRectValue.origin.x,100));
        [simple save]; [full save];
    }
    [defaults setBool:YES forKey:@"TKTouchGamepadSimple"];
    assert([[AKGamepadLayout alloc] initWithDefaults:defaults].simple);
    assert(Near([[AKGamepadLayout alloc] initWithDefaults:defaults].frontScale,.7));
    // HUD is global, and stale profile saves/resets cannot restore its old state.
    assert(full.performanceOverlayEnabled && simple.performanceOverlayEnabled);
    full.performanceOverlayEnabled=NO; [full save]; [simple save];
    assert(!simple.performanceOverlayEnabled);
    simple.performanceOverlayEnabled=YES; [simple save]; [full reset];
    assert(full.performanceOverlayEnabled && Near(full.frontScale,1));
    assert(Near([[AKGamepadLayout alloc] initWithDefaults:defaults simple:YES].frontScale,.7));
    assert(Near(Frame([[AKGamepadLayout alloc] initWithDefaults:defaults simple:YES],@"left").origin.x,80));

    AKTouchActionLayout *a=[[AKTouchActionLayout alloc] initWithDefaults:defaults simple:NO];
    assert(a.enabled && Near(a.scale,1.3) && a.actions.count==1 && a.actions[0].modifiers==3);
    a.scale=2; a.enabled=NO; a.borderOpacity=.6; a.center=CGPointMake(.6,.5);
    a.actions[0].button=@"LB"; a.actions[0].diameter=80; a.actions[0].enabled=NO; a.actions[0].position=CGPointMake(40,60);
    [a addAction]; [a save];
    AKTouchActionLayout *b=[[AKTouchActionLayout alloc] initWithDefaults:defaults simple:YES];
    assert(b.simple && b.enabled && Near(b.scale,1.3) && Near(b.borderOpacity,.3));
    assert(CGPointEqualToPoint(b.center,CGPointMake(.4,.7)) && b.actions.count==1);
    assert([b.actions[0].button isEqual:@"A"] && b.actions[0].diameter==55 && b.actions[0].enabled);
    assert(CGPointEqualToPoint(b.actions[0].position,CGPointMake(20,-10)));
    b.scale=.8; b.actions[0].button=@"RB"; b.actions[0].modifiers=1; [b save];
    a=[[AKTouchActionLayout alloc] initWithDefaults:defaults simple:NO];
    assert(!a.enabled && Near(a.scale,2) && Near(a.borderOpacity,.6) && a.actions.count==2);
    assert([a.actions[0].button isEqual:@"LB"] && a.actions[0].diameter==80 && !a.actions[0].enabled);
    assert(CGPointEqualToPoint(a.center,CGPointMake(.6,.5)) && CGPointEqualToPoint(a.actions[0].position,CGPointMake(40,60)));
    [a reset]; [a save];
    b=[[AKTouchActionLayout alloc] initWithDefaults:defaults];
    assert(b.simple && b.actions.count==1 && Near(b.scale,.8) && b.enabled);
    assert([b.actions[0].button isEqual:@"RB"] && b.actions[0].modifiers==1);
    // Migration preserves the rollback data; corrupt new profiles use defaults,
    // rather than unexpectedly importing old settings a second time.
    assert([[defaults dictionaryForKey:@"WolkaraTouchAbilitiesV1"] isEqual:legacyAbilities]);
    assert([[defaults dictionaryForKey:@"WolkaraForeverTouchLayoutV1"] isEqual:legacy]);
    [defaults setObject:@"corrupt" forKey:@"WolkaraTouchLayoutV2.simple"];
    assert(Near([[AKGamepadLayout alloc] initWithDefaults:defaults].opacity,.8));
    [defaults removePersistentDomainForName:suite];
    puts("CONTROL_PROFILES_PASS: legacy migration, first visit, independent sizes/options/positions/toolbar/abilities, relaunch, reset and global HUD");
} return 0; }
