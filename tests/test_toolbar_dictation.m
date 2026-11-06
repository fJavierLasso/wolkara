#import <UIKit/UIKit.h>
#import "../launcher/Voice/Dictation.h"
#import "../launcher/Voice/VoiceSettings.h"
#import "../launcher/Voice/ToolbarDictationController.h"
static NSUInteger checks, failures;

static void Check(BOOL condition, NSString *what) {
    checks++;
    if (condition) return;
    failures++;
    fprintf(stderr, "FAIL: %s\n", what.UTF8String);
}
#define CHECK(condition, ...) Check((condition), [NSString stringWithFormat:__VA_ARGS__])

@interface FakeSpeech : NSObject <AKDictationSpeech>
@property (nonatomic) BOOL available;
@property (nonatomic) BOOL onDevice;
@property (nonatomic) BOOL authorized, deferAuthorization, failOnStart;
@property (nonatomic, copy) void (^authorizationAnswer)(BOOL);
@property (nonatomic, copy) void (^handler)(NSString *, BOOL, NSError *);
@property (nonatomic) NSUInteger starts, finishes, cancels;
@property (nonatomic, copy) NSArray<NSString *> *words;
- (void)say:(NSString *)text final:(BOOL)isFinal;
- (void)failAfterPartial:(NSString *)text;
@end

@implementation FakeSpeech
- (instancetype)init { if ((self = [super init])) { _available = YES; _onDevice = YES; _authorized = YES; } return self; }
- (BOOL)isAvailable { return self.available; }
- (BOOL)supportsOnDeviceRecognition { return self.onDevice; }
- (void)requestAuthorization:(void (^)(BOOL))completion {
    if (self.deferAuthorization) self.authorizationAnswer = completion;
    else completion(self.authorized);
}
- (void)startOnDevice:(BOOL)onDevice words:(NSArray<NSString *> *)words handler:(void (^)(NSString *, BOOL, NSError *))handler {
    (void)onDevice;
    self.starts++;
    self.words = words;
    self.handler = handler;
    if (_failOnStart) [self failAfterPartial:@""];
}
- (void)finish { self.finishes++; }
- (void)cancel { self.cancels++; self.handler = nil; }
// What a recogniser would do next.
- (void)say:(NSString *)text final:(BOOL)isFinal {
    void (^handler)(NSString *, BOOL, NSError *) = self.handler;
    if (handler) handler(text, isFinal, nil);
}
- (void)failAfterPartial:(NSString *)text {
    void (^handler)(NSString *, BOOL, NSError *) = self.handler;
    if (handler) handler(text, NO, [NSError errorWithDomain:@"test" code:3 userInfo:@{
        NSLocalizedDescriptionKey: @"the recogniser stopped"}]);
}
@end

@interface FakeAudio : NSObject <AKDictationAudio>
@property (nonatomic) BOOL refuse;
@property (nonatomic) BOOL refuseRestore;
@property (nonatomic) BOOL recording;
@property (nonatomic) NSUInteger begins, restores;
@end

@implementation FakeAudio
- (BOOL)beginRecording:(NSError **)error {
    self.begins++;
    if (self.refuse) {
        if (error) *error = [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"the session said no"}];
        return NO;
    }
    self.recording = YES;
    return YES;
}
- (BOOL)restore:(NSError **)error {
    self.restores++;
    if (self.refuseRestore) {
        if (error) *error = [NSError errorWithDomain:@"test" code:2 userInfo:@{NSLocalizedDescriptionKey: @"the session said no"}];
        return NO;
    }
    self.recording = NO;
    return YES;
}
@end

// The game's own text view, as far as dictation is concerned.
@interface FakeGameTextView : UIView
@property (nonatomic) NSUInteger inserts, returns, escapes;
@property (nonatomic, copy) NSString *lastText;
@property (nonatomic, strong) NSMutableArray<NSString *> *actions;
@end

@implementation FakeGameTextView
- (void)touchInsertText:(NSString *)text { self.inserts++; self.lastText = text; [self.actions addObject:@"text"]; }
- (void)touchSpecialKey:(unsigned short)code characters:(NSString *)characters {
    if (code == 53 && [characters isEqualToString:@"\x1b"]) { self.escapes++; [self.actions addObject:@"escape"]; return; }
    CHECK((code == 36 && [characters isEqualToString:@"\r"]), @"Return uses the unsigned-short ABI");
    self.returns++;
    [self.actions addObject:@"return"];
}
@end

