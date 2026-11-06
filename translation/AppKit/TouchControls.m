#import "TouchControls.h"
#import "AKSupport.h"
#import "AKHostLocalization.h"
#import "TouchTrackpad.h"
#import "TouchGamepadLayout.h"
#import "TouchGamepad.h"
#import "TouchHaptics.h"
#import <objc/runtime.h>

static char AKPrivateInputEventKey;
void AKMarkPrivateInputEvent(id event) {
    objc_setAssociatedObject(event, &AKPrivateInputEventKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
BOOL AKIsPrivateInputEvent(id event) { return [objc_getAssociatedObject(event, &AKPrivateInputEventKey) boolValue]; }

// Null until the app's shell says which keys are the user's; null means "nothing is owned",
// which is the behaviour without the feature and what a fixture that links only the adapter
// gets.
BOOL (*AKTouchKeyIsTakenForVoice)(unsigned short usage) = NULL;

NSNotificationName const AKTouchOwnedKeyUsagesDidChangeNotification = @"AKTouchOwnedKeyUsagesDidChange";
NSString *const AKTouchOwnedKeyUsagesKey = @"usages";

// The usages the user has taken, kept here because this file is where the answer is needed:
// the adapter asks about a key it is about to post to the guest.
static NSSet<NSNumber *> *AKTouchOwnedKeyUsages = nil;

static BOOL AKTouchUsageIsTaken(unsigned short usage) {
    return [AKTouchOwnedKeyUsages containsObject:@(usage)];
}

// Posted when the game's own text view exists, with that view as the object. Dictation
// types into it and nowhere else; the alternative - searching every window in every
// scene for something that answers a private selector - is not a thing to do while a
// game is running. Shell/main.m is the observer, because it is what knows about both
// this adapter and the voice module.
NSNotificationName const AKTouchGameTextInputDidAppearNotification = @"AKTouchGameTextInputDidAppear";

NSNotificationName const AKTouchKeyboardRequestNotification = @"AKTouchKeyboardRequestNotification";
// Posted when the user has asked to leave twice and the guest still refused to quit: the shell,
// which owns the session and what it has to flush, closes WolkaraForever. Named as a string on the
// shell's side for the same reason as the two notifications above - the adapter is a dylib the
// app does not link.
NSNotificationName const AKTouchCloseAppNotification = @"AKTouchCloseAppNotification";
// The keys the launcher's and the platform's switches read. The trackpad string
// is the one the platform already stored, so an existing choice carries over.
NSString *const AKTouchControlsDefaultsKey = @"AKTouchControls";
static NSString *const AKDictationLocaleKey = @"AKToolbarDictationLocale";
static NSString *const AKTouchTrackpadDefaultsKey = @"TKTouchTrackpadEnabled";
// The composer's placeholder when nothing has been dictated or typed: it says what the field
// does, so an empty box is not mistaken for the game's own text.
static NSString *AKComposerDefaultLabel(void) { return AKHostLocalized(@"touch.draft.placeholder"); }
@interface AKTouchControls (KeyboardState)
- (void)updateKeyboardButton;
- (void)updateDraftButtons;
- (void)replaceGameText:(NSString *)text;
// YES while the user has asked for the draft keyboard and it has not been
// dismissed: the draft editor uses it to decide whether to take focus back when
// a system panel (dictation) has finished with it.
- (BOOL)keyboardRequested;
- (BOOL)voiceDraftActive;
- (void)prepareVoiceDraftForEditing;
- (void)confirmDictation;
@end

// A normal, visible UIKit document. Editing and dictation stay local until
// Send or Replace is requested; never reset the text context on every keyboard callback.
@interface AKKeyboardTextView : UITextView <UITextViewDelegate>
@property (nonatomic, weak) AKTouchControls *inputOwner;
- (BOOL)forwardCommittedText;
- (BOOL)commitDraftSendingReturn:(BOOL)sendReturn;
- (void)discardDraft;
- (void)beginVoiceDraft;
- (void)cancelDraftSession;
- (NSString *)reviewedDraftText;
- (BOOL)canModifyDraft;
- (BOOL)canReplaceField;
@end

@implementation AKKeyboardTextView {
    NSMutableSet *_dictationPlaceholders;
    BOOL _acceptingInput, _didSubmitDraft, _resignedForDictation, _committingDraft;
    NSUInteger _session;
}
- (instancetype)initWithFrame:(CGRect)frame textContainer:(NSTextContainer *)container {
    if ((self = [super initWithFrame:frame textContainer:container])) {
        self.delegate = self;
        _dictationPlaceholders = [NSMutableSet new];
        self.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        self.textColor = UIColor.whiteColor;
        self.tintColor = UIColor.systemCyanColor;
        self.font = [UIFont systemFontOfSize:17];
        self.layer.cornerRadius = 8;
        self.accessibilityLabel = AKHostLocalized(@"touch.draft.label");
        self.accessibilityHint = AKHostLocalized(@"touch.draft.hint");
        self.accessibilityLanguage = AKHostLanguageCode();
        self.accessibilityIdentifier = @"wolkaraforever.keyboard.draft";
        self.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.autocorrectionType = UITextAutocorrectionTypeYes;
        self.spellCheckingType = UITextSpellCheckingTypeYes;
        self.smartQuotesType = UITextSmartQuotesTypeNo;
        self.smartDashesType = UITextSmartDashesTypeNo;
        self.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
        self.returnKeyType = UIReturnKeySend;
        self.secureTextEntry = NO;
    }
    return self;
}
- (UIView *)inputAccessoryView { return self.inputOwner.inputAccessoryView; }
- (BOOL)canModifyDraft { return _acceptingInput && !_dictationPlaceholders.count && !self.markedTextRange; }
- (BOOL)canReplaceField { return [self canModifyDraft] && (self.hasText || !_didSubmitDraft); }
- (BOOL)textViewShouldBeginEditing:(UITextView *)view {
    (void)view;
    if (self.inputOwner.voiceDraftActive) [self.inputOwner prepareVoiceDraftForEditing];
    return YES;
}
- (void)textViewDidChange:(UITextView *)view {
    (void)view;
    _didSubmitDraft = NO;
    [self.inputOwner updateDraftButtons];
}
- (void)textViewDidChangeSelection:(UITextView *)view { (void)view; [self.inputOwner updateDraftButtons]; }
- (void)discardDraft {
    [super setText:@""];
    [self.undoManager removeAllActions];
    [self.inputOwner updateDraftButtons];
}
- (void)beginVoiceDraft {
    _session++; _acceptingInput = YES; _didSubmitDraft = NO;
    [self discardDraft];
}
- (void)cancelDraftSession {
    _session++; _acceptingInput = NO; _resignedForDictation = NO;
    [_dictationPlaceholders removeAllObjects];
    if (self.markedTextRange) { [super setMarkedText:@"" selectedRange:NSMakeRange(0, 0)]; [super unmarkText]; }
    [super resignFirstResponder];
    [self discardDraft];
}
- (NSString *)reviewedDraftText {
    if (![self canModifyDraft]) return nil;
    if (self.isFirstResponder) {
        _committingDraft = YES;
        BOOL accepted = [self resignFirstResponder];
        _committingDraft = NO;
        if (!accepted) return nil;
    }
    return self.text;
}
- (BOOL)forwardCommittedText { return [self commitDraftSendingReturn:NO]; }
- (BOOL)commitDraftSendingReturn:(BOOL)sendReturn {
    if (self.inputOwner.voiceDraftActive) {
        [self.inputOwner confirmDictation];
        return YES;
    }
    if (![self canReplaceField]) return NO;
    // Let UIKit finish its current correction before reading the final document.
    // Ordinary cancellation clears the draft; submission preserves it until here.
    _committingDraft = YES;
    BOOL resigned = [self resignFirstResponder];
    _committingDraft = NO;
    if (!resigned) return NO;
    // Drafts cannot send Return/Tab or other control keys by pasting text.
    // Those keys remain explicit actions in the accessory bar.
    NSString *text = [[self.text componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet]
        componentsJoinedByString:@" "];
    [self discardDraft];
    // Once cleared after submission, repeated taps/queued Send callbacks must
    // not turn a successful replacement into an accidental empty replacement.
    _didSubmitDraft = YES;
    [self.inputOwner updateDraftButtons];
    // Empty Send presses Return on the existing game field. Only explicit Replace
    // can clear that field; reopening the keyboard never reads the guest's text.
    if (!sendReturn || text.length) [self.inputOwner replaceGameText:text];
    if (sendReturn) [self.inputOwner touchSpecialKey:36 characters:@"\r"];
    [self.inputOwner dismissKeyboard];
    return YES;
}
- (BOOL)becomeFirstResponder {
    if (!self.isFirstResponder) _didSubmitDraft = NO;
    _acceptingInput = YES;
    BOOL accepted = [super becomeFirstResponder];
    _acceptingInput = accepted;
    [self.inputOwner updateKeyboardButton];
    return accepted;
}
- (BOOL)resignFirstResponder {
    BOOL accepted = [super resignFirstResponder];
    if (accepted) {
        _session++;
        if (_dictationPlaceholders.count) {
            // The system dictation UI takes focus while the microphone listens.
            // The draft and the pending result are the user's: keep both, and
            // take focus back when the session ends (endDictationSessionIfIdle).
            // Only a pending dictation placeholder says so: text a keyboard is
            // still composing is discarded like any other draft.
            _resignedForDictation = YES;
            AKLog(@"draft editor resigned with dictation pending; keeping the draft");
        } else {
            _acceptingInput = NO;
            [_dictationPlaceholders removeAllObjects];
            if (!_committingDraft) [self discardDraft];
        }
    }
    [self.inputOwner updateKeyboardButton];
    return accepted;
}
// The dictation session has finished. If it left the editor without focus, take
// it back so the dictated draft is visible and Replace works, as it was before.
- (void)endDictationSessionIfIdle {
    if (_dictationPlaceholders.count || self.markedTextRange || !_resignedForDictation) return;
    _resignedForDictation = NO;
    if (!self.inputOwner.keyboardRequested) return;
    AKLog(@"dictation session ended without focus; restoring the draft keyboard");
    __weak AKKeyboardTextView *weakSelf = self;
    [NSRunLoop.mainRunLoop performInModes:@[NSRunLoopCommonModes] block:^{
        AKKeyboardTextView *input = weakSelf;
        if (input && input.inputOwner.keyboardRequested && !input.isFirstResponder) [input becomeFirstResponder];
    }];
}
- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    (void)textView; (void)range;
    if ([text isEqual:@"\n"]) {
        // Send commits the corrected draft, presses Return and dismisses. Defer
        // until UIKit finishes this edit; do not mutate its document here.
        NSUInteger session = _session;
        __weak AKKeyboardTextView *weakSelf = self;
        [NSRunLoop.mainRunLoop performInModes:@[NSRunLoopCommonModes] block:^{
            AKKeyboardTextView *input = weakSelf;
            if (input && input->_session == session) [input commitDraftSendingReturn:YES];
        }];
        return NO;
    }
    return _acceptingInput;
}
- (void)insertText:(NSString *)text { if (_acceptingInput) [super insertText:text]; }
- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
    if (_acceptingInput) [super replaceRange:range withText:text];
}
- (void)setMarkedText:(NSString *)text selectedRange:(NSRange)range {
    if (_acceptingInput) [super setMarkedText:text selectedRange:range];
}
- (void)unmarkText { if (_acceptingInput) [super unmarkText]; }
- (id)insertDictationResultPlaceholder {
    if (!self.inputOwner.keyboardRequested) return [NSObject new];
    // Dictation can start while the system panel, not this editor, holds focus:
    // the result is still the user's draft, so accept it from here on. UIKit also
    // requires a placeholder for the session to start at all: refusing it is how
    // "the microphone is visible but tapping it does nothing" looks.
    _acceptingInput = YES;
    // UITextView implements the dictation selectors on some systems and not on
    // others, and sending one it does not have aborts the app. Ask first, and
    // hand back our own token when the superclass has nothing, because the
    // session cannot start without a placeholder.
    id placeholder = nil;
    if ([UITextView instancesRespondToSelector:@selector(insertDictationResultPlaceholder)]) {
        placeholder = [super insertDictationResultPlaceholder];
    }
    if (!placeholder) placeholder = [[NSObject alloc] init];
    [_dictationPlaceholders addObject:placeholder];
    AKLog(@"dictation placeholder inserted=%d pending=%lu accepting=%d", placeholder != nil, (unsigned long)_dictationPlaceholders.count, _acceptingInput);
    [self.inputOwner updateDraftButtons];
    return placeholder;
}
- (void)removeDictationResultPlaceholder:(id)placeholder willInsertResult:(BOOL)willInsert {
    if (![_dictationPlaceholders containsObject:placeholder]) return;
    if ([UITextView instancesRespondToSelector:@selector(removeDictationResultPlaceholder:willInsertResult:)]) {
        [super removeDictationResultPlaceholder:placeholder willInsertResult:willInsert];
    }
    [_dictationPlaceholders removeObject:placeholder];
    AKLog(@"dictation placeholder removed willInsertResult=%d pending=%lu", willInsert, (unsigned long)_dictationPlaceholders.count);
    [self.inputOwner updateDraftButtons];
    [self endDictationSessionIfIdle];
}
// Lengths only: never log or retain what was dictated.
- (void)insertDictationResult:(NSArray<UIDictationPhrase *> *)dictationResult {
    if (!self.inputOwner.keyboardRequested) return;
    NSUInteger characters = 0;
    for (UIDictationPhrase *phrase in dictationResult) characters += phrase.text.length;
    AKLog(@"dictation result: %lu phrases, %lu characters", (unsigned long)dictationResult.count, (unsigned long)characters);
    // UITextView does not implement this selector. UIKit sends it to whichever
    // responder holds the session's placeholder, so forwarding it to super
    // raises NSInvalidArgumentException and the app dies the instant dictation
    // finishes. Insert the phrases as ordinary input instead, the same way the
    // dictated text would have arrived.
    _acceptingInput = YES;
    for (UIDictationPhrase *phrase in dictationResult) {
        if (phrase.text.length) [self insertText:phrase.text];
    }
    [self.inputOwner updateDraftButtons];
}
- (void)dictationRecognitionFailed {
    AKLog(@"dictation recognition failed (markedText=%d, placeholders=%lu)", self.markedTextRange != nil, (unsigned long)_dictationPlaceholders.count);
    // UITextView does not implement this optional callback. Preserve the
    // completed draft; only discard the provisional recognition segment.
    if (self.markedTextRange) {
        [super setMarkedText:@"" selectedRange:NSMakeRange(0, 0)];
        [super unmarkText];
    }
    [_dictationPlaceholders removeAllObjects];
    [self.inputOwner updateDraftButtons];
    [self endDictationSessionIfIdle];
}
@end

