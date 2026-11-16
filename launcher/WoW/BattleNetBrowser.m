#import "BattleNetBrowser.h"
#import "BattleNetLogin.h"
#import <WebKit/WebKit.h>

@interface TKWoWBattleNetBrowser () <WKNavigationDelegate, WKUIDelegate>
@end
@implementation TKWoWBattleNetBrowser {
    WKWebView *_web;
    NSURL *_loginURL;
    void (^_completion)(NSString *,NSString *);
    NSTimer *_timeout;
    BOOL _finished, _visitedLogin;
    WKNavigation *_mainNavigation;
    BOOL _nextNavigationTrusted, _mainNavigationTrusted, _rejectedCallback;
    UILabel *_host;
    UIStackView *_stack;
    UITextField *_returnField;
    UIScrollView *_returnScroll;
    BOOL _externalLoginActive;
}
- (instancetype)initWithRegion:(NSString *)region completion:(void (^)(NSString *,NSString *))completion {
    if (!(self=[super initWithNibName:nil bundle:nil])) return nil;
    _loginURL=TKWoWLoginURL(region); _completion=[completion copy];
    self.title=@"Battle.net login"; self.modalInPresentation=YES;
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Apple / Google…"
        style:UIBarButtonItemStylePlain target:self action:@selector(showExternalLogin)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier=@"wow.login.external";
    _host=[UILabel new]; _host.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _host.textAlignment=NSTextAlignmentCenter; _host.numberOfLines=0;
    _host.text=@"Sign in on Blizzard's website. Complete any CAPTCHA or verification there.";
    WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];
    configuration.websiteDataStore=WKWebsiteDataStore.nonPersistentDataStore;
    _web=[[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    _web.navigationDelegate=self; _web.UIDelegate=self;
    _web.opaque=NO; _web.backgroundColor=[UIColor colorWithRed:0.05 green:0.06 blue:0.08 alpha:1];
    _web.scrollView.backgroundColor=_web.backgroundColor;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[_host,_web]];
    stack.axis=UILayoutConstraintAxisVertical; stack.spacing=8; stack.translatesAutoresizingMaskIntoConstraints=NO;
    _stack=stack;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor]]];
    __weak typeof(self) weakSelf=self;
    _timeout=[NSTimer scheduledTimerWithTimeInterval:600 repeats:NO block:^(NSTimer *timer) {
        (void)timer; [weakSelf finish:nil failure:@"Browser login timed out. Please try again."];
    }];
    if (_loginURL) [_web loadRequest:[NSURLRequest requestWithURL:_loginURL]];
    else [self finish:nil failure:@"Browser login is unavailable for this region."];
}
- (void)cancel { [self finish:nil failure:nil]; }
- (void)showExternalLogin {
    if (_finished || _externalLoginActive) return;
    _externalLoginActive=YES;
    _web.navigationDelegate=nil; _web.UIDelegate=nil; [_web stopLoading];
    [_stack removeArrangedSubview:_web]; [_web removeFromSuperview]; _web=nil;
    self.navigationItem.rightBarButtonItem=nil;
    _host.text=@"Sign in with Apple, Google or another linked account in your browser. After signing in, the final localhost page cannot open. Copy its full address, return here and paste it below. Keep that address private: it grants access to your account.";
    _stack.layoutMargins=UIEdgeInsetsMake(16,20,16,20); _stack.layoutMarginsRelativeArrangement=YES;
    UIButton *open=[UIButton buttonWithType:UIButtonTypeSystem];
    [open setTitle:@"Open browser to sign in" forState:UIControlStateNormal];
    open.accessibilityIdentifier=@"wow.login.openBrowser";
    [open addTarget:self action:@selector(openExternalBrowser) forControlEvents:UIControlEventTouchUpInside];
    _returnField=[UITextField new]; _returnField.secureTextEntry=YES;
    _returnField.borderStyle=UITextBorderStyleRoundedRect;
    _returnField.placeholder=@"Paste the final browser address";
    _returnField.accessibilityIdentifier=@"wow.login.browserReturn";
    _returnField.accessibilityLabel=@"Private address from the browser";
    _returnField.autocorrectionType=UITextAutocorrectionTypeNo;
    _returnField.spellCheckingType=UITextSpellCheckingTypeNo;
    _returnField.autocapitalizationType=UITextAutocapitalizationTypeNone;
    _returnField.smartQuotesType=UITextSmartQuotesTypeNo;
    _returnField.smartDashesType=UITextSmartDashesTypeNo;
    _returnField.keyboardType=UIKeyboardTypeURL;
    UIButton *use=[UIButton buttonWithType:UIButtonTypeSystem];
    [use setTitle:@"Continue" forState:UIControlStateNormal];
    use.accessibilityIdentifier=@"wow.login.useBrowserReturn";
    [use addTarget:self action:@selector(useBrowserReturn) forControlEvents:UIControlEventTouchUpInside];
    [_stack addArrangedSubview:open]; [_stack addArrangedSubview:_returnField];
    [_stack addArrangedSubview:use];
    // Keep the private return field reachable on narrow landscape phones and
    // when the keyboard appears. Removing the old stack releases its web constraints.
    [_stack removeFromSuperview];
    _returnScroll=[UIScrollView new]; _returnScroll.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:_returnScroll]; [_returnScroll addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_returnScroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_returnScroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [_returnScroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [_returnScroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:_returnScroll.contentLayoutGuide.topAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:_returnScroll.contentLayoutGuide.bottomAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:_returnScroll.contentLayoutGuide.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:_returnScroll.contentLayoutGuide.trailingAnchor],
        [_stack.widthAnchor constraintEqualToAnchor:_returnScroll.frameLayoutGuide.widthAnchor],
        [_returnField.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [open.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [use.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_externalLoginActive && _returnField.isFirstResponder)
        [_returnScroll scrollRectToVisible:[_returnField convertRect:_returnField.bounds toView:_returnScroll] animated:NO];
}
- (void)openExternalBrowser {
    if (_finished || !_externalLoginActive || !_loginURL) return;
    [_returnField resignFirstResponder];
    __weak typeof(self) weakSelf=self;
    [UIApplication.sharedApplication openURL:_loginURL options:@{} completionHandler:^(BOOL success) {
        TKWoWBattleNetBrowser *host=weakSelf;
        if (host && !success && !host->_finished) host->_host.text=@"The browser could not open. Try again or cancel to use Battle.net email login.";
    }];
}
- (void)useBrowserReturn {
    if (_finished || !_externalLoginActive) return;
    // Explicit user paste only. Never read the pasteboard, Safari storage or
    // provider forms. The game service, not this parser, authenticates the ticket.
    NSString *text=[_returnField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *ticket=text.length<=8192?TKWoWLoginTicketFromURL([NSURL URLWithString:text]):nil;
    _returnField.text=@"";
    if (!ticket) { _host.text=@"Paste the complete final address from your browser. It must start with http://localhost:0/?ST=."; return; }
    [_returnField resignFirstResponder];
    [self finish:ticket failure:nil];
}
- (void)finish:(NSString *)ticket failure:(NSString *)failure {
    if (_finished) return; _finished=YES;
    [_timeout invalidate]; _timeout=nil;
    _web.navigationDelegate=nil; _web.UIDelegate=nil; [_web stopLoading];
    [_web removeFromSuperview]; _web=nil;
    _returnField.text=@"";
    void (^completion)(NSString *,NSString *)=_completion; _completion=nil;
    // The caller encrypts immediately, before dismissal can retain the ticket.
    if (completion) completion(ticket,failure);
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed || self.isBeingDismissed) [self cancel];
}
- (void)dealloc { [_timeout invalidate]; }
- (BOOL)finishCallbackURL:(NSURL *)url {
    if (!TKWoWLoginCallbackURL(url)) return NO;
    NSString *ticket=_visitedLogin?TKWoWLoginTicketFromURL(url):nil;
    [self finish:ticket failure:ticket?nil:@"Battle.net returned an invalid login response."];
    return YES;
}
- (BOOL)isCurrentLoginNavigation:(WKNavigation *)navigation webView:(WKWebView *)webView {
    // These delegate callbacks describe the main-frame navigation. Bind the
    // fallback to our browser's approved HTTPS load, not a subframe, rejected
    // policy action or a late failure from a superseded navigation.
    return !_finished && webView==_web && _visitedLogin && _mainNavigationTrusted && !_rejectedCallback &&
        (!navigation || navigation==_mainNavigation);
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    (void)webView; NSURL *url=action.request.URL;
    if (_finished || _externalLoginActive) { decisionHandler(WKNavigationActionPolicyCancel); return; }
    if (TKWoWLoginCallbackURL(url)) {
        // Only the top-level login navigation can finish an attempt. A CAPTCHA
        // iframe or popup must never inject a different account's ticket.
        BOOL top=action.targetFrame.isMainFrame && action.sourceFrame.isMainFrame;
        if (!top) _rejectedCallback=YES;
        decisionHandler(WKNavigationActionPolicyCancel);
        if (top) [self finishCallbackURL:url];
        return;
    }
    if (action.targetFrame.isMainFrame || !action.targetFrame) {
        if (!TKWoWLoginPageIsTrusted(url)) {
            _nextNavigationTrusted=NO;
            decisionHandler(WKNavigationActionPolicyCancel);
            [self showExternalLogin];
            return;
        }
        if (action.targetFrame.isMainFrame) _nextNavigationTrusted=YES;
    } else if (![@[@"https",@"about",@"data",@"blob"] containsObject:url.scheme.lowercaseString]) {
        decisionHandler(WKNavigationActionPolicyCancel); return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    if (_finished || webView!=_web) return;
    _mainNavigation=navigation;
    _mainNavigationTrusted=_nextNavigationTrusted || TKWoWLoginPageIsTrusted(webView.URL);
    _nextNavigationTrusted=NO; _rejectedCallback=NO;
}
- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation {
    // Some WebKit versions expose localhost:0 here, others only in the error
    // below. It is a delivery endpoint, not a page that should be contacted.
    if (![self isCurrentLoginNavigation:navigation webView:webView]) return;
    if ([self finishCallbackURL:webView.URL]) return;
    if (webView.URL && !TKWoWLoginPageIsTrusted(webView.URL)) _mainNavigationTrusted=NO;
}
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    if (_finished || webView!=_web) return;
    if (TKWoWLoginPageIsTrusted(webView.URL)) {
        _visitedLogin=YES; _host.text=webView.URL.host;
        _mainNavigation=navigation; _mainNavigationTrusted=YES;
    }
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (_finished || webView!=_web || (navigation && _mainNavigation && navigation!=_mainNavigation)) return;
    if ([error.domain isEqual:NSURLErrorDomain] && error.code==NSURLErrorCancelled) return;
    // WebKit can reject port 0 before decidePolicyForNavigationAction sees the
    // final redirect. Waypoint handles the same case via the failing URL.
    // Read only the documented URL fields, never localizedDescription or a
    // nested error; those may contain credentials and unrelated URLs.
    id value=error.userInfo[NSURLErrorFailingURLErrorKey];
    NSURL *url=[value isKindOfClass:NSURL.class]?value:nil;
    if (!url) {
        id string=error.userInfo[NSURLErrorFailingURLStringErrorKey];
        if ([string isKindOfClass:NSString.class] && [string length]<=8192) url=[NSURL URLWithString:string];
    }
    if ([self isCurrentLoginNavigation:navigation webView:webView] && [self finishCallbackURL:url]) return;
    NSString *kind=[error.domain isEqual:NSURLErrorDomain]?@"network":
        ([error.domain isEqual:WKErrorDomain] || [error.domain isEqual:@"WebKitErrorDomain"])?@"WebKit":@"navigation";
    [self finish:nil failure:[NSString stringWithFormat:@"The Battle.net login page could not load (%@ %ld). Please try again.",kind,(long)error.code]];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self webView:webView didFailProvisionalNavigation:navigation withError:error];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    (void)webView; [self finish:nil failure:@"The login page closed. Please try again."];
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    (void)configuration; (void)features;
    if (!_finished && !_externalLoginActive && !action.targetFrame && TKWoWLoginPageIsTrusted(action.request.URL)) [webView loadRequest:action.request];
    return nil;
}
@end
