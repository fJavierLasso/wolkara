// Exercise the real coordinator with a deterministic session, without a mic or
// an imported game. Interruption-ended is deliberately missing in one case.
#import <AVFAudio/AVFAudio.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AudioSessionCoordinator.h"
#import "AKAudioPlayback.h"
#include <assert.h>

@interface TestAudioSession : NSObject
@property NSString *category, *mode;
@property AVAudioSessionCategoryOptions categoryOptions;
@property BOOL active, secondaryAudioShouldBeSilencedHint;
@property NSUInteger activations, categories, failures;
@end
@implementation TestAudioSession
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)error {
    (void)error; self.category=category; self.mode=mode; self.categoryOptions=options; ++_categories; return YES;
}
- (BOOL)setActive:(BOOL)active error:(NSError **)error {
    if (active) {
        ++_activations;
        if (_failures) { --_failures; if(error)*error=[NSError errorWithDomain:@"test" code:1 userInfo:nil]; return NO; }
    }
    _active=active; return YES;
}
- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)error {
    (void)options; return [self setActive:active error:error];
}
- (BOOL)setPreferredInput:(id)input error:(NSError **)error { (void)input; (void)error; return YES; }
- (AVAudioSessionRecordPermission)recordPermission { return AVAudioSessionRecordPermissionGranted; }
- (id)currentRoute { return nil; }
- (double)sampleRate { return 48000; }
- (NSUInteger)inputNumberOfChannels { return 0; }
- (BOOL)isInputAvailable { return YES; }
@end
static TestAudioSession *session;
static id sharedSession(id cls, SEL selector) { (void)cls; (void)selector; return session; }
static void pump(double seconds) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(end.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
}
static void post(NSString *name, NSDictionary *info) {
    [NSNotificationCenter.defaultCenter postNotificationName:name object:nil userInfo:info]; pump(0.06);
}
int main(void) { @autoreleasepool {
    session=[TestAudioSession new];
    Method method=class_getClassMethod(AVAudioSession.class,@selector(sharedInstance));
    IMP original=method_setImplementation(method,(IMP)sharedSession);
    __block NSUInteger recoveries=0; __block float gain=1;
    [NSNotificationCenter.defaultCenter addObserverForName:AKGameAudioRecovered object:nil queue:nil usingBlock:^(NSNotification *note) { (void)note; ++recoveries; }];
    [NSNotificationCenter.defaultCenter addObserverForName:AKGameAudioGainChanged object:nil queue:nil usingBlock:^(NSNotification *note) { gain=[note.userInfo[@"gain"] floatValue]; }];
    AKAudioSessionCoordinator *owner=AKAudioSessionCoordinator.shared;
    assert([owner requestGamePlayback:@"test"]); pump(0.06);
    assert([session.category isEqual:AVAudioSessionCategoryPlayback]);
    assert(session.categoryOptions==AVAudioSessionCategoryOptionMixWithOthers);
    NSUInteger count=session.activations;
    for(int i=0;i<10;i++)assert([owner requestGamePlayback:@"hardware query"]);
    assert(session.activations==count && session.categories==1);
    post(AVAudioSessionInterruptionNotification,@{AVAudioSessionInterruptionTypeKey:@(AVAudioSessionInterruptionTypeBegan)});
    assert([owner requestGamePlayback:@"query during interruption"]);
    assert(session.activations==count);
    // No interruption-ended: foreground alone must recover a suspended output.
    post(UIApplicationDidBecomeActiveNotification,nil);
    assert(session.activations>count && recoveries==1);
    post(AVAudioSessionInterruptionNotification,@{AVAudioSessionInterruptionTypeKey:@(AVAudioSessionInterruptionTypeBegan)});
    post(AVAudioSessionInterruptionNotification,@{AVAudioSessionInterruptionTypeKey:@(AVAudioSessionInterruptionTypeEnded)});
    assert(recoveries==2);
    session.secondaryAudioShouldBeSilencedHint=YES;
    post(AVAudioSessionSilenceSecondaryAudioHintNotification,nil); assert(gain>0 && gain<0.5);
    session.secondaryAudioShouldBeSilencedHint=NO;
    post(AVAudioSessionSilenceSecondaryAudioHintNotification,nil); assert(gain==1);
    post(UIApplicationDidEnterBackgroundNotification,nil); assert(gain<0.5);
    post(UISceneDidActivateNotification,nil); assert(gain==1);
    assert([owner beginPushToTalk:NULL]); count=session.activations;
    post(UIApplicationDidBecomeActiveNotification,nil);
    assert(session.activations==count && owner.pushToTalkActive);
    assert([owner useRecordOnlyForPushToTalk:NULL]);
    assert([owner endPushToTalk:NULL]); pump(0.06);
    assert([session.category isEqual:AVAudioSessionCategoryPlayback] && !owner.pushToTalkActive);
    count=recoveries; session.failures=1;
    post(UIApplicationDidBecomeActiveNotification,nil); assert(recoveries==count);
    pump(0.35); assert(recoveries==count+1);
    // Pending retries must not steal a dictation or restart a released game.
    session.failures=1; post(UIApplicationDidBecomeActiveNotification,nil);
    [owner releaseGamePlayback]; count=session.activations; pump(0.35);
    assert(session.activations==count && !session.active);
    post(UIApplicationDidBecomeActiveNotification,nil); assert(session.activations==count);
    method_setImplementation(method,original);
    puts("audio session: mixing, interruption/foreground recovery, gain, dictation and cancelled retries: PASS");
} }