@interface AKTouchControls () <UIGestureRecognizerDelegate>
@end

@implementation AKTouchControls {
    UIButton *_keyboardButton, *_trackpadButton, *_gamepadButton, *_settingsButton, *_leaveButton;
    UIButton *_insertDraftButton, *_clearDraftButton;
    UIButton *_savedTextButton;
    UILongPressGestureRecognizer *_savedTextHold, *_gamepadHold;
    BOOL _savedTextHeld, _savedTextEditing;
    BOOL _gamepadEnabled, _gamepadSimple, _gamepadHeld, _keyboardRequested;
    UIView *_accessory, *_composer;
    NSTimer *_holdTimer;
    AKKeyboardTextView *_keyboardInput;
    AKTrackpad _pad;
    AKTouchHaptics *_haptics;
    AKTouchGamepad *_gamepad;
    BOOL _tookOwnPlace;
    UIView *_dictationGroup;
    UIButton *_dictateButton, *_dictationSendButton, *_dictationCancelButton, *_dictationLanguageButton;
    NSLayoutConstraint *_dictationLanguageWidth, *_draftTextTop, *_composerHeight;
    NSString *_dictationLocale;
    UILabel *_dictationStatus, *_draftLabel;
    UIControl *_dictationShield;
    NSString *_dictationState;
    UIMenu *_mouseMenu;
    NSMutableDictionary<NSString *, NSValue *> *_toolbarDragOrigins;
    NSUInteger _statusGeneration;
}

