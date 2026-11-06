#import "../translation/AppKit/AKPerformanceOverlay.h"
// Original UIKit/AppKit fixture for manual touch/keyboard testing. No guest.
#import "AppKit.h"
#import "TouchControls.h"
#import "TouchGamepad.h"
#import "TouchGamepadLayout.h"
#import "SavedTextController.h"
#include <assert.h>
#include <dlfcn.h>

@interface AKTouchControls (DictationLanguageFixture)
- (void)selectDictationLocale:(NSString *)identifier;
@end

@interface AKPerformanceOverlay (PerformanceFixture)
- (void)handlePan:(UIPanGestureRecognizer *)pan;
@end
@interface UIView (HostTrackingFixture)
- (BOOL)nativeControlsActive;
@end

@interface AKInputFixtureView : NSView
@property CATextLayer *heading, *instructions, *result;
@property NSMutableString *text;
@property NSString *lastAction;
@property NSRange selection;
@property NSUInteger replacements;
@property NSUInteger privateKeyCount;
// The last key event this guest view was given, so a test can say whether the adapter posted
// one at all. Nil is the answer that matters for a key the user has taken.
@property (nonatomic, strong, nullable) NSEvent *lastKeyEvent;
@end
@implementation AKInputFixtureView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [UIColor colorWithRed:0.06 green:0.10 blue:0.16 alpha:1].CGColor;
        _text = [NSMutableString new];
        _lastAction = @"Ready";
        for (NSString *key in @[@"heading", @"instructions", @"result"]) {
            CATextLayer *label = [CATextLayer new];
            label.contentsScale = UIScreen.mainScreen.scale;
            label.foregroundColor = UIColor.whiteColor.CGColor;
            label.wrapped = YES;
            [self.layer addSublayer:label];
            [self setValue:label forKey:key];
        }
        _heading.fontSize = 24; _instructions.fontSize = 15; _result.fontSize = 18;
        _heading.string = @"Tolkara · Touch input fixture";
        _instructions.string = @"Slide: move • Tap: left click • Two fingers: scroll / right click\nThree-finger tap: middle click • Hold then slide: drag\nUse the keyboard button at the top center. This is an original test screen.";
        [self setFrame:frame];
    }
    return self;
}
- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    CGFloat width = MAX(100, frame.size.width - 96);
    _heading.frame = CGRectMake(48, 32, width, 32);
    _instructions.frame = CGRectMake(48, 76, width, 78);
    _result.frame = CGRectMake(48, 170, width, 100);
    [self refresh];
}
- (void)refresh {
    self.result.string = [NSString stringWithFormat:@"%@\nText: %@", self.lastAction, self.text];
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)event {
    if (AKIsPrivateInputEvent(event)) self.privateKeyCount++;
    self.lastKeyEvent = event;
    if (event.keyCode == 0 && (event.modifierFlags & NSEventModifierFlagCommand)) {
        self.selection = NSMakeRange(0, self.text.length);
        self.replacements++;
        return;
    }
    NSRange range = self.selection;
    assert(NSMaxRange(range) <= self.text.length);
    if (event.keyCode == 51) {
        if (!range.length && range.location) range = [self.text rangeOfComposedCharacterSequenceAtIndex:range.location - 1];
        [self.text deleteCharactersInRange:range];
        self.selection = NSMakeRange(range.location, 0);
    } else if (event.keyCode == 53) {
        [self.text setString:@""]; self.selection = NSMakeRange(0, 0);
    } else if (event.characters.length) {
        [self.text replaceCharactersInRange:range withString:event.characters];
        self.selection = NSMakeRange(range.location + event.characters.length, 0);
    }
    self.lastAction = @"Keyboard input received";
    [self refresh];
}
- (void)mouseMoved:(NSEvent *)event {
    self.lastAction = [NSString stringWithFormat:@"Pointer %.0f, %.0f", event.locationInWindow.x, event.locationInWindow.y];
    [self refresh];
}
- (void)mouseDown:(NSEvent *)event { self.lastAction = event.clickCount == 2 ? @"Double click" : @"Left click / hold"; [self refresh]; }
- (void)rightMouseDown:(NSEvent *)event { (void)event; self.lastAction = @"Right click / hold"; [self refresh]; }
- (void)otherMouseDown:(NSEvent *)event { (void)event; self.lastAction = @"Middle click"; [self refresh]; }
- (void)mouseDragged:(NSEvent *)event { (void)event; self.lastAction = @"Left drag"; [self refresh]; }
- (void)rightMouseDragged:(NSEvent *)event { (void)event; self.lastAction = @"Right drag"; [self refresh]; }
- (void)scrollWheel:(NSEvent *)event {
    self.lastAction = [NSString stringWithFormat:@"Scroll %.0f, %.0f", event.deltaX, event.deltaY];
    [self refresh];
}
@end

static void AKDrainFixtureEvents(void) {
    // Let UIKit finish its asynchronous text transaction before observing the
    // translated events. The fixture is entered from a timer, like the guest.
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false);
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:event];
}

static UIView *AKFindInputView(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqual:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = AKFindInputView(child, identifier);
        if (found) return found;
    }
    return nil;
}

#pragma mark - Faking a key press at the adapter's door

// UIKey and UIPress cannot be constructed, so they are subclassed and the accessors
// `postKeys:` reads are overridden: keyCode, characters, modifierFlags and timestamp. This
// is the only way to drive the one place the adapter posts guest key events, and a contract
// nothing exercises is a contract that is not tested - the Replace assertion above sat
// failing for a day for exactly that reason.
@interface AKFixtureKey : UIKey
@property (nonatomic) UIKeyboardHIDUsage usage;
@end
@implementation AKFixtureKey
- (UIKeyboardHIDUsage)keyCode { return self.usage; }
- (UIKeyModifierFlags)modifierFlags { return 0; }
// "a" for usage 0x04, "b" for 0x05, and so on: enough for the guest view to insert.
- (NSString *)characters { return [NSString stringWithFormat:@"%c", (char)('a' + (self.usage - 0x04))]; }
- (NSString *)charactersIgnoringModifiers { return self.characters; }
@end

@interface AKFixturePress : UIPress
@property (nonatomic, strong) AKFixtureKey *fakeKey;
@end
@implementation AKFixturePress
- (UIKey *)key { return self.fakeKey; }
- (NSTimeInterval)timestamp { return NSProcessInfo.processInfo.systemUptime; }
@end

static void AKFixtureInputSource(void *context) {
    (void)context;
    NSEvent *event = [NSEvent new]; event.type = NSEventTypeMouseMoved;
    [NSApp postEvent:event atStart:NO];
}

