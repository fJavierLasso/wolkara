#import "SavedTextController.h"
#import "../../translation/AppKit/HostGameSession.h"
#import "WKLocalization.h"

@protocol WKSavedTextTarget <NSObject>
- (void)touchSubmitPrivateText:(NSString *)text;
@end

@implementation WKSavedTextController {
    id<WKSavedTextStorage> _store;
    UIAlertController *_editor;
    __weak UIView *_editorTarget;
}
- (instancetype)init { return [self initWithStore:[WKSavedTextStore new]]; }
- (instancetype)initWithStore:(id<WKSavedTextStorage>)store {
    if ((self = [super init])) {
        _store = store;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(action:)
            name:@"AKTouchSavedTextAction" object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:)
            name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}
- (BOOL)canReach:(UIView *)target {
    return !AKGameSessionUsesBattleNet() && target && target == self.gameTextTarget && target.window &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
        [target respondsToSelector:@selector(touchSubmitPrivateText:)];
}
- (BOOL)validText:(NSString *)text {
    NSMutableCharacterSet *forbidden = [NSCharacterSet.controlCharacterSet mutableCopy];
    [forbidden formUnionWithCharacterSet:NSCharacterSet.newlineCharacterSet];
    return [text rangeOfCharacterFromSet:forbidden].location == NSNotFound;
}
- (void)showProblem:(NSString *)message presenter:(UIViewController *)presenter {
    if (!presenter.view.window || presenter.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:WKLocalized(@"touch.savedText.title")
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WKLocalized(@"touch.savedText.ok") style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
- (void)clearEditor {
    _editor.textFields.firstObject.text = @"";
    _editor = nil;
    if (_editorTarget) [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchSavedTextEditorState"
        object:_editorTarget userInfo:@{@"active":@NO}];
    _editorTarget = nil;
}
- (void)saveEditor {
    UIAlertController *editor = _editor;
    if (!editor) return;
    NSString *text = editor.textFields.firstObject.text ?: @"";
    UIViewController *presenter = editor.presentingViewController;
    NSError *error = nil;
    NSString *problem = ![self validText:text] ? WKLocalized(@"touch.savedText.singleLine") : nil;
    if (!problem && ![_store saveText:text error:&error]) problem = WKLocalized(@"touch.savedText.saveError");
    [self clearEditor];
    [presenter dismissViewControllerAnimated:YES completion:^{
        if (problem) [self showProblem:problem presenter:presenter];
    }];
}
- (void)showEditorForTarget:(UIView *)target text:(NSString *)text {
    UIViewController *presenter = target.window.rootViewController;
    if (_editor || presenter.presentedViewController) return;
    UIAlertController *editor = [UIAlertController alertControllerWithTitle:WKLocalized(@"touch.savedText.title")
        message:WKLocalized(@"touch.savedText.instructions") preferredStyle:UIAlertControllerStyleAlert];
    [editor addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.secureTextEntry = YES;
        field.textContentType = UITextContentTypePassword;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.spellCheckingType = UITextSpellCheckingTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.smartQuotesType = UITextSmartQuotesTypeNo;
        field.smartDashesType = UITextSmartDashesTypeNo;
        field.placeholder = WKLocalized(@"touch.savedText.field");
        field.accessibilityIdentifier = @"wolkaraforever.savedText.field";
        field.text = text;
    }];
    __weak WKSavedTextController *weakSelf = self;
    [editor addAction:[UIAlertAction actionWithTitle:WKLocalized(@"touch.savedText.cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        (void)action; [weakSelf clearEditor];
    }]];
    [editor addAction:[UIAlertAction actionWithTitle:WKLocalized(@"touch.savedText.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action; [weakSelf saveEditor];
    }]];
    _editor = editor;
    _editorTarget = target;
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchSavedTextEditorState"
        object:target userInfo:@{@"active":@YES}];
    [presenter presentViewController:editor animated:YES completion:nil];
}
- (void)action:(NSNotification *)note {
    UIView *target = [note.object isKindOfClass:UIView.class] ? note.object : nil;
    if (![self canReach:target] || _editor) return;
    NSString *action = note.userInfo[@"action"];
    if (![action isEqualToString:@"edit"] && ![action isEqualToString:@"type"]) return;
    UIViewController *presenter = target.window.rootViewController;
    if (presenter.presentedViewController) return;
    NSError *error = nil;
    NSString *text = [_store readText:&error];
    if (!text || error) {
        [self showProblem:WKLocalized(@"touch.savedText.readError") presenter:presenter];
        return;
    }
    if ([action isEqualToString:@"edit"] || !text.length) {
        [self showEditorForTarget:target text:text];
        return;
    }
    if (![self validText:text]) {
        [self showProblem:WKLocalized(@"touch.savedText.singleLine") presenter:presenter];
        return;
    }
    // Explicit hold only. No clipboard, opening Return, trailing Escape, text
    // logging or game-field inspection. The selected field belongs to the user.
    [(id<WKSavedTextTarget>)target touchSubmitPrivateText:text];
}
- (void)background:(NSNotification *)note {
    (void)note;
    UIAlertController *editor = _editor;
    [self clearEditor];
    [editor dismissViewControllerAnimated:NO completion:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