// This dylib is loaded by name, so nothing here can be called by the shell at link time. The
// one channel is the notification that says which keys the user has taken, where it is
// received - and the pointer is set here, because until it arrives nothing is owned and every
// key goes to the game.
+ (void)load {
    [NSNotificationCenter.defaultCenter addObserverForName:AKTouchOwnedKeyUsagesDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        id usages = note.userInfo[AKTouchOwnedKeyUsagesKey];
        if ([usages isKindOfClass:NSSet.class]) AKTouchOwnedKeyUsages = [usages copy];
        else if ([usages isKindOfClass:NSArray.class]) AKTouchOwnedKeyUsages = [NSSet setWithArray:usages];
        else AKTouchOwnedKeyUsages = nil;
        // Null when nothing is taken, so the check at the adapter's door is one nil test in
        // the common case rather than a set lookup per key.
        AKTouchKeyIsTakenForVoice = AKTouchOwnedKeyUsages.count ? AKTouchUsageIsTaken : NULL;
        AKLog(@"the user's keys: %lu taken (the game will not see those)",
              (unsigned long)AKTouchOwnedKeyUsages.count);
    }];
}

// The launcher's switch, and the platform's install path, ask this before the
// controls are added. A stored choice wins; without one they are on, because
// this product wants them on every device it runs on.
+ (BOOL)enabled {
    NSNumber *saved = [NSUserDefaults.standardUserDefaults objectForKey:AKTouchControlsDefaultsKey];
    return [saved isKindOfClass:NSNumber.class] ? saved.boolValue : YES;
}

static void AKEmitTouch(void *context, AKTrackpadAction action, double x, double y, unsigned button) {
    AKTouchControls *controls = (__bridge AKTouchControls *)context;
    switch (action) {
        case AKTrackpadMove: [controls.delegate touchMoveBy:CGPointMake(x, y)]; break;
        case AKTrackpadScroll: [controls.delegate touchScrollBy:CGPointMake(x, y)]; break;
        case AKTrackpadDown: [controls.delegate touchButton:button pressed:YES]; break;
        case AKTrackpadUp: [controls.delegate touchButton:button pressed:NO]; break;
    }
}

- (UIButton *)buttonWithSymbol:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.45];
    button.layer.cornerRadius = 22;
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.4].CGColor;
    button.accessibilityLabel = label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(buttonTouchDown) forControlEvents:UIControlEventTouchDown];
    [self addSubview:button];
    return button;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.zPosition = 100001;
        // VoiceOver reads what is under this view in the app's language, not the iPad's, so a
        // German HUD and German keyboard keys are pronounced as German.
        self.accessibilityLanguage = AKHostLanguageCode();
        _haptics = [AKTouchHaptics new];
        _keyboardInput = [[AKKeyboardTextView alloc] initWithFrame:CGRectMake(0, 0, 1, 1) textContainer:nil];
        _keyboardInput.inputOwner = self;
        // Announced, not reached for. The game's text input is this view, not the draft
        // editor: this one is the layer's UIKeyInput, and its delegate is what posts the
        // key events into the guest. The draft editor is a UITextView that holds words for
        // Replace and cannot reach the game at all. Announcing the wrong one is not a
        // cosmetic mistake - the first transcript sent to it aborted the app with
        // "-[AKKeyboardTextView touchInsertText:]: unrecognized selector" (measured on
        // Dadpad, 2026-10-21).
        [NSNotificationCenter.defaultCenter postNotificationName:AKTouchGameTextInputDidAppearNotification
                                                        object:self];
        [self buildComposer];
        _keyboardButton = [self buttonWithSymbol:@"keyboard" label:AKHostLocalized(@"touch.keyboard.show") action:@selector(toggleKeyboard)];
        _keyboardButton.accessibilityIdentifier = @"tolkara.keyboard";
        _trackpadButton = [self buttonWithSymbol:@"cursorarrow" label:AKHostLocalized(@"touch.trackpad.enable") action:@selector(toggleTrackpad)];
        // Optical centering for the left-leaning symbol; keep its hit area fixed.
        _trackpadButton.imageView.transform = CGAffineTransformMakeTranslation(4, 0);
        _trackpadButton.accessibilityIdentifier = @"tolkara.trackpad";
        _gamepadButton = [self buttonWithSymbol:@"gamecontroller" label:AKHostLocalized(@"touch.gamepad.automatic") action:@selector(toggleGamepad)];
        _gamepadButton.accessibilityIdentifier = @"tolkara.gamepad";
        [_gamepadButton addTarget:self action:@selector(gamepadTouchDown) forControlEvents:UIControlEventTouchDown];
        _gamepadHold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdGamepad:)];
        _gamepadHold.minimumPressDuration = 0.6; _gamepadHold.cancelsTouchesInView = YES;
        _gamepadHold.delegate = self; [_gamepadButton addGestureRecognizer:_gamepadHold];
        _gamepadButton.accessibilityCustomActions = @[[[UIAccessibilityCustomAction alloc]
            initWithName:AKHostLocalized(@"touch.gamepad.toggleEnabled") target:self selector:@selector(toggleGamepadEnabled)]];
        _settingsButton = [self buttonWithSymbol:@"gearshape" label:AKHostLocalized(@"touch.settings") action:@selector(showControlSettings)];
        _settingsButton.accessibilityIdentifier = @"wolkaraforever.controlSettings";
        // A way out of the game from any screen. Until this existed, a guest screen with no
        // quit of its own - the login screen is one - left the user with no control that
        // returned to WolkaraForever's launcher at all, and closing the app was the only exit
        // (reported on Dadpad, 2026-10-21). It closes WolkaraForever, which ends the guest with it.
        _leaveButton=[self buttonWithSymbol:@"house" label:AKHostLocalized(@"touch.leave") action:@selector(leaveGame)];
        _leaveButton.accessibilityIdentifier=@"wolkaraforever.leaveGame";
        _leaveButton.accessibilityHint=AKHostLocalized(@"touch.leave.hint");
        // Said once at build time so a device run can be read back without a tap.
        AKLog(@"toolbar: leave game control on the toolbar (house; asks the guest to terminate)");
        _gamepadButton.accessibilityHint = AKHostLocalized(@"touch.gamepad.hint");
        NSNumber *gamepad = [NSUserDefaults.standardUserDefaults objectForKey:@"TKTouchGamepadEnabled"];
        _gamepadEnabled = gamepad ? gamepad.boolValue : YES;
        _gamepadSimple = [NSUserDefaults.standardUserDefaults boolForKey:@"TKTouchGamepadSimple"];
        [self setGamepadVisible:NO];
        _trackpadButton.accessibilityHint = AKHostLocalized(@"touch.trackpad.hint");
        __weak AKTouchControls *weakSelf = self;
        NSMutableArray<UIAction *> *actions = [NSMutableArray new];
        NSArray<NSString *> *buttons = @[AKHostLocalized(@"touch.mouse.left"), AKHostLocalized(@"touch.mouse.right"),
                                         AKHostLocalized(@"touch.mouse.middle")];
        for (unsigned i = 0; i < buttons.count; i++) {
            [actions addObject:[UIAction actionWithTitle:buttons[i] image:nil identifier:nil handler:^(UIAction *action) {
                (void)action;
                AKTouchControls *controls = weakSelf;
                [controls cancelTouches];
                [controls.delegate touchButton:i pressed:YES];
                [controls.delegate touchButton:i pressed:NO];
            }]];
        }
        _mouseMenu = [UIMenu menuWithTitle:@"Mouse buttons" children:actions];
        _trackpadButton.menu = _mouseMenu;
        _dictationState = @"idle";
        _dictationShield = [UIControl new];
        _dictationShield.hidden = YES;
        _dictationShield.accessibilityElementsHidden = YES;
        [self insertSubview:_dictationShield atIndex:0];
        _dictationGroup = [UIView new];
        _dictationGroup.accessibilityIdentifier = @"wolkaraforever.dictationGroup";
        [self addSubview:_dictationGroup];
        _dictateButton = [self buttonWithSymbol:@"mic.fill" label:AKHostLocalized(@"touch.dictation.start") action:@selector(startDictation)];
        _dictateButton.accessibilityIdentifier = @"wolkaraforever.dictate";
        _dictationSendButton = [self buttonWithSymbol:@"checkmark" label:AKHostLocalized(@"touch.dictation.send") action:@selector(confirmDictation)];
        _dictationSendButton.accessibilityIdentifier = @"wolkaraforever.dictationSend";
        _dictationSendButton.tintColor = UIColor.systemGreenColor;
        _dictationCancelButton = [self buttonWithSymbol:@"xmark" label:AKHostLocalized(@"touch.dictation.cancel") action:@selector(cancelDictation)];
        _dictationCancelButton.accessibilityIdentifier = @"wolkaraforever.dictationCancel";
        _dictationCancelButton.tintColor = UIColor.systemRedColor;
        for (UIButton *button in @[_dictateButton, _dictationSendButton, _dictationCancelButton]) [_dictationGroup addSubview:button];
        _dictationSendButton.hidden = _dictationCancelButton.hidden = YES;
        _savedTextButton = [self buttonWithSymbol:@"key.fill" label:AKHostLocalized(@"touch.savedText.title") action:@selector(editSavedText)];
        _savedTextButton.accessibilityIdentifier = @"wolkaraforever.savedText";
        _savedTextButton.accessibilityHint = AKHostLocalized(@"touch.savedText.instructions");
        [_savedTextButton addTarget:self action:@selector(savedTextTouchDown) forControlEvents:UIControlEventTouchDown];
        [self addSubview:_savedTextButton];
        _savedTextHold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdSavedText:)];
        _savedTextHold.minimumPressDuration = 0.6;
        _savedTextHold.cancelsTouchesInView = YES;
        _savedTextHold.delegate = self;
        [_savedTextButton addGestureRecognizer:_savedTextHold];
        _dictationStatus = [UILabel new];
        _dictationStatus.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _dictationStatus.textColor = UIColor.whiteColor;
        _dictationStatus.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.75];
        _dictationStatus.textAlignment = NSTextAlignmentCenter;
        _dictationStatus.numberOfLines = 0;
        _dictationStatus.hidden = YES;
        [self addSubview:_dictationStatus];
        _toolbarDragOrigins = [NSMutableDictionary new];
        for (UIView *item in [self toolbarItems]) {
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveToolbarItem:)];
            pan.delegate = self;
            [item addGestureRecognizer:pan];
        }
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(dictationStateChanged:)
            name:@"AKTouchDictationState" object:self];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(savedTextEditorState:)
            name:@"AKTouchSavedTextEditorState" object:self];
        NSNumber *saved = [NSUserDefaults.standardUserDefaults objectForKey:AKTouchTrackpadDefaultsKey];
        self.trackpadEnabled = saved ? saved.boolValue : UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspendInput:) name:UIApplicationWillResignActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backgroundInput:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowResigned:) name:UIWindowDidResignKeyNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(controlAppearanceChanged:)
            name:AKGamepadLayoutDidChangeNotification object:NSUserDefaults.standardUserDefaults];    // Whether the system keyboard (and so its dictation button) exists at all on
    // this device, and whether UIKit is talking to our draft editor when it does.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(systemKeyboardShown:) name:UIKeyboardDidShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(systemKeyboardHidden:) name:UIKeyboardDidHideNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardRequestedByGuest:) name:AKTouchKeyboardRequestNotification object:nil];        [self controlAppearanceChanged:nil];
    }
    return self;
}