static UIView *FindToolbarView(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqualToString:identifier]) return view;
    for (UIView *child in view.subviews) {
        UIView *found = FindToolbarView(child, identifier);
        if (found) return found;
    }
    return nil;
}
@interface AKToolbarTestPan : UIPanGestureRecognizer
@property UIGestureRecognizerState testState;
@property CGPoint movement;
@end
@implementation AKToolbarTestPan
- (UIGestureRecognizerState)state { return _testState; }
- (CGPoint)translationInView:(UIView *)view { (void)view; return _movement; }
@end
@interface AKTouchControls (ToolbarFixture)
- (void)moveToolbarItem:(UIPanGestureRecognizer *)pan;
- (NSArray<UIView *> *)toolbarItems;
- (CGRect)toolbarBounds;
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)pan;
- (void)holdSavedText:(UILongPressGestureRecognizer *)press;
- (void)holdGamepad:(UILongPressGestureRecognizer *)press;
- (BOOL)toggleGamepadEnabled;
@end

@interface AKSavedTextTestHold : UILongPressGestureRecognizer
@property UIGestureRecognizerState testState;
@end
@implementation AKSavedTextTestHold
- (UIGestureRecognizerState)state { return _testState; }
@end
static void TestControllerModes(AKTouchControls *controls) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    id savedEnabled=[defaults objectForKey:@"TKTouchGamepadEnabled"],savedSimple=[defaults objectForKey:@"TKTouchGamepadSimple"];
    UIButton *button=[controls valueForKey:@"_gamepadButton"];
    void (^tap)(void)=^{ [button sendActionsForControlEvents:UIControlEventTouchDown]; [button sendActionsForControlEvents:UIControlEventTouchUpInside]; };
    if (!controls.gamepadEnabled) [controls toggleGamepadEnabled];
    if ([[controls valueForKey:@"_gamepadSimple"] boolValue]) tap();
    tap(); assert(controls.gamepadEnabled && [[controls valueForKey:@"_gamepadSimple"] boolValue]);
    assert([defaults boolForKey:@"TKTouchGamepadSimple"]);
    assert([controls gestureRecognizerShouldBegin:[controls valueForKey:@"_gamepadHold"]]);
    AKSavedTextTestHold *hold=[AKSavedTextTestHold new]; hold.testState=UIGestureRecognizerStateBegan;
    [button sendActionsForControlEvents:UIControlEventTouchDown];
    [controls holdGamepad:hold]; [controls holdGamepad:hold];
    hold.testState=UIGestureRecognizerStateEnded; [controls holdGamepad:hold];
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(!controls.gamepadEnabled && [[controls valueForKey:@"_gamepadSimple"] boolValue]);
    tap(); assert(!controls.gamepadEnabled && ![[controls valueForKey:@"_gamepadSimple"] boolValue]);
    hold.testState=UIGestureRecognizerStateBegan;
    [button sendActionsForControlEvents:UIControlEventTouchDown]; [controls holdGamepad:hold];
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(controls.gamepadEnabled && ![[controls valueForKey:@"_gamepadSimple"] boolValue]);
    AKTouchControls *reload=[[AKTouchControls alloc] initWithFrame:controls.bounds];
    assert(reload.gamepadEnabled && ![[reload valueForKey:@"_gamepadSimple"] boolValue]);
    assert(button.accessibilityCustomActions.count==1);
    if ([savedSimple boolValue]) tap();
    if (savedEnabled && ![savedEnabled boolValue]) [controls toggleGamepadEnabled];
    for (NSString *key in @[@"TKTouchGamepadEnabled",@"TKTouchGamepadSimple"]) {
        id value=[key isEqual:@"TKTouchGamepadEnabled"]?savedEnabled:savedSimple;
        if (value) [defaults setObject:value forKey:key]; else [defaults removeObjectForKey:key];
    }
    puts("CONTROLLER_MODE_GESTURES_PASS: tap changes layout, hold toggles enabled once, no trailing tap, persistence and accessibility action.");
}
@interface AKSavedTextTestStore : NSObject <WKSavedTextStorage>
@property NSString *value;
@property BOOL refuse;
@property NSUInteger writes;
@end
@implementation AKSavedTextTestStore
- (NSString *)readText:(NSError **)error {
    if (self.refuse) { if (error) *error = [NSError errorWithDomain:@"fixture" code:1 userInfo:nil]; return nil; }
    return self.value ?: @"";
}
- (BOOL)saveText:(NSString *)text error:(NSError **)error {
    if (self.refuse) { if (error) *error = [NSError errorWithDomain:@"fixture" code:1 userInfo:nil]; return NO; }
    self.value = text; self.writes++; return YES;
}
@end
@interface WKSavedTextController (Fixture)
- (void)saveEditor;
- (void)clearEditor;
@end
static void AKSavedTextSettle(UIViewController *presenter) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    do {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    } while ((presenter.transitionCoordinator || presenter.presentedViewController.isBeingPresented ||
              presenter.presentedViewController.isBeingDismissed) && deadline.timeIntervalSinceNow > 0);
    assert(!presenter.presentedViewController.isBeingPresented && !presenter.presentedViewController.isBeingDismissed);
    AKDrainFixtureEvents();
}