@interface LocaleDictation : AKDictation
@property (nonatomic, copy) NSString *requestedLocale;
@end
@implementation LocaleDictation
- (BOOL)beginWithLocale:(NSString *)locale progress:(void (^)(NSString *))progress completion:(AKDictationCompletion)completion {
    self.requestedLocale = locale;
    return [super beginWithLocale:locale progress:progress completion:completion];
}
@end

static void TestToolbarDictation(UIWindow *window) {
    LocaleDictation *dictation = [LocaleDictation new];
    [dictation cancel];
    FakeSpeech *speech = [FakeSpeech new]; FakeAudio *audio = [FakeAudio new];
    dictation.speech = speech; dictation.audio = audio; dictation.transcriptHandler = nil;
    __attribute__((objc_precise_lifetime)) AKToolbarDictationController *controller = [[AKToolbarDictationController alloc] initWithDictation:dictation];
    FakeGameTextView *target = [FakeGameTextView new];
    target.actions = [NSMutableArray new];
    [window.rootViewController.view addSubview:target]; [AKDictation setGameTextTarget:target];
    __block NSString *state = nil, *problem = nil, *preview = @"";
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"AKTouchDictationState" object:target queue:nil usingBlock:^(NSNotification *note) {
        state = note.userInfo[@"state"]; problem = note.userInfo[@"problem"];
        if (note.userInfo[@"text"]) preview = note.userInfo[@"text"];
    }];
    void (^action)(NSString *) = ^(NSString *value) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchDictationAction" object:target
            userInfo:@{@"action":value, @"text":preview}];
    };
    AKVoiceSettings.shared.autoSubmit = YES; AKVoiceSettings.shared.trailingSpace = YES;
    action(@"start");
    CHECK(([state isEqualToString:@"listening"] && audio.recording && target.returns == 1 && !target.inserts), @"start opens chat with one Return and starts capture");
    [speech say:@"hello whirl" final:NO];
    CHECK(([preview isEqualToString:@"hello whirl"] && target.inserts == 0 && target.returns == 1), @"partial results appear only in the visible draft");
    [speech say:@"hello world" final:NO];
    CHECK(([preview isEqualToString:@"hello world"] && target.inserts == 0), @"a recognition correction replaces the draft without game keys");
    void (^oldLanguage)(NSString *, BOOL, NSError *) = speech.handler;
    NSUInteger oldStarts = speech.starts;
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchDictationAction" object:target
        userInfo:@{@"action":@"language", @"locale":@"en-US"}];
    CHECK(([dictation.requestedLocale isEqual:@"en-US"] && speech.starts == oldStarts + 1 && !preview.length), @"language selection starts a fresh recognizer and clears the old draft");
    oldLanguage(@"stale Spanish result", YES, nil);
    CHECK((!preview.length && target.returns == 1 && !target.escapes && !target.inserts && audio.recording), @"switching language ignores old results without opening chat twice or typing");
    [speech say:@"hello world" final:NO];
    void (^late)(NSString *, BOOL, NSError *) = speech.handler;
    action(@"confirm"); action(@"confirm"); late(@"extra words never reviewed", YES, nil);
    CHECK((target.inserts == 1 && target.returns == 2 && target.escapes == 1 && [target.lastText isEqualToString:@"hello world"]), @"confirm sends exactly the displayed text, one Return and one closing Esc, once");
    CHECK(([target.actions isEqualToArray:@[@"return", @"text", @"return", @"escape"]]), @"send closes chat after publishing; repeated confirmation and late speech add no keys");
    CHECK(([state isEqualToString:@"idle"] && !audio.recording), @"sending ends capture and clears the draft");
    action(@"start"); [speech say:@"cancel this" final:NO]; late = speech.handler;
    NSUInteger returns = target.returns;
    [target.actions removeAllObjects];
    action(@"cancel"); action(@"cancel"); late(@"late cancelled words", YES, nil);
    CHECK((target.inserts == 1 && target.returns == returns && target.escapes == 2 && !preview.length), @"cross discards text and adds exactly one Esc, with no Return");
    CHECK(([target.actions isEqualToArray:@[@"escape"]]), @"repeated cancel and late speech cannot add the second Esc that opens the menu");
    action(@"start"); [speech say:@"correct this" final:NO]; late = speech.handler;
    action(@"pause"); preview = @"manually corrected";
    late(@"old speech correction", NO, nil); late(@"old final", YES, nil);
    CHECK(([preview isEqualToString:@"manually corrected"] && !audio.recording), @"editing freezes recognition before the user changes the draft");
    action(@"confirm");
    CHECK((target.inserts == 2 && [target.lastText isEqualToString:@"manually corrected"]), @"confirmation uses the edited document");
    action(@"start"); [speech say:@"the final preview" final:YES];
    CHECK(([state isEqualToString:@"review"] && target.inserts == 2 && !audio.recording && [preview isEqualToString:@"the final preview"]), @"even final recognition results wait for explicit review");
    action(@"cancel");
    action(@"start"); returns = target.returns; action(@"confirm");
    CHECK((target.returns == returns && target.inserts == 2 && audio.recording), @"an empty checkmark does not close or send the chat");
    action(@"cancel");
    speech.authorized = NO; action(@"start");
    CHECK(([state isEqualToString:@"review"] && problem.length && !audio.recording), @"permission denial remains visible and cancellable");
    action(@"cancel"); speech.authorized = YES; speech.deferAuthorization = YES;
    NSUInteger starts = speech.starts;
    action(@"start"); action(@"cancel"); speech.authorizationAnswer(YES);
    CHECK((speech.starts == starts && [state isEqualToString:@"idle"]), @"late permission cannot reopen capture");
    speech.deferAuthorization = NO;
    action(@"start"); [speech say:@"background" final:NO]; late = speech.handler;
    returns = target.returns; NSUInteger escapes = target.escapes;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    late(@"old background result", YES, nil);
    CHECK((dictation.state == AKDictationStateIdle && !audio.recording && !preview.length && target.inserts == 2 && target.returns == returns && target.escapes == escapes), @"background discards without injecting any keys");
    audio.refuse = YES; action(@"start");
    CHECK((problem.length && [state isEqualToString:@"review"]), @"audio failure is visible and does not submit");
    action(@"cancel"); audio.refuse = NO;
    speech.failOnStart = YES; action(@"start");
    CHECK((problem.length && dictation.state == AKDictationStateIdle && !audio.recording), @"synchronous capture failure cannot strand listening state");
    action(@"cancel"); speech.failOnStart = NO;
    action(@"start"); [speech say:@"reviewed partial" final:NO]; [speech failAfterPartial:@"unreviewed error text"];
    CHECK((problem.length && target.inserts == 2 && [preview isEqualToString:@"reviewed partial"]), @"recognition error never replaces or submits the last visible draft");
    action(@"cancel");
    dictation.transcriptHandler = ^(NSString *text) { (void)text; };
    returns = target.returns; action(@"start");
    CHECK((problem.length && dictation.state == AKDictationStateIdle && target.returns == returns), @"Test Voice ownership prevents even the opening Return");
    dictation.transcriptHandler = nil;
    [dictation begin]; starts = speech.starts; action(@"start"); action(@"cancel");
    CHECK((speech.starts == starts && dictation.state == AKDictationStateListening), @"a mapped recording is not taken over or cancelled");
    [dictation cancel];
    action(@"start"); [speech say:@"detached" final:NO]; [target removeFromSuperview]; action(@"confirm");
    CHECK((target.inserts == 2), @"detached destinations never receive text");
    action(@"dismiss");
    [window.rootViewController.view addSubview:target];
    action(@"start"); [speech say:@"old session" final:NO]; late = speech.handler; action(@"cancel");
    action(@"start"); [speech say:@"new session" final:NO]; late(@"stale overwrite", YES, nil);
    CHECK(([preview isEqualToString:@"new session"] && target.inserts == 2), @"old callbacks cannot overwrite a new draft");
    preview = @"visible\ntext\t only"; action(@"confirm");
    CHECK(([target.lastText isEqualToString:@"visible text  only"] && target.inserts == 3), @"pasted control characters cannot become game commands");
    [NSNotificationCenter.defaultCenter removeObserver:observer]; [AKDictation setGameTextTarget:nil];
    CHECK((controller != nil), @"the toolbar owner survives the tests");
    AKVoiceSettings.shared.trailingSpace = NO; AKVoiceSettings.shared.autoSubmit = NO;
}

@interface TestDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic) UIWindow *window;
@end
@implementation TestDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController=[UIViewController new]; [self.window makeKeyAndVisible];
    TestToolbarDictation(self.window);
    printf("VOICE %s: %lu toolbar checks\n", failures ? "FAIL" : "PASS", (unsigned long)checks);
    fflush(stdout); exit(failures ? 1 : 0);
}
@end
@interface TestApp : UIResponder <UIApplicationDelegate>
@end

@implementation TestApp
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)options {
    (void)application; (void)options;
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Voice tests"
                                                                        sessionRole:session.role];
    configuration.delegateClass = TestDelegate.class;
    return configuration;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(TestApp.class));
    }
}