- (NSArray<UIView *> *)toolbarItems {
    return @[_trackpadButton, _keyboardButton, _gamepadButton, _settingsButton, _leaveButton, _dictationGroup, _savedTextButton];
}
- (void)controlAppearanceChanged:(NSNotification *)notification {
    (void)notification;
    AKGamepadLayout *layout = _gamepad.layout ?: [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    _haptics.enabled = layout.hapticsEnabled;
    BOOL editing = _gamepad.editing;
    for (UIButton *button in @[_trackpadButton, _keyboardButton, _gamepadButton, _settingsButton, _leaveButton,
                               _dictateButton, _dictationSendButton, _dictationCancelButton, _savedTextButton]) {
        button.alpha = editing ? MAX(0.6, layout.opacity) : layout.opacity;
        button.layer.borderColor = (editing ? UIColor.systemYellowColor : [UIColor.whiteColor colorWithAlphaComponent:0.4]).CGColor;
        button.layer.borderWidth = editing ? 2 : 0.5;
    }
    _trackpadButton.menu = editing ? nil : _mouseMenu;
    [self setNeedsLayout];
}
- (void)buttonTouchDown { if (!_gamepad.editing) [_haptics buttonPressed]; }

- (CGRect)toolbarBounds {
    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.superview.safeAreaInsets);
    return CGRectInset(safe, 8, 8);
}
- (void)placeToolbarInHost:(UIView *)host {
    if (self.superview != host) return;
    if (!_tookOwnPlace) {
        _tookOwnPlace = YES;
        NSMutableArray<NSLayoutConstraint *> *theirs = [NSMutableArray array];
        for (NSLayoutConstraint *constraint in host.constraints)
            if (constraint.firstItem == self || constraint.secondItem == self) [theirs addObject:constraint];
        [NSLayoutConstraint deactivateConstraints:theirs];
        self.translatesAutoresizingMaskIntoConstraints = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    // A pass-through surface allows each button to be moved anywhere in the safe area.
    self.frame = host.bounds;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.superview) [self placeToolbarInHost:self.superview];
    _dictationShield.frame = self.bounds;
    CGRect safe = [self toolbarBounds];
    AKGamepadLayout *layout = _gamepad.layout;
    NSArray<UIView *> *items = [self toolbarItems];
    BOOL compact = safe.size.width < 408;
    CGFloat width = compact ? 252 : 408;
    CGFloat x = CGRectGetMidX(safe) - width / 2;
    for (NSUInteger index = 0; index < items.count; index++) {
        UIView *item = items[index];
        CGRect fallback = CGRectMake(x + index * 52, safe.origin.y, index == 5 ? 96 : 44, 44);
        if (compact && index == 5) fallback = CGRectMake(CGRectGetMidX(safe)-48, safe.origin.y+52, 96, 44);
        if (index == 6) fallback = compact ? CGRectMake(CGRectGetMidX(safe)+56, safe.origin.y+52, 44, 44) : CGRectMake(x+364, safe.origin.y, 44, 44);
        item.frame = layout ? [layout frameForItem:item.accessibilityIdentifier defaultFrame:fallback inBounds:safe] : fallback;
    }
    _dictateButton.frame = CGRectMake(26, 0, 44, 44);
    _dictationSendButton.frame = CGRectMake(0, 0, 44, 44);
    _dictationCancelButton.frame = CGRectMake(52, 0, 44, 44);
    CGFloat labelWidth = MIN(280, safe.size.width);
    CGFloat labelX = MAX(safe.origin.x, MIN(CGRectGetMidX(_dictationGroup.frame)-labelWidth/2, CGRectGetMaxX(safe)-labelWidth));
    CGFloat labelY = CGRectGetMaxY(_dictationGroup.frame)+4;
    if (labelY+60 > CGRectGetMaxY(safe)) labelY = CGRectGetMinY(_dictationGroup.frame)-64;
    _dictationStatus.frame = CGRectMake(labelX, MAX(safe.origin.y, labelY), labelWidth, 60);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer == _gamepadHold) return !_gamepad.configuring;
    if (recognizer == _savedTextHold) return !_gamepad.configuring && !self.voiceDraftActive && !_keyboardRequested && !_savedTextEditing;
    return _gamepad.editing;
}
- (void)savedTextTouchDown { _savedTextHeld = NO; }
- (void)savedTextEditorState:(NSNotification *)note { _savedTextEditing = [note.userInfo[@"active"] boolValue]; }
- (void)editSavedText {
    if (_savedTextHeld || _gamepad.configuring || self.voiceDraftActive || _savedTextEditing) return;
    [self cancelTouches]; [self dismissKeyboard];
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchSavedTextAction" object:self userInfo:@{@"action":@"edit"}];
}
- (void)holdSavedText:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan || _savedTextHeld || _gamepad.configuring ||
        self.voiceDraftActive || _keyboardRequested || _savedTextEditing) return;
    _savedTextHeld = YES;
    [self cancelTouches];
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchSavedTextAction" object:self userInfo:@{@"action":@"type"}];
}
- (void)moveToolbarItem:(UIPanGestureRecognizer *)pan {
    if (!_gamepad.editing) return;
    UIView *item = pan.view;
    NSString *key = item.accessibilityIdentifier;
    if (!key) return;
    if (pan.state == UIGestureRecognizerStateBegan) _toolbarDragOrigins[key] = [NSValue valueWithCGRect:item.frame];
    NSValue *origin = _toolbarDragOrigins[key];
    if (!origin) return;
    CGRect frame = origin.CGRectValue;
    CGPoint delta = [pan translationInView:self];
    frame.origin.x += delta.x; frame.origin.y += delta.y;
    [_gamepad.layout moveItem:key toFrame:frame inBounds:[self toolbarBounds]];
    [self setNeedsLayout]; [self layoutIfNeeded];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [_gamepad.layout save];
        [_toolbarDragOrigins removeObjectForKey:key];
    }
}
- (NSString *)preferredDictationLocale {
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:AKDictationLocaleKey];
    NSString *identifier = [saved isKindOfClass:NSString.class] && [saved length] ? saved : _keyboardInput.textInputMode.primaryLanguage;
    if (!identifier.length || [identifier isEqual:@"emoji"]) identifier = NSLocale.preferredLanguages.firstObject ?: @"en-US";
    return [identifier stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
}
- (void)updateDictationLanguage {
    NSString *selected = _dictationLocale ?: [self preferredDictationLocale];
    NSMutableOrderedSet<NSString *> *locales = [NSMutableOrderedSet orderedSetWithArray:@[@"en-US",@"es-ES"]];
    [locales addObject:selected];
    for (UITextInputMode *mode in UITextInputMode.activeInputModes)
        if (mode.primaryLanguage.length && ![mode.primaryLanguage isEqual:@"emoji"])
            [locales addObject:[mode.primaryLanguage stringByReplacingOccurrencesOfString:@"_" withString:@"-"]];
    NSMutableArray<UIAction *> *actions = [NSMutableArray new];
    __weak AKTouchControls *weakSelf = self;
    for (NSString *identifier in locales) {
        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:identifier];
        NSString *name = [locale localizedStringForLocaleIdentifier:identifier] ?: identifier;
        UIAction *action = [UIAction actionWithTitle:name image:nil identifier:identifier handler:^(UIAction *choice) {
            (void)choice; [weakSelf selectDictationLocale:identifier];
        }];
        action.state = [identifier isEqual:selected] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    _dictationLanguageButton.menu = [UIMenu menuWithTitle:AKHostLocalized(@"touch.dictation.language.note") children:actions];
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:selected];
    NSString *name = [locale localizedStringForLanguageCode:locale.languageCode] ?: selected;
    [_dictationLanguageButton setTitle:[name stringByAppendingString:@" ▾"] forState:UIControlStateNormal];
    _dictationLanguageButton.accessibilityValue = name;
}
- (void)selectDictationLocale:(NSString *)identifier {
    if (!self.voiceDraftActive || [identifier isEqual:_dictationLocale]) return;
    _dictationLocale = identifier;
    [NSUserDefaults.standardUserDefaults setObject:identifier forKey:AKDictationLocaleKey];
    [self updateDictationLanguage];
    [self postDictationAction:@"language"];
}
- (void)postDictationAction:(NSString *)action {
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchDictationAction" object:self userInfo:@{@"action":action, @"locale":_dictationLocale ?: [self preferredDictationLocale], @"text":_keyboardInput.text ?: @""}];
}
- (void)startDictation {
    if (_gamepad.configuring) return;
    // Capture the choice before dismissing UIKit's keyboard; hidden editors
    // do not reliably report the language the user expects to speak.
    _dictationLocale = [self preferredDictationLocale];
    [self cancelTouches]; [self dismissKeyboard];
    [self updateDictationLanguage];
    [self postDictationAction:@"start"];
}
- (BOOL)voiceDraftActive { return _dictationState && ![_dictationState isEqualToString:@"idle"]; }
- (void)prepareVoiceDraftForEditing {
    if (!self.voiceDraftActive) return;
    [self postDictationAction:@"pause"];
    _keyboardRequested = YES;
}
- (void)confirmDictation {
    if (_gamepad.editing || !self.voiceDraftActive || ![_keyboardInput canModifyDraft] || !_keyboardInput.text.length) return;
    if ([_keyboardInput reviewedDraftText] != nil) [self postDictationAction:@"confirm"];
}
- (void)cancelDictation { [self postDictationAction:@"cancel"]; }
- (void)dictationStateChanged:(NSNotification *)note {
    BOOL wasActive = self.voiceDraftActive;
    _dictationState = note.userInfo[@"state"] ?: @"idle";
    BOOL active = self.voiceDraftActive;
    _dictationLanguageButton.hidden = !active;
    _dictationLanguageWidth.constant = active ? 140 : 0;
    _draftTextTop.constant = active ? 26 : 4;
    _composerHeight.constant = active ? 104 : 82;
    if (active && !wasActive) [_keyboardInput beginVoiceDraft];
    NSString *text = note.userInfo[@"text"];
    if (active && [text isKindOfClass:NSString.class]) {
        _keyboardInput.text = text;
        [_keyboardInput scrollRangeToVisible:NSMakeRange(text.length, 0)];
    }
    if (!active && wasActive) {
        _keyboardRequested = NO;
        [_keyboardInput cancelDraftSession];
        [self.superview becomeFirstResponder];
    }
    _dictationShield.hidden = !active;
    _dictateButton.hidden = active;
    _dictationSendButton.hidden = _dictationCancelButton.hidden = !active;
    [_insertDraftButton setTitle:AKHostLocalized(active ? @"touch.dictation.sendButton" : @"touch.draft.replace") forState:UIControlStateNormal];
    _insertDraftButton.accessibilityLabel = AKHostLocalized(active ? @"touch.dictation.send" : @"touch.draft.replace");
    _insertDraftButton.accessibilityHint = AKHostLocalized(active ? @"touch.dictation.send.hint" : @"touch.draft.replace.hint");
    _clearDraftButton.accessibilityLabel = AKHostLocalized(active ? @"touch.dictation.cancel" : @"touch.draft.clear");
    _keyboardInput.accessibilityLabel = AKHostLocalized(active ? @"touch.dictation.draft.label" : @"touch.draft.label");
    _keyboardInput.accessibilityHint = AKHostLocalized(active ? @"touch.dictation.draft" : @"touch.draft.hint");
    _draftLabel.text = active ? AKHostLocalized(@"touch.dictation.draft") : AKComposerDefaultLabel();
    NSString *problem = note.userInfo[@"problem"];
    _dictationStatus.text = problem.length ? problem : (active ? AKHostLocalized([@"touch.dictation." stringByAppendingString:_dictationState]) : @"");
    _dictationStatus.hidden = !active && !problem.length;
    NSUInteger generation = ++_statusGeneration;
    if (problem.length) {
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, problem);
        __weak AKTouchControls *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            AKTouchControls *controls = weakSelf;
            if (controls && controls->_statusGeneration == generation && !controls.voiceDraftActive) controls->_dictationStatus.hidden = YES;
        });
    }
    [self updateKeyboardButton];
    [self setNeedsLayout];
}
- (void)setTrackpadEnabled:(BOOL)enabled {
    [self cancelTouches];
    _trackpadEnabled = enabled;
    _trackpadButton.tintColor = enabled ? UIColor.systemCyanColor : UIColor.whiteColor;
    _trackpadButton.accessibilityLabel = enabled ? AKHostLocalized(@"touch.trackpad.disable") : AKHostLocalized(@"touch.trackpad.enable");
    _trackpadButton.accessibilityValue = enabled ? AKHostLocalized(@"touch.value.on") : AKHostLocalized(@"touch.value.off");
    [self.delegate touchTrackpadChanged:enabled];
}
- (void)toggleTrackpad {
    if (_gamepad.editing) return;
    self.trackpadEnabled = !self.trackpadEnabled;
    [NSUserDefaults.standardUserDefaults setBool:self.trackpadEnabled forKey:AKTouchTrackpadDefaultsKey];
}
- (BOOL)gamepadEnabled { return _gamepadEnabled; }
// Selection handles and system text UI need the same tracking-mode service as
// the controller settings while the guest owns the main thread.
- (BOOL)configuring { return _gamepad.configuring || self.keyboardVisible || _savedTextEditing || ![_dictationState isEqualToString:@"idle"]; }
- (void)showControlSettings {
    [self cancelDictation];
    if (_gamepad.editing) return;
    [self cancelTouches]; [self dismissKeyboard];
    // The gamepad owns the settings sheet, so we open it here rather than asking a
    // host that may have no such thing.
    [_gamepad toggleSettings];
    if ([self.delegate respondsToSelector:@selector(touchControlSettings)]) [self.delegate touchControlSettings];
}
// Leaving the game from a screen that has no quit of its own.
//
// The guest is a real Cocoa application in this process: asking its own NSApp to terminate
// runs its applicationShouldTerminate:/applicationWillTerminate: handlers first, which is how
// the game saves its settings, and only then does the translated AppKit end the process. That
// is the same path the game's own Exit item takes; nothing is killed and no memory is written.
//
// The confirmation says the rest plainly because there is no way around it: one guest per
// process, so WolkaraForever cannot put its launcher back afterwards - opening WolkaraForever again does.
- (void)leaveGame {
    [self cancelDictation];
    if (_gamepad.editing) return;
    [self cancelTouches]; [self dismissKeyboard];
    // One question, and no request to the guest.
    //
    // Asking the guest's own application object to terminate was tried first and is not kept.
    // The client answered `NSTerminateCancel`, so the tap did nothing at all - the exact dead
    // end this control exists to remove - and on the same run it faulted with EXC_BAD_ACCESS
    // shortly afterwards (ERROR #132, Dadpad, 2026-10-21): a half-asked shutdown that is then
    // cancelled is not a state to put a running client in for a UI convenience. WolkaraForever ends
    // its own process instead, and says plainly what that costs.
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:AKHostLocalized(@"touch.leave.title")
        message:AKHostLocalized(@"touch.leave.message")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:AKHostLocalized(@"touch.leave.keep") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:AKHostLocalized(@"touch.leave.close") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        (void)action;
        AKLog(@"leave game: the user chose to close WolkaraForever");
        [NSNotificationCenter.defaultCenter postNotificationName:AKTouchCloseAppNotification object:nil];
    }]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}