@interface AKInputFixtureScene : UIResponder <UIWindowSceneDelegate>
@property NSWindow *guest;
@property NSTimer *pump;
@end
@implementation AKInputFixtureScene
- (void)checkSavedText {
    UIView *host = [self.guest valueForKey:@"_host"];
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKInputFixtureView *guest = (id)self.guest.contentView;
    UIButton *key = (id)FindToolbarView(controls, @"wolkaraforever.savedText");
    AKSavedTextTestStore *store = [AKSavedTextTestStore new];
    __attribute__((objc_precise_lifetime)) WKSavedTextController *controller = [[WKSavedTextController alloc] initWithStore:store];
    controller.gameTextTarget = controls;
    UIViewController *presenter = controls.window.rootViewController;
    [key sendActionsForControlEvents:UIControlEventTouchDown];
    [key sendActionsForControlEvents:UIControlEventTouchUpInside]; AKSavedTextSettle(presenter);
    UIAlertController *editor = (id)presenter.presentedViewController;
    assert([editor isKindOfClass:UIAlertController.class] && controls.configuring);
    assert([editor.message isEqualToString:@"Hold key to type what's in the box and send it. Useful for your password"]);
    UITextField *field = editor.textFields.firstObject;
    assert(field.secureTextEntry && field.autocorrectionType == UITextAutocorrectionTypeNo && field.autocapitalizationType == UITextAutocapitalizationTypeNone);
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--saved-text-preview"]) return;
    NSString *dummy = @" fixture-Pass123! "; // Deliberate spaces must be preserved.
    field.text = dummy;
    [controller saveEditor]; AKSavedTextSettle(presenter);
    assert([store.value isEqualToString:dummy] && store.writes == 1 && !field.text.length && !guest.text.length && !controls.configuring);
    AKSavedTextTestHold *hold = [AKSavedTextTestHold new];
    [key sendActionsForControlEvents:UIControlEventTouchDown];
    hold.testState = UIGestureRecognizerStateBegan;
    [controls holdSavedText:hold]; [controls holdSavedText:hold];
    hold.testState = UIGestureRecognizerStateChanged; [controls holdSavedText:hold];
    hold.testState = UIGestureRecognizerStateEnded; [controls holdSavedText:hold];
    [key sendActionsForControlEvents:UIControlEventTouchUpInside]; AKSavedTextSettle(presenter);
    NSString *sent = [dummy stringByAppendingString:@"\r"];
    assert([guest.text isEqualToString:sent] && !presenter.presentedViewController);
    assert(guest.privateKeyCount == sent.length && AKIsPrivateInputEvent(guest.lastKeyEvent));
    // Recreate the owner: the value comes from storage, not a controller cache.
    controller = nil;
    controller = [[WKSavedTextController alloc] initWithStore:store]; controller.gameTextTarget = controls;
    [key sendActionsForControlEvents:UIControlEventTouchDown]; [key sendActionsForControlEvents:UIControlEventTouchUpInside]; AKSavedTextSettle(presenter);
    editor = (id)presenter.presentedViewController; field = editor.textFields.firstObject;
    assert([field.text isEqualToString:dummy]);
    store.refuse = YES; field.text = @"unsaved replacement";
    [controller saveEditor]; AKSavedTextSettle(presenter);
    assert([store.value isEqualToString:dummy] && store.writes == 1 && !field.text.length && [guest.text isEqualToString:sent]);
    [presenter dismissViewControllerAnimated:NO completion:nil]; AKSavedTextSettle(presenter);
    store.refuse = NO;
    [key sendActionsForControlEvents:UIControlEventTouchDown]; [key sendActionsForControlEvents:UIControlEventTouchUpInside]; AKSavedTextSettle(presenter);
    editor = (id)presenter.presentedViewController; field = editor.textFields.firstObject;
    field.text = @"not saved";
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil]; AKSavedTextSettle(presenter);
    assert(!field.text.length && [store.value isEqualToString:dummy] && [guest.text isEqualToString:sent] && !controls.configuring);
    [key sendActionsForControlEvents:UIControlEventTouchDown]; [key sendActionsForControlEvents:UIControlEventTouchUpInside]; AKSavedTextSettle(presenter);
    editor = (id)presenter.presentedViewController; editor.textFields.firstObject.text = @"";
    [controller saveEditor]; AKSavedTextSettle(presenter);
    assert(!store.value.length && store.writes == 2);
    [key sendActionsForControlEvents:UIControlEventTouchDown]; hold.testState = UIGestureRecognizerStateBegan;
    [controls holdSavedText:hold]; AKSavedTextSettle(presenter);
    assert([presenter.presentedViewController isKindOfClass:UIAlertController.class] && [guest.text isEqualToString:sent]);
    [controller clearEditor]; [presenter dismissViewControllerAnimated:NO completion:nil]; AKSavedTextSettle(presenter);
    store.refuse = YES;
    [key sendActionsForControlEvents:UIControlEventTouchDown]; [controls holdSavedText:hold]; AKSavedTextSettle(presenter);
    assert([presenter.presentedViewController isKindOfClass:UIAlertController.class] && [guest.text isEqualToString:sent]);
    [presenter dismissViewControllerAnimated:NO completion:nil]; AKSavedTextSettle(presenter);
    store.refuse = NO; store.value = @"invalid\ncommand";
    [key sendActionsForControlEvents:UIControlEventTouchDown]; [controls holdSavedText:hold]; AKSavedTextSettle(presenter);
    assert([presenter.presentedViewController isKindOfClass:UIAlertController.class] && [guest.text isEqualToString:sent]);
    [presenter dismissViewControllerAnimated:NO completion:nil]; AKSavedTextSettle(presenter);
    // A detached or unregistered destination must never receive saved text.
    controller.gameTextTarget = nil; store.value = dummy;
    [key sendActionsForControlEvents:UIControlEventTouchDown]; [controls holdSavedText:hold]; AKSavedTextSettle(presenter);
    assert([guest.text isEqualToString:sent] && !presenter.presentedViewController);
    // Isolated synthetic item only; never use the app's actual service or value.
    NSString *service = [@"org.tolkara.fixture.saved-text." stringByAppendingString:NSUUID.UUID.UUIDString];
    WKSavedTextStore *realStore = [[WKSavedTextStore alloc] initWithService:service];
    NSError *storageError = nil;
    if ([realStore saveText:dummy error:&storageError]) {
        WKSavedTextStore *freshStore = [[WKSavedTextStore alloc] initWithService:service];
        assert([[freshStore readText:&storageError] isEqualToString:dummy]);
        assert([freshStore saveText:@"replacement" error:&storageError]);
        assert([[realStore readText:&storageError] isEqualToString:@"replacement"]);
        assert([freshStore saveText:@"" error:&storageError] && ![realStore readText:&storageError].length);
        NSLog(@"saved-text fixture: isolated Keychain add, reload, update and delete passed");
    } else {
        assert(storageError != nil);
        NSLog(@"saved-text fixture: Keychain refusal reported (%ld); persistence needs the signed app", (long)storageError.code);
    }
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: secure saved-text editor, save without typing, single hold submission, persistent-store reload, empty value, background clearing and refusal paths");
    exit(EXIT_SUCCESS);
}
- (void)saveFixturePreview {
    [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        UIWindow *window = [(UIView *)[self.guest valueForKey:@"_host"] window];
        [window layoutIfNeeded];
        UIView *host = [self.guest valueForKey:@"_host"];
        UIView *target;
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--performance-test"])
            target = [host valueForKey:@"_performanceOverlay"];
        else {
            AKTouchControls *controls = [host valueForKey:@"_touchControls"];
            target = [(UIView *)[controls valueForKey:@"_keyboardInput"] superview];
        }
        [target layoutIfNeeded]; assert(target.bounds.size.width > 0 && target.bounds.size.height > 0);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:target.bounds];
        NSData *png = [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
            [target.layer renderInContext:context.CGContext];
        }];
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/fixture-preview.png"];
        assert([png writeToFile:path atomically:YES]);
        NSLog(@"TOUCH_UI_SELF_TEST_PASS: saved UIKit preview"); exit(EXIT_SUCCESS);
    }];
}
- (void)checkLateMetalMetrics {
    UIView *host = [self.guest valueForKey:@"_host"];
    AKPerformanceOverlay *overlay = [host valueForKey:@"_performanceOverlay"];
    [NSUserDefaults.standardUserDefaults setObject:@{@"performanceOverlayEnabled":@NO}
        forKey:@"WolkaraForeverTouchLayoutV1"];
    overlay.hidden = NO;
    [overlay updateMetrics];
    assert(dlsym(RTLD_DEFAULT, "AKMetalCurrentFPS") == NULL);
    NSString *library = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"LateMetalMetrics.dylib"];
    assert(dlopen(library.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL));
    void (*prepare)(void) = dlsym(RTLD_DEFAULT, "AKTestPrepareLateMetal");
    void (*record)(void) = dlsym(RTLD_DEFAULT, "AKTestRecordMetalFrames");
    assert(prepare && record);
    prepare();
    [overlay updateMetrics]; // Resolves the late library and enables its real hooks.
    void (*intervals)(void) = dlsym(RTLD_DEFAULT, "AKTestMetricIntervals");
    assert(intervals); intervals();
    // Start fresh after interval tests.
    overlay.hidden = YES; overlay.hidden = NO;
    record();
    [overlay updateMetrics];
    UILabel *label = [overlay valueForKey:@"_fpsLabel"];
    assert([label.text containsString:@"60"]);
    overlay.hidden = YES;
    assert([overlay valueForKey:@"_pollTimer"] == nil);
    overlay.hidden = NO;
    record(); [overlay updateMetrics];
    assert([label.text containsString:@"60"]);
    overlay.expanded = YES; [overlay layoutIfNeeded];
    for (NSString *key in @[@"_expandedFPSLabel",@"_expandedGPULabel",@"_expandedThermalLabel",@"_expandedMemoryLabel",@"_expandedBatteryLabel",@"_expandedPowerLabel"]) {
        UILabel *row = [overlay valueForKey:key];
        assert(row.text.length && row.bounds.size.height > 10 && row.bounds.size.width > 100);
    }
    overlay.expanded = NO;
    AKToolbarTestPan *drag = [AKToolbarTestPan new];
    drag.testState = UIGestureRecognizerStateBegan; [overlay handlePan:drag];
    assert(overlay.interacting && [host nativeControlsActive]);
    drag.testState = UIGestureRecognizerStateChanged; drag.movement = CGPointMake(5000,5000); [overlay handlePan:drag];
    assert(CGRectContainsRect(UIEdgeInsetsInsetRect(host.bounds,host.safeAreaInsets),overlay.frame));
    drag.testState = UIGestureRecognizerStateEnded; [overlay handlePan:drag];
    assert(!overlay.interacting);
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKTouchGamepad *gamepad = [controls valueForKey:@"_gamepad"];
    [gamepad toggleSettings];
    UISwitch *toggle = (id)FindToolbarView(host, @"wolkara.controls.performance");
    assert(toggle);
    toggle.on = YES; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    assert(gamepad.layout.performanceOverlayEnabled && !overlay.hidden);
    toggle.on = NO; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    assert(overlay.hidden && [overlay valueForKey:@"_pollTimer"] == nil);
    [gamepad toggleSettings];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--save-preview"]) {
        overlay.hidden = NO; overlay.expanded = YES; record(); [overlay updateMetrics];
        [self saveFixturePreview]; return;
    }
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: late Metal load, late HUD enable, synthetic 60 FPS and hide/show recovery");
    exit(EXIT_SUCCESS);
}
- (void)checkReviewedVoiceDraft {
    UIView *host = [self.guest valueForKey:@"_host"];
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKInputFixtureView *guest = (id)self.guest.contentView;
    UITextView *draft = [controls valueForKey:@"_keyboardInput"];
    UIButton *mic = (id)FindToolbarView(controls, @"wolkaraforever.dictate");
    UIButton *send = (id)FindToolbarView(controls, @"wolkaraforever.dictationSend");
    UIButton *cancel = (id)FindToolbarView(controls, @"wolkaraforever.dictationCancel");
    UIButton *draftCancel = [controls valueForKey:@"_clearDraftButton"];
    __block NSString *lastAction = nil, *submitted = nil, *locale = nil;
    [NSUserDefaults.standardUserDefaults setObject:@"es-ES" forKey:@"AKToolbarDictationLocale"];
    void (^publish)(NSString *, NSString *) = ^(NSString *state, NSString *text) {
        NSMutableDictionary *info = [@{@"state":state} mutableCopy];
        if (text) info[@"text"] = text;
        [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchDictationState" object:controls userInfo:info];
    };
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"AKTouchDictationAction" object:controls queue:nil usingBlock:^(NSNotification *note) {
        lastAction = note.userInfo[@"action"];
        locale = note.userInfo[@"locale"];
        if ([lastAction isEqualToString:@"start"] || [lastAction isEqualToString:@"language"]) publish(@"authorizing", @"");
        else if ([lastAction isEqualToString:@"pause"]) publish(@"review", nil);
        else if ([lastAction isEqualToString:@"confirm"]) { submitted = note.userInfo[@"text"]; publish(@"idle", @""); }
        else if ([lastAction isEqualToString:@"cancel"] || [lastAction isEqualToString:@"dismiss"]) publish(@"idle", @"");
    }];
    [mic sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(!controls.keyboardVisible && !draft.superview.hidden && !send.enabled);
    publish(@"listening", @"hello whirl"); publish(@"listening", @"hello world");
    assert([draft.text isEqualToString:@"hello world"] && send.enabled && !controls.keyboardVisible);
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--review-draft-preview"]) {
        publish(@"listening", @"Hola equipo, nos vemos junto a la entrada. Este texto se queda aquí hasta pulsar enviar.");
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--save-preview"]) [self saveFixturePreview];
        return;
    }
    UIButton *language = [controls valueForKey:@"_dictationLanguageButton"];
    assert(!language.hidden && language.showsMenuAsPrimaryAction && [locale isEqual:@"es-ES"]);
    [controls selectDictationLocale:@"en-US"];
    assert([lastAction isEqual:@"language"] && [locale isEqual:@"en-US"] && !draft.text.length);
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"AKToolbarDictationLocale"] isEqual:@"en-US"]);
    BOOL checkedEnglish = NO;
    for (UIAction *choice in language.menu.children)
        if ([choice.identifier isEqual:@"en-US"]) checkedEnglish = choice.state == UIMenuElementStateOn;
    assert(checkedEnglish);
    publish(@"listening", @"hello world");
    AKDrainFixtureEvents(); assert(!guest.text.length && guest.lastKeyEvent == nil);
    [draft becomeFirstResponder]; AKDrainFixtureEvents();
    assert([lastAction isEqualToString:@"pause"] && controls.keyboardVisible && draft.inputView == nil);
    draft.selectedRange = NSMakeRange(draft.text.length, 0);
    [draft insertText:@" edited"];
    [send sendActionsForControlEvents:UIControlEventTouchUpInside]; AKDrainFixtureEvents();
    assert([submitted isEqualToString:@"hello world edited"] && !draft.text.length && draft.superview.hidden && !controls.keyboardVisible);
    assert(!guest.text.length && guest.lastKeyEvent == nil); // Only the notification may request a commit.
    [mic sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert([locale isEqual:@"en-US"] && !language.hidden);
    publish(@"listening", @"discard this");
    [cancel sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert([lastAction isEqualToString:@"cancel"] && !draft.text.length && draft.superview.hidden);
    [draft insertDictationResult:@[]]; [draft insertText:@"late native result"];
    assert(!draft.text.length); // Cancellation must not re-arm the editor.
    [mic sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(draftCancel.enabled && !draft.text.length && !draft.superview.hidden);
    [draftCancel sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert([lastAction isEqualToString:@"cancel"] && !draft.text.length && draft.superview.hidden);
    [mic sendActionsForControlEvents:UIControlEventTouchUpInside]; publish(@"listening", @"discard from draft cross");
    [draftCancel sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert([lastAction isEqualToString:@"cancel"] && !draft.text.length && draft.superview.hidden);
    [mic sendActionsForControlEvents:UIControlEventTouchUpInside]; publish(@"listening", @"background draft");
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    assert([lastAction isEqualToString:@"dismiss"] && !draft.text.length && draft.superview.hidden);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: visible live draft, no game input, keyboard editing, exact reviewed confirmation, cancel and background discard");
    exit(EXIT_SUCCESS);
}
- (void)checkToolbarEditing {
    UIView *host = [self.guest valueForKey:@"_host"];
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKTouchGamepad *gamepad = [controls valueForKey:@"_gamepad"];
    [gamepad.layout reset]; [host layoutIfNeeded]; [controls layoutIfNeeded];
    NSArray<UIView *> *items = [controls toolbarItems];
    assert(items.count == 7 && CGRectEqualToRect(controls.frame, host.bounds));
    for (UIView *item in items) assert(CGRectContainsRect([controls toolbarBounds], item.frame));
    CGPoint clear = CGPointMake(CGRectGetMidX(controls.bounds), CGRectGetMidY(controls.bounds));
    assert(![controls pointInside:clear withEvent:nil]);
    UIButton *mic = (id)FindToolbarView(controls, @"wolkaraforever.dictate");
    UIButton *send = (id)FindToolbarView(controls, @"wolkaraforever.dictationSend");
    UIButton *cancel = (id)FindToolbarView(controls, @"wolkaraforever.dictationCancel");
    assert(mic && send && cancel && !mic.hidden && send.hidden && cancel.hidden);
    __block NSString *action = nil;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"AKTouchDictationAction" object:controls queue:nil usingBlock:^(NSNotification *note) { action = note.userInfo[@"action"]; }];
    [mic sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert([action isEqualToString:@"start"] && !controls.keyboardVisible);
    void (^state)(NSString *) = ^(NSString *value) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchDictationState" object:controls userInfo:@{@"state":value}];
    };
    state(@"authorizing"); assert(mic.hidden && !send.hidden && !cancel.hidden && !send.enabled);
    state(@"listening");
    UITextView *draft = [controls valueForKey:@"_keyboardInput"];
    assert(!send.enabled && controls.configuring && !controls.keyboardVisible);
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchDictationState" object:controls
        userInfo:@{@"state":@"listening", @"text":@"A visible draft"}];
    assert(send.enabled && [draft.text isEqualToString:@"A visible draft"] && !draft.superview.hidden && draft.inputView == nil);
    UIView *shield = [controls valueForKey:@"_dictationShield"];
    assert(!shield.hidden && [host hitTest:[controls convertPoint:clear toView:host] withEvent:nil] == shield);
    [send sendActionsForControlEvents:UIControlEventTouchUpInside]; assert([action isEqualToString:@"confirm"]);
    state(@"finalizing"); assert(send.enabled && !cancel.hidden);
    [cancel sendActionsForControlEvents:UIControlEventTouchUpInside]; assert([action isEqualToString:@"cancel"]);
    state(@"idle"); assert(!mic.hidden && send.hidden && cancel.hidden && !draft.text.length && draft.superview.hidden && shield.hidden);
    [gamepad toggleSettings]; [host layoutIfNeeded];
    UISwitch *edit = (id)FindToolbarView(host, @"wolkaraforever.controls.edit");
    assert(edit); edit.on = YES; [edit sendActionsForControlEvents:UIControlEventValueChanged];
    [host layoutIfNeeded]; [controls layoutIfNeeded];
    assert(gamepad.editing && controls.configuring);
    BOOL mouseBefore = controls.trackpadEnabled, padBefore = controls.gamepadEnabled;
    for (UIView *item in items) {
        CGRect before = item.frame;
        CGPoint center = CGPointMake(CGRectGetMidX(item.bounds), CGRectGetMidY(item.bounds));
        UIView *hit = [host hitTest:[item convertPoint:center toView:host] withEvent:nil];
        assert(hit == item || [hit isDescendantOfView:item]);
        if ([item isKindOfClass:UIButton.class]) [(UIButton *)item sendActionsForControlEvents:UIControlEventTouchUpInside];
        AKToolbarTestPan *pan = [AKToolbarTestPan new]; [item addGestureRecognizer:pan];
        assert([controls gestureRecognizerShouldBegin:pan]);
        pan.testState = UIGestureRecognizerStateBegan; [controls moveToolbarItem:pan];
        pan.movement = CGPointMake(-30, 180); pan.testState = UIGestureRecognizerStateChanged; [controls moveToolbarItem:pan];
        pan.testState = UIGestureRecognizerStateEnded; [controls moveToolbarItem:pan];
        assert(!CGRectEqualToRect(item.frame, before));
        assert(CGRectContainsRect([controls toolbarBounds], item.frame));
        AKGamepadLayout *saved = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        CGRect restored = [saved frameForItem:item.accessibilityIdentifier defaultFrame:before inBounds:[controls toolbarBounds]];
        assert(fabs(restored.origin.x-item.frame.origin.x)<0.01 && fabs(restored.origin.y-item.frame.origin.y)<0.01);
        [item removeGestureRecognizer:pan];
    }
    assert(controls.trackpadEnabled == mouseBefore && controls.gamepadEnabled == padBefore && !controls.keyboardVisible);
    // Done must win hit-testing even if a user drops the mouse control over it.
    UIButton *done = (id)FindToolbarView(host, @"wolkaraforever.layout.done");
    UIView *mouse = items[0];
    CGPoint doneCenter = [done convertPoint:CGPointMake(CGRectGetMidX(done.bounds), CGRectGetMidY(done.bounds)) toView:controls];
    mouse.center = doneCenter;
    assert(![controls pointInside:doneCenter withEvent:nil]);
    assert([host hitTest:[controls convertPoint:doneCenter toView:host] withEvent:nil] == done);
    [done sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(!gamepad.editing);
    AKToolbarTestPan *pan = [AKToolbarTestPan new]; assert(![controls gestureRecognizerShouldBegin:pan]);
    // Reconstruct positions at iPhone Pro/Max and Duo-like window sizes, portrait and landscape.
    CGRect original = host.bounds;
    for (NSValue *size in @[[NSValue valueWithCGSize:CGSizeMake(402,874)], [NSValue valueWithCGSize:CGSizeMake(440,956)],
                           [NSValue valueWithCGSize:CGSizeMake(956,440)], [NSValue valueWithCGSize:CGSizeMake(678,466)],
                           [NSValue valueWithCGSize:CGSizeMake(951,669)]]) {
        host.bounds = (CGRect){CGPointZero, size.CGSizeValue};
        [controls setNeedsLayout]; [controls layoutIfNeeded];
        for (UIView *item in items) assert(CGRectContainsRect([controls toolbarBounds], item.frame));
    }
    host.bounds = original;
    [gamepad.layout reset]; [controls setNeedsLayout]; [controls layoutIfNeeded];
    for (UIView *item in items) assert(fabs(item.frame.origin.y-[controls toolbarBounds].origin.y)<0.01);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: toolbar drag, persistence, resize, reset, edit isolation, Done hit-testing and dictation controls");
    exit(EXIT_SUCCESS);
}

- (void)checkTrackingUIProgress {
    UIView *host = [self.guest valueForKey:@"_host"];
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKTouchGamepad *gamepad = [controls valueForKey:@"_gamepad"];
    for (NSUInteger surface = 0; surface < 2; surface++) {
        if (surface == 0) [controls toggleKeyboard]; else [gamepad toggleSettings];
        __block BOOL trackingFired = NO, defaultFired = NO;
        NSTimer *tracking = [NSTimer timerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *timer) {
            (void)timer; trackingFired = YES;
        }];
        [NSRunLoop.mainRunLoop addTimer:tracking forMode:UITrackingRunLoopMode];
        NSTimer *ordinary = [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *timer) {
            (void)timer; defaultFired = YES;
        }];
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 1;
        while (!(trackingFired && defaultFired) && NSProcessInfo.processInfo.systemUptime < deadline) {
            // The guest polls with no imported application running. Drain its
            // queue so this test reaches the native-UI service point.
            [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES];
        }
        [tracking invalidate]; [ordinary invalidate];
        NSLog(@"Native tracking progress: surface=%lu tracking=%d default=%d", (unsigned long)surface, trackingFired, defaultFired);
        assert(trackingFired && defaultFired);
        if (surface == 0) [controls dismissKeyboard]; else [gamepad toggleSettings];
    }
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: UIKit tracking and default work progress while native editor/settings are open");
    exit(EXIT_SUCCESS);
}
- (void)checkNativeUIProgress {
    UIView *host = [self.guest valueForKey:@"_host"];
    CFRunLoopSourceContext context = {0}; context.perform = AKFixtureInputSource;
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    // Empty nonblocking polls, source-driven blocking polls, a permanently
    // occupied queue, repeated peeks, and NSApplication's own run loop must
    // all let native UI make progress.
    for (NSUInteger traffic = 0; traffic < 5; traffic++) {
        UIView *probe = [[UIView alloc] initWithFrame:CGRectMake(60, 260, 24, 24)];
        probe.backgroundColor = UIColor.systemGreenColor;
        [host addSubview:probe];
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(60, 300, 220, 32)];
        [host addSubview:slider];
        __block BOOL completed = NO, deferred = NO, timerFired = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ deferred = YES; });
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *fired) {
            (void)fired; slider.value = 0.75; timerFired = YES;
        }];
        // No explicit flush in the fixture: it previously hid presentation
        // problems by forcing a Core Animation commit after every key/motion.
        [UIView animateWithDuration:0.05 animations:^{
            probe.center = CGPointMake(200, 272);
        } completion:^(BOOL finished) { completed = finished; }];
        NSEvent *peeked = nil;
        if (traffic == 3) {
            AKFixtureInputSource(NULL);
            peeked = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast
                inMode:NSDefaultRunLoopMode dequeue:NO];
            assert(peeked);
        }
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 2;
        if (traffic == 4) {
            [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *stop) {
                (void)stop; [NSApp stop:nil];
            }];
            [NSApp run];
        }
        while (traffic != 4 && !(completed && deferred && timerFired) && NSProcessInfo.processInfo.systemUptime < deadline) {
            @autoreleasepool {
                if (traffic == 2) AKFixtureInputSource(NULL);
                if (traffic == 1) CFRunLoopSourceSignal(source);
                NSEvent *event = [NSApp nextEventMatchingMask:UINT64_MAX
                    untilDate:traffic == 1 ? [NSDate dateWithTimeIntervalSinceNow:0.01] : NSDate.distantPast
                    inMode:NSDefaultRunLoopMode dequeue:traffic != 3];
                if (peeked) assert(event == peeked);
            }
        }
        [timer invalidate];
        NSLog(@"Native UI progress: traffic=%lu animation=%d deferred=%d timer=%d",
            (unsigned long)traffic, completed, deferred, timerFired);
        assert(completed && deferred && timerFired && slider.value == 0.75);
        if (peeked) assert([NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast
            inMode:NSDefaultRunLoopMode dequeue:YES] == peeked);
        [probe removeFromSuperview]; [slider removeFromSuperview];
    }
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFRelease(source);
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: native UI presentation, deferred work, slider updates and queue peeking inside guest loop");
    exit(EXIT_SUCCESS);
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    [NSApplication sharedApplication];
    self.guest = [[NSWindow alloc] initWithContentRect:((UIWindowScene *)scene).screen.bounds styleMask:0 backing:2 defer:NO];
    self.guest.contentView = [[AKInputFixtureView alloc] initWithFrame:self.guest.frame];
    self.guest.acceptsMouseMovedEvents = YES;
    [self.guest makeFirstResponder:self.guest.contentView];
    [self.guest makeKeyAndOrderFront:nil];
    self.pump = [NSTimer scheduledTimerWithTimeInterval:0.016 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:event];
    }];
    BOOL selfTest = [NSProcessInfo.processInfo.arguments containsObject:@"--self-test"];
    BOOL nativeReference = [NSProcessInfo.processInfo.arguments containsObject:@"--native-keyboard-reference"];
    if (selfTest) {
        // A blocked main thread must fail instead of leaving simctl waiting.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                fprintf(stderr, "TOUCH_UI_SELF_TEST_TIMEOUT\n");
                _Exit(EXIT_FAILURE);
            });
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--performance-test"]) {
        [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:NO block:^(NSTimer *timer) { (void)timer; [self checkLateMetalMetrics]; }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--review-draft-test"] || [NSProcessInfo.processInfo.arguments containsObject:@"--review-draft-preview"]) {
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
            (void)timer; [self checkReviewedVoiceDraft];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--saved-text-test"] || [NSProcessInfo.processInfo.arguments containsObject:@"--saved-text-preview"]) {
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
            (void)timer; [self checkSavedText];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--toolbar-test"]) {
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
            (void)timer; [self checkToolbarEditing];
        }];
        return;
    }
    // A plain launch is for looking at the fixture. Without --stay it closes itself
    // after a minute anyway, so a headless run cannot sit on it for ever.
    if (!selfTest && ![NSProcessInfo.processInfo.arguments containsObject:@"--stay"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{
                fprintf(stderr, "TOUCH_UI_LIFETIME_REACHED (pass --stay to keep it open)\n");
                _Exit(EXIT_SUCCESS);
            });
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--tracking-progress-test"]) {
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer; [self.pump invalidate]; self.pump = nil;
            [self checkTrackingUIProgress];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--ui-progress-test"]) {
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            [self.pump invalidate]; self.pump = nil;
            [self checkNativeUIProgress];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--guest-poll-loop"]) {
        // Exercise UIKit inside the timer-entered desktop loop used by the
        // runtime, rather than only returning to UIApplicationMain each turn.
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            [self.pump invalidate];
            self.pump = nil;
            while (YES) { @autoreleasepool {
                if ([NSProcessInfo.processInfo.arguments containsObject:@"--queued-traffic"]) AKFixtureInputSource(NULL);
                NSEvent *event = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast
                    inMode:NSDefaultRunLoopMode dequeue:YES];
                if (event.window) [NSApp sendEvent:event];
            } }
        }];
    }
    if (selfTest || nativeReference || [NSProcessInfo.processInfo.arguments containsObject:@"--show-keyboard"]) {
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            UIView *host = [self.guest valueForKey:@"_host"];
            AKTouchControls *controls = [host valueForKey:@"_touchControls"];
            CGSize originalSize = host.bounds.size;
            if (nativeReference) {
                UITextView *reference = [[UITextView alloc] initWithFrame:CGRectMake(48, 130, 360, 70)];
                reference.backgroundColor = UIColor.whiteColor;
                reference.accessibilityIdentifier = @"tolkara.reference-input";
                [host addSubview:reference];
                [reference becomeFirstResponder];
                return;
            }
            if (selfTest) TestControllerModes(controls);
            [controls toggleKeyboard];
            if (!selfTest) return;
            [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
                (void)timer;
                [host layoutIfNeeded];
                assert(controls.keyboardVisible && CGSizeEqualToSize(originalSize, host.bounds.size));
                assert(host.keyboardLayoutGuide.layoutFrame.size.height > 100);
                UIButton *mouse = [controls valueForKey:@"_trackpadButton"];
                assert(CGRectGetMaxY(mouse.frame) <= CGRectGetMinY(host.keyboardLayoutGuide.layoutFrame));
                assert(CGRectGetMinY(controls.frame) >= 0);
                CGRect toolbarFrame = controls.frame;
                assert(CGRectEqualToRect(controls.frame, host.bounds));
                CGRect toolbarSafe = CGRectInset(UIEdgeInsetsInsetRect(controls.bounds, host.safeAreaInsets), 8, 8);
                assert(CGRectContainsRect(toolbarSafe, mouse.frame));
                UITextView *input = (UITextView *)AKFindInputView(host, @"wolkaraforever.keyboard.draft");
                UIButton *insert = (UIButton *)AKFindInputView(host, @"wolkaraforever.keyboard.insert");
                UIButton *clear = (UIButton *)AKFindInputView(host, @"wolkaraforever.keyboard.clear");
                assert(input.isFirstResponder && [input conformsToProtocol:@protocol(UITextInput)]);
                assert(input.inputView == nil);
                assert(input.autocorrectionType == UITextAutocorrectionTypeYes);
                assert(input.spellCheckingType == UITextSpellCheckingTypeYes);
                assert(input.returnKeyType == UIReturnKeySend);
                assert(!input.superview.hidden && input.bounds.size.width > 100 && input.bounds.size.height >= 44);
                CGRect editor = [input convertRect:input.bounds toView:host];
                assert(CGRectGetMaxY(editor) < CGRectGetMinY(host.keyboardLayoutGuide.layoutFrame));
                assert(CGRectGetMinY(editor) >= CGRectGetMaxY(mouse.frame));
                AKInputFixtureView *fixture = (AKInputFixtureView *)self.guest.contentView;
                // Reopening with unknown existing text starts an empty draft;
                // an explicit empty replacement must clear the entire field.
                [fixture.text setString:@"Previous synthetic value"];
                fixture.selection = NSMakeRange(4, 0);
                assert(!input.text.length && insert.enabled);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                // Which of the three went wrong, said out loud. A bare assert in a fixture
                // whose only output is a console log tells the reader that something
                // moved and nothing about what, which is half a report.
                if (fixture.text.length || insert.enabled || fixture.replacements != 1) {
                    fprintf(stderr, "TOUCH_UI_INSERT_MISMATCH: guest text=%s insert.enabled=%d replacements=%lu\n",
                            fixture.text.UTF8String ?: "", (int)insert.enabled,
                            (unsigned long)fixture.replacements);
                    fflush(stderr);
                }
                assert(!fixture.text.length && !insert.enabled && fixture.replacements == 1);
                assert(!controls.keyboardVisible && host.isFirstResponder);
                [controls toggleKeyboard];
                [fixture.text setString:@"A different old value"];
                fixture.selection = NSMakeRange(2, 3);
                [input insertText:@"Fixture @ñ🙂"];
                AKDrainFixtureEvents();
                assert([input.text isEqual:@"Fixture @ñ🙂"] && [fixture.text isEqual:@"A different old value"] && insert.enabled && clear.enabled);
                [input deleteBackward];
                assert([input.text isEqual:@"Fixture @ñ"]);
                // Editing an earlier range stays local; it must not append to
                // the game or emit backspaces until the user requests Insert.
                UITextPosition *end = [input positionFromPosition:input.beginningOfDocument offset:7];
                [input replaceRange:[input textRangeFromPosition:input.beginningOfDocument toPosition:end] withText:@"Draft"];
                assert([input.text isEqual:@"Draft @ñ"]);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"] && input.text.length == 0 && !insert.enabled && !clear.enabled);
                NSUInteger replacements = fixture.replacements;
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(0, 0) replacementText:@"\n"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"] && fixture.replacements == replacements);
                assert(!controls.keyboardVisible && host.isFirstResponder);
                [controls toggleKeyboard];
                // Provisional text and unfinished dictation cannot be inserted.
                [input setMarkedText:@" provisional" selectedRange:NSMakeRange(12, 0)];
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"]);
                [input setMarkedText:@" ¡Hola equipo!" selectedRange:NSMakeRange(@" ¡Hola equipo!".length, 0)];
                [input unmarkText];
                id placeholder = [input insertDictationResultPlaceholder];
                assert(placeholder);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"]);
                [input removeDictationResultPlaceholder:placeholder willInsertResult:YES];
                [input insertText:@" Dictado."];
                assert([input.text isEqual:@" ¡Hola equipo! Dictado."]);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                NSMutableString *expected = [@" ¡Hola equipo! Dictado." mutableCopy];
                assert([fixture.text isEqual:expected]);
                assert(!controls.keyboardVisible && host.isFirstResponder);
                [controls toggleKeyboard];
                // Many edits are now one normal document, not 64 resets of
                // UIKit's selection/undo context and 64 asynchronous forwards.
                for (NSUInteger i = 0; i < 64; i++) {
                    [input insertText:@"a"]; [input insertText:@"b"]; [input deleteBackward];
                    AKDrainFixtureEvents();
                    assert(input.text.length == i + 1 && [fixture.text isEqual:expected]);
                }
                NSString *draft = [input.text copy];
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                [expected setString:draft];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected] && !input.text.length);
                assert(!controls.keyboardVisible && host.isFirstResponder);
                [controls toggleKeyboard];
                [input insertText:@" discarded"];
                [clear sendActionsForControlEvents:UIControlEventTouchUpInside];
                assert(!input.text.length);
                [input insertText:@" failed recognition" ];
                [input setMarkedText:@" provisional" selectedRange:NSMakeRange(12, 0)];
                [input dictationRecognitionFailed];
                assert([input.text isEqual:@" failed recognition"]);
                [clear sendActionsForControlEvents:UIControlEventTouchUpInside];
                // Pasted controls are text, never implicit game commands.
                input.text = @"one\ntwo\tthree";
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                [expected setString:@"one two three"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected]);
                assert(!controls.keyboardVisible && host.isFirstResponder);
                [controls toggleKeyboard];
                UIStackView *accessory = (UIStackView *)controls.inputAccessoryView;
                // A correction replaces an earlier range in UIKit's document;
                // only the final corrected text and one Return reach the guest.
                [input insertText:@"teh message"];
                UITextPosition *wordEnd = [input positionFromPosition:input.beginningOfDocument offset:3];
                [input replaceRange:[input textRangeFromPosition:input.beginningOfDocument toPosition:wordEnd] withText:@"the"];
                [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(input.text.length, 0) replacementText:@"\n"];
                [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(input.text.length, 0) replacementText:@"\n"];
                AKDrainFixtureEvents();
                [expected setString:@"the message\r"];
                assert([fixture.text isEqual:expected] && !input.text.length);
                assert(!controls.keyboardVisible && host.isFirstResponder && input.superview.hidden);
                replacements = fixture.replacements;
                [(UIButton *)accessory.arrangedSubviews[5] sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected] && fixture.replacements == replacements);
                // Empty Send keeps an already populated game field, adds Return,
                // and closes; explicit empty Replace above remains a clear action.
                [controls toggleKeyboard];
                assert(input.inputView == nil);
                [(UIButton *)accessory.arrangedSubviews[5] sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                [expected appendString:@"\r"];
                assert([fixture.text isEqual:expected] && fixture.replacements == replacements);
                assert(!controls.keyboardVisible && host.isFirstResponder);
                // The accessory Return also sends a nonempty draft and closes.
                [controls toggleKeyboard];
                [input insertText:@"accessory send"];
                [(UIButton *)accessory.arrangedSubviews[5] sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                [expected setString:@"accessory send\r"];
                assert([fixture.text isEqual:expected]);
                assert(!controls.keyboardVisible && host.isFirstResponder);
                // A queued Send cannot submit after dismissal and a new session.
                [controls toggleKeyboard];
                [input insertText:@"cancelled send"];
                [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(input.text.length, 0) replacementText:@"\n"];
                [controls dismissKeyboard];
                [controls toggleKeyboard];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected] && !input.text.length && controls.keyboardVisible);
                [input insertText:@" close without inserting"];
                [controls dismissKeyboard]; [controls toggleKeyboard];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected] && !input.text.length);
                [input setMarkedText:@" discard me" selectedRange:NSMakeRange(11, 0)];
                [controls dismissKeyboard];
                [input insertText:@" late result"];
                [input removeDictationResultPlaceholder:placeholder willInsertResult:NO];
                [input unmarkText];
                assert(!input.text.length);
                [controls toggleKeyboard];
                [input insertText:@" cancelled on background"];
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
                [NSNotificationCenter.defaultCenter postNotificationName:UIWindowDidResignKeyNotification object:input.window];
                assert(controls.keyboardVisible && input.text.length);
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
                assert(!controls.keyboardVisible && !input.text.length && input.superview.hidden);
                [input insertText:@" background result"];
                [host layoutIfNeeded];
                assert(CGRectEqualToRect(toolbarFrame, controls.frame));
                [controls setGamepadVisible:NO]; [host layoutIfNeeded];
                assert(CGRectEqualToRect(toolbarFrame, controls.frame));

                [fixture.text setString:@""]; fixture.selection=NSMakeRange(0,0);
                // --- what dictation types into -----------------------------------------
                //
                // The controls announce themselves as the game's text input, because they
                // are the layer's UIKeyInput and their delegate is what posts the guest's
                // keys. Dictation sends them touchInsertText: and
                // touchSpecialKey:characters: without asking whether they exist, so they
                // must answer both, and the words must reach the guest. The announced
                // object used to be the draft editor, which answers neither: the first
                // transcript aborted the app ("unrecognized selector", Dadpad,
                // 2026-10-21).
                assert([controls respondsToSelector:@selector(touchInsertText:)] &&
                       [controls respondsToSelector:@selector(touchSpecialKey:characters:)]);
                [controls touchInsertText:@"a"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"a"]);
                [controls touchSpecialKey:53 characters:@"\x1b"];
                AKDrainFixtureEvents();
                assert(!fixture.text.length);
                // Reopening always uses UIKit's system input view, including
                // after a hidden or floating keyboard reports a short frame.
                [controls toggleKeyboard];
                [NSNotificationCenter.defaultCenter postNotificationName:UIKeyboardDidShowNotification object:nil
                    userInfo:@{UIKeyboardFrameEndUserInfoKey: [NSValue valueWithCGRect:CGRectZero]}];
                AKDrainFixtureEvents();
                assert(input.inputView == nil);
                [controls dismissKeyboard];
                [host layoutIfNeeded];
                [fixture.text setString:@""];
                fixture.selection = NSMakeRange(0, 0);
                NSLog(@"native: the announced text target answers dictation and reaches the guest");
                // The one control that leaves a guest screen with no quit of its own. It asks
                // the guest's own application object to terminate, which is the game's
                // save-and-quit path; the tap itself runs in the adapter and is not exercised
                // here because it would end the fixture.
                UIButton *leave = (UIButton *)AKFindInputView(host, @"wolkaraforever.leaveGame");
                assert(leave && [leave.accessibilityLabel isEqual:@"Leave the game"]);
                NSLog(@"native: the toolbar carries Leave the game");
                [fixture.text setString:expected];

                [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
                    (void)timer;
                    assert([fixture.text isEqual:expected]);
                    assert(!controls.keyboardVisible && host.isFirstResponder);
                    NSLog(@"TOUCH_UI_SELF_TEST_PASS: system keyboard, autocorrection traits, send/dismiss, whole-field replacement, empty clearing, duplicate suppression, draft editing, dictation and cancellation");
                    exit(EXIT_SUCCESS);
                }];
            }];
        }];
    }
}
@end

@interface AKInputFixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation AKInputFixtureApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Input fixture" sessionRole:session.role];
    config.delegateClass = AKInputFixtureScene.class;
    return config;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AKInputFixtureApp.class)); } }
