#import "ToolbarDictationController.h"

// The adapter owns the visible UIKit draft. Speech callbacks may update that
// document, but only an explicit confirmation carrying the displayed text may
// type into the game. No callback is allowed to submit a final transcript.
@protocol AKToolbarTextTarget <NSObject>
- (void)touchInsertText:(NSString *)text;
- (void)touchSpecialKey:(unsigned short)code characters:(NSString *)characters;
@end

@implementation AKToolbarDictationController {
    AKDictation *_dictation;
    __weak UIView *_target;
    BOOL _ownsDraft, _capturing, _openedChat;
    NSUInteger _generation;
}
- (instancetype)initWithDictation:(AKDictation *)dictation {
    if ((self = [super init])) {
        _dictation = dictation;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(action:)
            name:@"AKTouchDictationAction" object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stateChanged:)
            name:AKDictationStateDidChangeNotification object:dictation];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:)
            name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}
- (void)publishForTarget:(UIView *)target state:(NSString *)state text:(NSString *)text problem:(NSString *)problem {
    if (!target) return;
    NSMutableDictionary *info = [@{@"state":state, @"problem":problem ?: @""} mutableCopy];
    if (text) info[@"text"] = text;
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchDictationState" object:target userInfo:info];
}
- (void)stateChanged:(NSNotification *)note {
    (void)note;
    if (!_ownsDraft || !_capturing || _dictation.state == AKDictationStateIdle) return;
    NSArray *states = @[@"idle", @"authorizing", @"listening", @"finalizing"];
    [self publishForTarget:_target state:states[_dictation.state] text:nil problem:nil];
}
- (BOOL)canReach:(UIView *)target {
    return target && target.window && target == AKDictation.gameTextTarget &&
        [target respondsToSelector:@selector(touchInsertText:)] &&
        [target respondsToSelector:@selector(touchSpecialKey:characters:)];
}
- (void)endDraftClosingChat:(BOOL)closeChat {
    UIView *target = _target;
    BOOL opened = _openedChat, capturing = _capturing;
    _ownsDraft = _capturing = _openedChat = NO;
    _target = nil; ++_generation;
    if (capturing) [_dictation cancel];
    [self publishForTarget:target state:@"idle" text:@"" problem:nil];
    if (closeChat && opened && [self canReach:target]) {
        [(id<AKToolbarTextTarget>)target touchSpecialKey:53 characters:@"\x1b"];
    }
}
- (void)background:(NSNotification *)note {
    (void)note;
    // Losing the foreground drops the draft without sending keys to a game
    // that is no longer visible. The explicit cross button sends one Esc.
    if (_ownsDraft) [self endDraftClosingChat:NO];
}
- (void)action:(NSNotification *)note {
    UIView *target = [note.object isKindOfClass:UIView.class] ? note.object : nil;
    if (!target) return;
    NSString *action = note.userInfo[@"action"];
    BOOL changingLanguage = [action isEqualToString:@"language"];
    if ([action isEqualToString:@"start"] || changingLanguage) {
        if (changingLanguage) {
            if (!_ownsDraft || target != _target) return;
            // Invalidate callbacks before cancelling. Restart only recognition;
            // the chat is already open and must not receive another Return/Esc.
            BOOL capturing = _capturing; _capturing = NO; ++_generation;
            if (capturing) [_dictation cancel];
        } else if (_ownsDraft) return;
        if (![self canReach:target]) {
            if (changingLanguage) [self endDraftClosingChat:NO];
            [self publishForTarget:target state:@"idle" text:nil problem:@"No game text input is available."];
            return;
        }
        if (_dictation.state != AKDictationStateIdle || _dictation.transcriptHandler) {
            if (changingLanguage) [self endDraftClosingChat:NO];
            [self publishForTarget:target state:@"idle" text:nil problem:@"Another dictation session is already active."];
            return;
        }
        _target = target;
        _ownsDraft = _capturing = _openedChat = YES;
        NSUInteger generation = ++_generation;
        // Enter is the user's requested chat shortcut, not proof of guest focus.
        if (!changingLanguage) [(id<AKToolbarTextTarget>)target touchSpecialKey:36 characters:@"\r"];
        [self publishForTarget:target state:@"authorizing" text:@"" problem:nil];
        __weak AKToolbarDictationController *weakSelf = self;
        NSString *locale = [note.userInfo[@"locale"] isKindOfClass:NSString.class] ? note.userInfo[@"locale"] : nil;
        BOOL accepted = [_dictation beginWithLocale:locale progress:^(NSString *text) {
            AKToolbarDictationController *self = weakSelf;
            if (!self || !self->_capturing || self->_generation != generation) return;
            [self publishForTarget:self->_target state:@"listening" text:text problem:nil];
        } completion:^(NSString *text, NSString *problem) {
            AKToolbarDictationController *self = weakSelf;
            if (!self || !self->_ownsDraft || self->_generation != generation) return;
            self->_capturing = NO;
            [self publishForTarget:self->_target state:@"review" text:text problem:problem];
        }];
        if (!accepted) {
            _capturing = NO;
            [self publishForTarget:target state:@"review" text:nil problem:@"Dictation could not start."];
        }
        return;
    }
    if (!_ownsDraft || target != _target) return;
    if ([action isEqualToString:@"confirm"]) {
        // Commit exactly the document the user has seen/edited. Stop speech
        // first and invalidate its callbacks so a late correction cannot sneak
        // extra words into the message or replace a newer draft.
        id value = note.userInfo[@"text"];
        NSString *text = [value isKindOfClass:NSString.class] ? value : @"";
        text = [[text componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet] componentsJoinedByString:@" "];
        text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length || ![self canReach:target]) return;
        [self endDraftClosingChat:NO];
        [(id<AKToolbarTextTarget>)target touchInsertText:text];
        [(id<AKToolbarTextTarget>)target touchSpecialKey:36 characters:@"\r"];
        // The tested Forever client leaves an empty chat editor after sending.
        // Close it once. A second Esc would open the game menu.
        [(id<AKToolbarTextTarget>)target touchSpecialKey:53 characters:@"\x1b"];
    } else if ([action isEqualToString:@"pause"]) {
        // Tapping the draft to edit freezes recognition before UIKit opens its
        // keyboard; subsequent speech must not overwrite the user's corrections.
        BOOL capturing = _capturing; _capturing = NO; ++_generation;
        if (capturing) [_dictation cancel];
        [self publishForTarget:target state:@"review" text:nil problem:nil];
    } else if ([action isEqualToString:@"cancel"] || [action isEqualToString:@"dismiss"]) {
        [self endDraftClosingChat:[action isEqualToString:@"cancel"]];
    }
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_capturing) [_dictation cancel];
}
@end