- (void)setGamepadVisible:(BOOL)visible {
    _gamepadButton.tintColor = visible ? (_gamepadSimple ? UIColor.systemGreenColor : UIColor.systemCyanColor) : UIColor.whiteColor;
    [_gamepadButton setImage:[UIImage systemImageNamed:_gamepadSimple ? @"l.joystick" : @"gamecontroller"] forState:UIControlStateNormal];
    NSString *mode = AKHostLocalized(_gamepadSimple ? @"touch.gamepad.value.simple" : @"touch.gamepad.value.full");
    NSString *state = AKHostLocalized(!_gamepadEnabled ? @"touch.gamepad.value.off" :
        visible ? @"touch.gamepad.value.active" : @"touch.gamepad.value.automatic");
    _gamepadButton.accessibilityValue = [NSString stringWithFormat:@"%@, %@",mode,state];
}
- (void)gamepadTouchDown { _gamepadHeld = NO; }
- (void)toggleGamepad {
    if (_gamepad.configuring || _gamepadHeld) return;
    _gamepadSimple = !_gamepadSimple;
    [NSUserDefaults.standardUserDefaults setBool:_gamepadSimple forKey:@"TKTouchGamepadSimple"];
    _gamepad.simple = _gamepadSimple;
    [self setGamepadVisible:_gamepad.visible];
}
- (void)holdGamepad:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan || _gamepadHeld || _gamepad.configuring) return;
    _gamepadHeld = YES;
    [self toggleGamepadEnabled];
}
- (BOOL)toggleGamepadEnabled {
    if (_gamepad.configuring) return NO;
    _gamepadEnabled = !_gamepadEnabled;
    [NSUserDefaults.standardUserDefaults setBool:_gamepadEnabled forKey:@"TKTouchGamepadEnabled"];
    _gamepad.enabled = _gamepadEnabled;
    [self setGamepadVisible:_gamepad.visible];
    if ([self.delegate respondsToSelector:@selector(touchGamepadPreferenceChanged:)])
        [self.delegate touchGamepadPreferenceChanged:_gamepadEnabled];
    return YES;
}
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)keyboardVisible { return _keyboardInput.isFirstResponder; }
- (BOOL)becomeFirstResponder {
    _composer.hidden = NO;
    _gamepad.keyboardVisible = YES;
    if ([self.delegate respondsToSelector:@selector(touchKeyboardVisibilityChanged:)])
        [self.delegate touchKeyboardVisibilityChanged:YES];
    _keyboardRequested = YES;
    BOOL accepted = [_keyboardInput becomeFirstResponder];
    [self updateKeyboardButton];
    return accepted;
}
- (BOOL)keyboardRequested { return _keyboardRequested; }
- (BOOL)resignFirstResponder {
    BOOL accepted = [_keyboardInput resignFirstResponder];
    [self updateKeyboardButton];
    return accepted;
}
- (void)updateKeyboardButton {
    _composer.hidden = !self.keyboardVisible && !self.voiceDraftActive;
    [self updateDraftButtons];
    [_keyboardButton setImage:[UIImage systemImageNamed:self.keyboardVisible ? @"keyboard.chevron.compact.down" : @"keyboard"] forState:UIControlStateNormal];
    _keyboardButton.accessibilityLabel = self.keyboardVisible ? AKHostLocalized(@"touch.keyboard.hide") : AKHostLocalized(@"touch.keyboard.show");
    _gamepad.keyboardVisible = self.keyboardVisible || self.voiceDraftActive;
    if ([self.delegate respondsToSelector:@selector(touchKeyboardVisibilityChanged:)])
        [self.delegate touchKeyboardVisibilityChanged:self.keyboardVisible];
}
- (void)toggleKeyboard {
    if (self.voiceDraftActive) {
        [self prepareVoiceDraftForEditing];
        [self becomeFirstResponder];
        return;
    }
    [self cancelDictation];
    if (_gamepad.editing) return;
    [self cancelTouches];
    if (self.keyboardVisible) [self dismissKeyboard];
    else [self becomeFirstResponder];
}
- (void)dismissKeyboard {
    if (self.voiceDraftActive) { [self cancelDictation]; return; }
    BOOL requested = _keyboardRequested;
    _keyboardRequested = NO;
    [_keyboardInput cancelDraftSession];
    if (requested) [self.superview becomeFirstResponder];
    [self updateKeyboardButton];
}
// The guest owns its text/selection. Explicit Replace replaces the field.
// Accessory keys still allow editing existing text directly in the guest.
// Touches pass through the toolbar except on its own chrome.
//
// The platform's version named the two buttons it had; this names every control the layer
// puts on the same strip, which is the same rule with the layer's controls in it. It was
// lost when the layer rewrote this file, and without it the toolbar claims every point in
// its frame - so a tap in the gap between two buttons goes to the toolbar instead of to the
// game. The platform's own test is what caught it.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    if (self.voiceDraftActive) return CGRectContainsPoint(self.bounds, point);
    if ([_gamepad configurationContainsPoint:point inView:self]) return NO;
    for (UIView *control in [self toolbarItems]) {
        if (!control.hidden && CGRectContainsPoint(control.frame, point)) return YES;
    }
    return NO;
}

- (BOOL)hasText { return YES; }
// The text-input traits, carried over from the platform's version of this class. It is what
// makes iPadOS treat these controls as a text input and offer the layer's own accessory row
// for them, and the platform's test asserts the two that decide that. They were lost when
// the layer rewrote this file; restored verbatim, because none of the layer's changes need
// them to differ.
- (UITextAutocapitalizationType)autocapitalizationType { return UITextAutocapitalizationTypeNone; }
- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (UITextSpellCheckingType)spellCheckingType { return UITextSpellCheckingTypeNo; }
- (UITextSmartQuotesType)smartQuotesType { return UITextSmartQuotesTypeNo; }
- (UITextSmartDashesType)smartDashesType { return UITextSmartDashesTypeNo; }
- (UITextSmartInsertDeleteType)smartInsertDeleteType { return UITextSmartInsertDeleteTypeNo; }
- (UIKeyboardType)keyboardType { return UIKeyboardTypeDefault; }
- (UIReturnKeyType)returnKeyType { return UIReturnKeyDefault; }
// Secure, so the system never offers to remember or spell-check what is typed at the game.
- (BOOL)isSecureTextEntry { return YES; }
- (void)insertText:(NSString *)text { [self.delegate touchInsertText:text]; }
// Dictation types into whatever the controls announced as the game's text input, and it
// asks for these two selectors when it does. They are the adapter's own converter - the
// delegate turns text into key events and posts them to the guest - so this view says the
// same thing to the same place, once, and does nothing else with the words.
- (void)touchInsertText:(NSString *)text {
    if ([self.delegate respondsToSelector:@selector(touchInsertText:)]) [self.delegate touchInsertText:text];
}
- (void)touchSubmitPrivateText:(NSString *)text {
    // Never fall back to ordinary text events: those can enter input diagnostics.
    if ([self.delegate respondsToSelector:@selector(touchSubmitPrivateText:)]) [self.delegate touchSubmitPrivateText:text];
}
- (void)touchSpecialKey:(unsigned short)code characters:(NSString *)characters {
    if ([self.delegate respondsToSelector:@selector(touchSpecialKey:characters:)])
        [self.delegate touchSpecialKey:code characters:characters];
}
- (void)replaceGameText:(NSString *)text {
    // A host with no draft panel leaves this out; the button then does nothing
    // rather than crashing.
    if ([self.delegate respondsToSelector:@selector(touchReplaceText:)]) [self.delegate touchReplaceText:text];
}
- (void)deleteBackward { [self.delegate touchSpecialKey:51 characters:@"\x7f"]; }

- (UIView *)inputAccessoryView {
    if (!_accessory) {
        UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
        row.distribution = UIStackViewDistributionFillEqually;
        row.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
        NSArray<NSString *> *titles = @[@"Esc", @"Tab", @"←", @"→", @"⌫", @"↵", @"⌄"];
        for (NSUInteger i = 0; i < titles.count; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = (NSInteger)i;
            button.tintColor = UIColor.whiteColor;
            [button setTitle:titles[i] forState:UIControlStateNormal];
            button.accessibilityIdentifier = [NSString stringWithFormat:@"wolkaraforever.keyboard.key.%lu", (unsigned long)i];
            button.accessibilityLabel = @[AKHostLocalized(@"touch.key.escape"), AKHostLocalized(@"touch.key.tab"),
                AKHostLocalized(@"touch.key.leftArrow"), AKHostLocalized(@"touch.key.rightArrow"),
                AKHostLocalized(@"touch.key.gameBackspace"), AKHostLocalized(@"touch.key.return"),
                AKHostLocalized(@"touch.keyboard.hide")][i];
            [button addTarget:self action:@selector(accessoryKey:) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:button];
        }
        _accessory = row;
        [self updateDraftButtons];
    }
    return _accessory;
}
- (void)accessoryKey:(UIButton *)button {
    if (self.voiceDraftActive && button.tag != 5 && button.tag != 6) {
        if (button.tag == 0) [self cancelDictation];
        return;
    }
    if (button.tag == 6) { [self dismissKeyboard]; return; }
    if (button.tag == 5) { [_keyboardInput commitDraftSendingReturn:YES]; return; }
    // Navigation never sends an unfinished draft or switches the guest field
    // during composition. Return uses the same commit path as the system Send key.
    if (_keyboardInput.text.length || ![_keyboardInput canModifyDraft]) return;
    const unsigned short codes[] = {53, 48, 123, 124, 51, 36};
    NSArray<NSString *> *characters = @[@"\x1b", @"\t", @"\uF702", @"\uF703", @"\x7f", @"\r"];
    if (button.tag >= 0 && button.tag < 6) [self.delegate touchSpecialKey:codes[button.tag] characters:characters[button.tag]];
}
- (void)insertDraft { if (self.voiceDraftActive) [self confirmDictation]; else [_keyboardInput forwardCommittedText]; }
- (void)clearDraft {
    if (self.voiceDraftActive) { [self cancelDictation]; return; }
    if ([_keyboardInput canModifyDraft]) [_keyboardInput discardDraft];
}
- (void)updateDraftButtons {
    BOOL ready = [_keyboardInput canModifyDraft];
    BOOL voice = self.voiceDraftActive;
    BOOL canSend = ready && _keyboardInput.text.length > 0;
    _dictationSendButton.enabled = voice && canSend;
    _insertDraftButton.enabled = voice ? canSend : [_keyboardInput canReplaceField];
    _clearDraftButton.enabled = voice || (ready && _keyboardInput.hasText);
    for (UIButton *button in ((UIStackView *)_accessory).arrangedSubviews) {
        button.enabled = voice ? (button.tag == 6 || button.tag == 0 || (button.tag == 5 && canSend)) :
            (button.tag == 6 || (button.tag == 5 ? [_keyboardInput canReplaceField] : (ready && !_keyboardInput.hasText)));
    }
}
- (void)buildComposer {
    _composer = [[UIView alloc] initWithFrame:CGRectZero];
    _composer.hidden = YES;
    _composer.translatesAutoresizingMaskIntoConstraints = NO;
    _composer.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.98];
    _composer.layer.cornerRadius = 12;
    _composer.layer.zPosition = self.layer.zPosition;
    UILabel *label = _draftLabel = [UILabel new];
    label.text = AKComposerDefaultLabel();
    label.font = [UIFont systemFontOfSize:12];
    label.textColor = UIColor.lightGrayColor;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.75;
    _dictationLanguageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _dictationLanguageButton.hidden = YES;
    _dictationLanguageButton.showsMenuAsPrimaryAction = YES;
    _dictationLanguageButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _dictationLanguageButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _dictationLanguageButton.accessibilityIdentifier = @"wolkara.dictation.language";
    _dictationLanguageButton.accessibilityLabel = AKHostLocalized(@"touch.dictation.language");
    _dictationLanguageButton.accessibilityHint = AKHostLocalized(@"touch.dictation.language.note");
    UIButton *insert = _insertDraftButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [insert setTitle:AKHostLocalized(@"touch.draft.replace") forState:UIControlStateNormal];
    insert.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    insert.accessibilityIdentifier = @"wolkaraforever.keyboard.insert";
    insert.accessibilityHint = AKHostLocalized(@"touch.draft.replace.hint");
    [insert addTarget:self action:@selector(insertDraft) forControlEvents:UIControlEventTouchUpInside];
    UIButton *clear = _clearDraftButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setImage:[UIImage systemImageNamed:@"xmark.circle"] forState:UIControlStateNormal];
    clear.accessibilityLabel = AKHostLocalized(@"touch.draft.clear");
    clear.accessibilityIdentifier = @"wolkaraforever.keyboard.clear";
    [clear addTarget:self action:@selector(clearDraft) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *view in @[label, _dictationLanguageButton, _keyboardInput, insert, clear]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [_composer addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:_composer.leadingAnchor constant:12],
        [label.topAnchor constraintEqualToAnchor:_composer.topAnchor constant:6],
        [label.trailingAnchor constraintEqualToAnchor:_dictationLanguageButton.leadingAnchor constant:-4],
        [label.heightAnchor constraintEqualToConstant:16],
        [_dictationLanguageButton.trailingAnchor constraintEqualToAnchor:_composer.trailingAnchor constant:-8],
        [_dictationLanguageButton.topAnchor constraintEqualToAnchor:_composer.topAnchor],
        [_dictationLanguageButton.heightAnchor constraintEqualToConstant:44],
        (_dictationLanguageWidth = [_dictationLanguageButton.widthAnchor constraintEqualToConstant:0]),
        [_keyboardInput.leadingAnchor constraintEqualToAnchor:_composer.leadingAnchor constant:8],
        (_draftTextTop = [_keyboardInput.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:4]),
        [_keyboardInput.bottomAnchor constraintEqualToAnchor:_composer.bottomAnchor constant:-8],
        [_keyboardInput.trailingAnchor constraintEqualToAnchor:clear.leadingAnchor],
        [clear.widthAnchor constraintEqualToConstant:44],
        [clear.heightAnchor constraintEqualToConstant:44],
        [clear.centerYAnchor constraintEqualToAnchor:_keyboardInput.centerYAnchor],
        [clear.trailingAnchor constraintEqualToAnchor:insert.leadingAnchor],
        [insert.widthAnchor constraintEqualToConstant:84],
        [insert.heightAnchor constraintEqualToConstant:44],
        [insert.centerYAnchor constraintEqualToAnchor:_keyboardInput.centerYAnchor],
        [insert.trailingAnchor constraintEqualToAnchor:_composer.trailingAnchor constant:-8],
    ]];
}
- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    [_composer removeFromSuperview];
    UIView *host = self.superview;
    if (!host) return;
    [host addSubview:_composer];
    // The editor follows the keyboard; the toolbar stays fixed at the top.
    // No resizing of the game's rendering surface or reading of game memory.
    NSLayoutConstraint *width = [_composer.widthAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.widthAnchor constant:-24];
    width.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [_composer.bottomAnchor constraintEqualToAnchor:host.keyboardLayoutGuide.topAnchor constant:-4],
        [_composer.centerXAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.centerXAnchor],
        width, [_composer.widthAnchor constraintLessThanOrEqualToConstant:800],
        (_composerHeight = [_composer.heightAnchor constraintEqualToConstant:82]),
    ]];

    // Placement happens in layoutSubviews, by frame, from the host's own bounds - see
    // placeToolbarInHost. Constraints are the host's to set, and Apple says a view must
    // not set translatesAutoresizingMaskIntoConstraints on itself; frame placement from
    // the host's bounds is the one thing neither can argue with.
    if (!_gamepad) {
        _gamepad = [[AKTouchGamepad alloc] initWithHostView:host];
        __weak AKTouchControls *weakSelf = self;
        _gamepad.visibilityChanged = ^(BOOL visible) {
            AKTouchControls *controls = weakSelf;
            if (!controls) return;
            [controls cancelTouches];
            [controls setGamepadVisible:visible];
            if (controls->_gamepad.editing) {
                if (controls.keyboardVisible || controls->_keyboardRequested) [controls dismissKeyboard];
                [controls cancelDictation];
            }
            else [controls->_toolbarDragOrigins removeAllObjects];
            [controls controlAppearanceChanged:nil];
        };
        _gamepad.simple = _gamepadSimple;
        _gamepad.enabled = _gamepadEnabled;
    }
    _gamepad.keyboardVisible = self.keyboardVisible || self.voiceDraftActive;
    [host bringSubviewToFront:self];
    [host bringSubviewToFront:_composer];
    [_gamepad refresh];
}

- (void)processTouches:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.trackpadEnabled) return;
    for (UITouch *touch in touches) if (touch.phase == UITouchPhaseCancelled) [self cancelTouches];
    unsigned count = 0;
    CGPoint center = CGPointZero;
    for (UITouch *touch in event.allTouches) {
        if (touch.type != UITouchTypeDirect || touch.view != self.superview ||
            touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) continue;
        CGPoint point = [touch locationInView:self.superview];
        center.x += point.x; center.y += point.y; count++;
    }
    if (count) { center.x /= count; center.y /= count; }
    AKTrackpadUpdate(&_pad, count, center.x, center.y, event.timestamp, AKEmitTouch, (__bridge void *)self);
    [_holdTimer invalidate]; _holdTimer = nil;
    if (_pad.fingers && !_pad.blocked && !_pad.lifting && !_pad.dragging && _pad.travelled <= 8) {
        __weak AKTouchControls *weakSelf = self;
        _holdTimer = [NSTimer timerWithTimeInterval:MAX(0.01, _pad.started + 0.46 - NSProcessInfo.processInfo.systemUptime)
                                          repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            AKTouchControls *controls = weakSelf;
            if (controls) AKTrackpadHold(&controls->_pad, NSProcessInfo.processInfo.systemUptime, AKEmitTouch, (__bridge void *)controls);
        }];
        [NSRunLoop.mainRunLoop addTimer:_holdTimer forMode:NSRunLoopCommonModes];
    }
}
- (void)cancelTouches {
    if ([self.delegate respondsToSelector:@selector(touchInputCancelled)]) [self.delegate touchInputCancelled];
    [_holdTimer invalidate]; _holdTimer = nil;
    AKTrackpadCancel(&_pad, AKEmitTouch, (__bridge void *)self);
    if (!_pad.fingers) _pad = (AKTrackpad){0};
}
- (void)suspendInput:(NSNotification *)notification {
    (void)notification;
    [self cancelTouches];
    _pad = (AKTrackpad){0};
    // Dictation and system permission panels temporarily take focus. Closing
    // the first responder here cancels dictation before its UI can appear.
    AKLog(@"input suspended (draftFirstResponder=%d)", _keyboardInput.isFirstResponder);
}
- (void)systemKeyboardShown:(NSNotification *)notification {
    NSValue *frame = notification.userInfo[UIKeyboardFrameEndUserInfoKey];
    AKLog(@"system keyboard shown draftFirstResponder=%d markedText=%d height=%.0f", _keyboardInput.isFirstResponder, _keyboardInput.markedTextRange != nil, [frame CGRectValue].size.height);
}
- (void)systemKeyboardHidden:(NSNotification *)notification {
    (void)notification;
    AKLog(@"system keyboard hidden draftFirstResponder=%d", _keyboardInput.isFirstResponder);
}
// A game macro or key combination asked for the draft keyboard: open it so the
// iOS keyboard (and its microphone) is one tap away. Never closes an open one.
- (void)keyboardRequestedByGuest:(NSNotification *)notification {
    if (_gamepad.editing) return;
    [self cancelDictation];
    (void)notification;
    [self cancelTouches];
    AKLog(@"draft keyboard requested from the guest");
    if (!self.keyboardVisible) [self becomeFirstResponder];
}
- (void)backgroundInput:(NSNotification *)notification {
    [self postDictationAction:@"dismiss"];
    [self suspendInput:notification];
    [self dismissKeyboard];
}
- (void)windowResigned:(NSNotification *)notification {
    if (notification.object == self.window) [self suspendInput:notification];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self backgroundInput:nil];
}
- (void)dealloc {
    [_composer removeFromSuperview];
    [_holdTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
@end
