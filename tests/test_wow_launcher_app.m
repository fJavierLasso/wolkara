// Isolated UIKit fixture: our synthetic installation, no network or guest execution.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#import <objc/runtime.h>
#include <stdatomic.h>
#import "../launcher/WoW/WoWViewController.h"
#import "../launcher/WoW/Client.h"
#import "../launcher/WoW/Updater.h"
#import "../launcher/App/LaunchProgressView.h"
#import "wow_installation_fixture.h"
#import "../launcher/WoW/GameToolsViewController.h"
#import "../launcher/WoW/AddonManager.h"
#import "../launcher/WoW/AddonStore.h"
#import "../launcher/WoW/AddonBrowser.h"
#import "../launcher/WoW/BattleNetBrowser.h"
#import "../launcher/WoW/BattleNetLogin.h"
#import <WebKit/WebKit.h>

@interface TKLoginTestFrame : NSObject
@property(nonatomic, getter=isMainFrame) BOOL mainFrame;
@end
@implementation TKLoginTestFrame
@end
@interface TKLoginTestNavigation : NSObject
@property(nonatomic) NSURLRequest *request;
@property(nonatomic) TKLoginTestFrame *sourceFrame, *targetFrame;
@end
@implementation TKLoginTestNavigation
@end
@interface TKLoginTestWebView : WKWebView
@property(nonatomic) NSURL *fixtureURL;
@end
@implementation TKLoginTestWebView
- (NSURL *)URL { return self.fixtureURL; }
@end
@interface TKWoWBattleNetBrowser (Fixture)
- (void)cancel;
@end
static void TestLoginCallbacks(void) {
    WKWebView *web=[WKWebView new]; // No loadRequest: network-free delegate fixture.
    NSString *token=@"US-0123456789abcdef0123456789abcdef-123456789";
    TKLoginTestNavigation *action=[TKLoginTestNavigation new];
    action.request=[NSURLRequest requestWithURL:[NSURL URLWithString:[@"http://localhost:0/?ST=" stringByAppendingString:token]]];
    action.sourceFrame=[TKLoginTestFrame new]; action.targetFrame=[TKLoginTestFrame new];
    action.targetFrame.mainFrame=YES;
    __block NSUInteger calls=0;
    TKWoWBattleNetBrowser *browser=[[TKWoWBattleNetBrowser alloc] initWithRegion:@"eu" completion:^(NSString *ticket,NSString *failure) {
        assert([ticket isEqual:token] && !failure); calls++;
    }];
    // Do not load its view: these delegate fixtures never request a web page.
    [browser setValue:@YES forKey:@"visitedLogin"];
    void (^policy)(WKNavigationActionPolicy)=^(WKNavigationActionPolicy value) { assert(value==WKNavigationActionPolicyCancel); };
    [(id<WKNavigationDelegate>)browser webView:web decidePolicyForNavigationAction:(id)action decisionHandler:policy];
    assert(calls==0); // iframe targeting the main frame cannot supply a ticket
    action.sourceFrame.mainFrame=YES; action.targetFrame.mainFrame=NO;
    [(id<WKNavigationDelegate>)browser webView:web decidePolicyForNavigationAction:(id)action decisionHandler:policy];
    assert(calls==0);
    action.targetFrame.mainFrame=YES;
    [(id<WKNavigationDelegate>)browser webView:web decidePolicyForNavigationAction:(id)action decisionHandler:policy];
    assert(calls==1);
    [(id<WKNavigationDelegate>)browser webView:web decidePolicyForNavigationAction:(id)action decisionHandler:policy];
    [browser cancel]; assert(calls==1); // completion is terminal, including late cancellation
    browser=[[TKWoWBattleNetBrowser alloc] initWithRegion:@"eu" completion:^(NSString *ticket,NSString *failure) {
        assert(!ticket && failure); calls++;
    }];
    [(id<WKNavigationDelegate>)browser webView:web decidePolicyForNavigationAction:(id)action decisionHandler:policy];
    assert(calls==2); // no committed Blizzard login page
    browser=[[TKWoWBattleNetBrowser alloc] initWithRegion:@"eu" completion:^(NSString *ticket,NSString *failure) {
        assert(!ticket && !failure); calls++;
    }];
    [browser cancel];
    [(id<WKNavigationDelegate>)browser webView:web decidePolicyForNavigationAction:(id)action decisionHandler:policy];
    assert(calls==3);
}
static TKWoWBattleNetBrowser *LoginBrowser(TKLoginTestWebView *web, WKNavigation *navigation, BOOL visited,
    void (^completion)(NSString *,NSString *)) {
    TKWoWBattleNetBrowser *browser=[[TKWoWBattleNetBrowser alloc] initWithRegion:@"eu" completion:completion];
    // No loadView/loadRequest: drive the real delegate with synthetic WebKit
    // events and distinct navigation identities, without network or an account.
    [browser setValue:web forKey:@"web"];
    web.fixtureURL=TKWoWLoginURL(@"eu");
    TKLoginTestNavigation *action=[TKLoginTestNavigation new];
    action.request=[NSURLRequest requestWithURL:web.fixtureURL];
    action.sourceFrame=[TKLoginTestFrame new]; action.sourceFrame.mainFrame=YES;
    action.targetFrame=[TKLoginTestFrame new]; action.targetFrame.mainFrame=YES;
    id<WKNavigationDelegate> delegate=(id)browser;
    [delegate webView:web decidePolicyForNavigationAction:(id)action decisionHandler:^(WKNavigationActionPolicy value) {
        assert(value==WKNavigationActionPolicyAllow);
    }];
    [delegate webView:web didStartProvisionalNavigation:navigation];
    if (visited) [delegate webView:web didCommitNavigation:navigation];
    return browser;
}
static void TestLoginRedirectFailures(void) {
    TKLoginTestWebView *web=[TKLoginTestWebView new];
    WKNavigation *navigation=(id)[NSObject new];
    NSURL *callback=[NSURL URLWithString:@"http://localhost:0/?ST=US-0123456789abcdef0123456789abcdef-123456789"];
    NSString *ticket=TKWoWLoginTicketFromURL(callback);
    __block NSUInteger successes=0, failures=0, cancelled=0;
    void (^completion)(NSString *,NSString *)=^(NSString *value, NSString *failure) {
        if (value) { assert([value isEqual:ticket] && !failure); successes++; }
        else if (failure) {
            assert(![failure containsString:ticket] && ![failure containsString:@"localhost"]);
            assert(![failure containsString:@"private-description"]); failures++;
        } else cancelled++;
    };
    for (NSString *key in @[NSURLErrorFailingURLErrorKey,NSURLErrorFailingURLStringErrorKey]) {
        TKWoWBattleNetBrowser *browser=LoginBrowser(web,navigation,YES,completion);
        NSError *error=[NSError errorWithDomain:@"WebKitErrorDomain" code:103 userInfo:@{
            key:[key isEqual:NSURLErrorFailingURLErrorKey]?(id)callback:callback.absoluteString,
            NSLocalizedDescriptionKey:@"private-description"}];
        [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:navigation withError:error];
        [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:navigation withError:error];
        [browser cancel];
    }
    assert(successes==2 && failures==0 && cancelled==0);
    NSError *redirectError=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost
        userInfo:@{NSURLErrorFailingURLErrorKey:callback}];
    TKWoWBattleNetBrowser *browser=LoginBrowser(web,navigation,YES,completion);
    web.fixtureURL=callback;
    [(id<WKNavigationDelegate>)browser webView:web didReceiveServerRedirectForProvisionalNavigation:navigation];
    [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:navigation withError:redirectError];
    assert(successes==3 && failures==0);
    // A callback without a trusted committed login, a foreign web view, or a
    // superseded main navigation must never acquire a game session.
    browser=LoginBrowser(web,navigation,NO,completion);
    [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:navigation withError:redirectError];
    assert(successes==3 && failures==1);
    browser=LoginBrowser(web,navigation,YES,completion);
    TKLoginTestWebView *foreign=[TKLoginTestWebView new];
    [(id<WKNavigationDelegate>)browser webView:foreign didFailProvisionalNavigation:navigation withError:redirectError];
    WKNavigation *old=(id)[NSObject new];
    [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:old withError:redirectError];
    assert(successes==3 && failures==1);
    [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:navigation withError:redirectError];
    assert(successes==4);
    // Cancellation and a policy-rejected iframe callback cannot be promoted
    // into successful authentication through the error fallback.
    browser=LoginBrowser(web,navigation,YES,completion);
    NSError *cancel=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:@{NSURLErrorFailingURLErrorKey:callback}];
    [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:navigation withError:cancel];
    assert(successes==4 && failures==1); [browser cancel]; assert(cancelled==1);
    [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:navigation withError:redirectError];
    assert(successes==4);
    browser=LoginBrowser(web,navigation,YES,completion);
    TKLoginTestNavigation *iframe=[TKLoginTestNavigation new];
    iframe.request=[NSURLRequest requestWithURL:callback];
    iframe.sourceFrame=[TKLoginTestFrame new];
    iframe.targetFrame=[TKLoginTestFrame new]; iframe.targetFrame.mainFrame=YES;
    [(id<WKNavigationDelegate>)browser webView:web decidePolicyForNavigationAction:(id)iframe decisionHandler:^(WKNavigationActionPolicy policy) {
        assert(policy==WKNavigationActionPolicyCancel);
    }];
    [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:navigation withError:redirectError];
    assert(successes==4 && failures==2);
    for (NSURL *url in @[[NSURL URLWithString:[callback.absoluteString stringByAppendingString:@"&ST=duplicate"]],
        [NSURL URLWithString:[callback.absoluteString stringByReplacingOccurrencesOfString:@"localhost" withString:@"evil.test"]],
        [NSURL URLWithString:@"https://eu.battle.net/login/"]]) {
        browser=LoginBrowser(web,navigation,YES,completion);
        NSError *error=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet
            userInfo:@{NSURLErrorFailingURLErrorKey:url,NSLocalizedDescriptionKey:@"private-description"}];
        [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:navigation withError:error];
    }
    assert(successes==4 && failures==5);
    browser=LoginBrowser(web,navigation,YES,completion);
    NSError *nested=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorServerCertificateUntrusted
        userInfo:@{NSUnderlyingErrorKey:redirectError}];
    [(id<WKNavigationDelegate>)browser webView:web didFailProvisionalNavigation:navigation withError:nested];
    assert(successes==4 && failures==6);
    puts("Battle.net browser PASS: redirect/error delivery, URL/string error fields, no replay, main-navigation binding and safe failures.");
}

// The production Swift archive is covered by test_forever_ui_archive.swift.
// This UI fixture only needs its no-pending-restore bridge to open the launcher.
@interface TKForeverUIArchive : NSObject
@end
@implementation TKForeverUIArchive
+ (BOOL)recoverInterruptedRestoreInWorkingDirectory:(NSString *)directory error:(NSError **)error {
    (void)directory; (void)error; return YES;
}
@end

@interface TKWoWViewController (Fixture)
- (void)selectProduct:(NSDictionary *)product;
- (void)refresh;
- (void)about;
- (void)repairInstallation;
- (void)manageAddons;
@end
static atomic_uint requests, revision, updates, repairs;
static atomic_bool failure, slow, interruptRepair;
static TKFixtureLibrary *fixture;
static NSDictionary *Plan(id self, SEL selector, NSString *product, NSString *region, NSString *locale, NSError **error) {
    (void)self; (void)selector; (void)region; (void)locale;
    unsigned request=atomic_fetch_add(&requests,1);
    [NSThread sleepForTimeInterval:(request==0 || atomic_load(&slow))?0.5:0.02];
    if (atomic_load(&failure)) { if (error) *error=TKWoWError(@"Synthetic offline response"); return nil; }
    return [fixture planForProduct:product revision:atomic_load(&revision)];
}
static BOOL Update(id self, SEL selector, NSDictionary *plan, NSString *root,
                   void (^progress)(NSString *,uint64_t,uint64_t), NSError **error) {
    (void)selector; (void)plan;
    assert([root isEqual:fixture.root]);
    if([(TKWoWUpdater *)self fullVerification]) {
        atomic_fetch_add(&repairs,1);
        if(atomic_exchange(&interruptRepair,false)) { if(error)*error=TKWoWError(@"Synthetic repair interruption");return NO; }
    }
    atomic_fetch_add(&updates,1); progress(@"download",50,100);
    [fixture writeMetadata:atomic_load(&revision) duplicate:NO];
    progress(@"complete",1,1); return YES;
}
static UIView *Find(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *child in view.subviews) { UIView *match=Find(child,identifier); if (match) return match; }
    return nil;
}
static CALayer *ActivityLayer(CALayer *layer) {
    if ([layer.name isEqual:@"startup.activity"]) return layer;
    for (CALayer *child in layer.sublayers) { CALayer *found=ActivityLayer(child); if (found) return found; }
    return nil;
}
@interface TKWoWAddonManagerViewController (AddonFixture)
- (void)browseCurseForge;
@end
static void TestAddonBrowserPolicy(void) {
    assert(TKAddonDownloadURLIsTrusted([NSURL URLWithString:@"https://edge.forgecdn.net/files/addon.zip"]));
    assert(TKAddonDownloadURLIsTrusted([NSURL URLWithString:@"https://www.curseforge.com/wow/addons/example/download/1"]));
    for (NSString *url in @[@"http://edge.forgecdn.net/a.zip",@"https://forgecdn.net.evil.test/a.zip",@"https://evil.test/a.zip",@"https://user:pass@forgecdn.net/a.zip",@"file:///tmp/a.zip"])
        assert(!TKAddonDownloadURLIsTrusted([NSURL URLWithString:url]));
    NSURL *url=[NSURL URLWithString:@"https://edge.forgecdn.net/addon.zip"];
    assert(TKAddonResponseIsZIP([[NSURLResponse alloc] initWithURL:url MIMEType:@"application/zip" expectedContentLength:10 textEncodingName:nil]));
    assert(!TKAddonResponseIsZIP([[NSURLResponse alloc] initWithURL:url MIMEType:@"text/html" expectedContentLength:10 textEncodingName:nil]));
    assert([TKAddonBrowseURL(@"wowf").absoluteString containsString:@"gameVersionTypeId=88568"]);
    assert(![TKAddonBrowseURL(@"wow").absoluteString containsString:@"88568"]);
}

@interface TKWoWFixtureDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic) UIWindow *window;
@property(nonatomic) TKWoWViewController *controller;
@property(nonatomic) NSUInteger launches, setups;
@property(nonatomic) CGFloat activityPosition;
@end
@implementation TKWoWFixtureDelegate
- (UIButton *)primary { return (id)Find(self.controller.view,@"wow.primary"); }
- (NSString *)status { return [(UILabel *)Find(self.controller.view,@"wow.status") text]; }
- (void)tap { [[self primary] sendActionsForControlEvents:UIControlEventTouchUpInside]; }
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    method_setImplementation(class_getInstanceMethod(TKWoWClient.class,@selector(planForProduct:region:locale:error:)),(IMP)Plan);
    method_setImplementation(class_getInstanceMethod(TKWoWUpdater.class,@selector(updatePlan:root:progress:error:)),(IMP)Update);
    [NSUserDefaults.standardUserDefaults setObject:@"wowf" forKey:@"WoWProduct"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:TKWoWBrowserLoginEnabledKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WoWRepairRequested.wowf"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WoWInstallRequested.wowf"];
    // Device language must not change this fork's English launcher UI.
    [NSUserDefaults.standardUserDefaults setObject:@[@"es-ES"] forKey:@"AppleLanguages"];
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        fprintf(stderr,"WoW UIKit TIMEOUT\n"); _Exit(1);
    });
    fixture=[TKFixtureLibrary new];
    // Start from an older launcher's ready installation. Its metadata must be
    // repaired by the real controller/updater before Play, without a download.
    fixture.omitCDNMetadata=YES; [fixture writeMetadata:0 duplicate:NO]; fixture.omitCDNMetadata=NO;
    NSString *retired=[fixture.directory stringByAppendingPathComponent:@"Interface/AddOns/WolkaraTouch"];
    assert([NSFileManager.defaultManager createDirectoryAtPath:retired withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([@"synthetic addon" writeToFile:[retired stringByAppendingPathComponent:@"Fixture.lua"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    NSString *mobile=[fixture.directory stringByAppendingPathComponent:@"Interface/AddOns/WolkaraMobile"];
    assert([NSFileManager.defaultManager createDirectoryAtPath:mobile withIntermediateDirectories:NO attributes:nil error:NULL]);
    assert([@"WolkaraMobile bundled addon v1\n" writeToFile:[mobile stringByAppendingPathComponent:@".wolkara-owner"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraTouchHintShown"];
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.controller=[[TKWoWViewController alloc] initWithLibrary:(id)fixture];
    __weak TKWoWFixtureDelegate *weakSelf=self;
    self.controller.startApp=^(TKApp *app) { assert(app==(id)fixture.apps[0]); weakSelf.launches++; };
    self.controller.executionMode=TKExecutionModeDeveloperService;
    self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:self.controller];
    [self.window makeKeyAndVisible];
    [self performSelector:@selector(changeSelection) withObject:nil afterDelay:0.1];
}
- (void)changeSelection {
    [self.controller selectProduct:TKWoWProducts()[1]];
    [self performSelector:@selector(checkSelection) withObject:nil afterDelay:0.8];
}
- (void)checkSelection {
    assert([self primary].enabled);
    assert([[(UIButton *)Find(self.controller.view,@"wow.edition") configuration].title containsString:@"Classic Era"]);
    assert([[(UILabel *)Find(self.controller.view,@"wow.version") text] containsString:@"demo"]);
    [self.controller selectProduct:TKWoWProducts()[0]];
    [self performSelector:@selector(checkReady) withObject:nil afterDelay:0.3];
}
- (void)checkReady {
    assert(!TKWoWInspectInstallation((id)fixture,TKWoWProducts()[0],[fixture planForProduct:@"wowf" revision:0]).metadataNeedsRepair);
    assert(atomic_load(&updates)==0); // Legacy CDN repair did not install/download.
    assert(!self.controller.presentedViewController);
    assert(![NSFileManager.defaultManager fileExistsAtPath:[fixture.directory stringByAppendingPathComponent:@"Interface/AddOns/WolkaraTouch"]]);
    assert(![NSFileManager.defaultManager fileExistsAtPath:[fixture.directory stringByAppendingPathComponent:@"Interface/AddOns/WolkaraMobile"]]);
    assert([self primary].enabled);
    assert([[self status] isEqual:@"Ready to play"] && self.controller.title.length==0);
    assert([[(UILabel *)Find(self.controller.view,@"wow.title") text] isEqual:@"WOLKARA"]);
    self.controller.executionMode=TKExecutionModeNone;
    assert(![self primary].enabled);
    self.controller.executionMode=TKExecutionModeDeveloperService;
    atomic_store(&revision,1); [self.controller refresh];
    [self performSelector:@selector(checkOutdated) withObject:nil afterDelay:0.3];
}
- (void)checkOutdated {
    assert([self primary].enabled && self.launches==0 && atomic_load(&updates)==1);
    assert(atomic_load(&repairs)==0);
    atomic_store(&interruptRepair,true);[self.controller repairInstallation];
    [self performSelector:@selector(checkRepairPaused) withObject:nil afterDelay:0.3];
}
- (void)checkRepairPaused {
    assert(atomic_load(&repairs)==1);
    assert([NSUserDefaults.standardUserDefaults boolForKey:@"WoWRepairRequested.wowf"]);
    [self.controller refresh];
    [self performSelector:@selector(checkRepairComplete) withObject:nil afterDelay:0.3];
}
- (void)checkRepairComplete {
    assert(atomic_load(&repairs)==2 && [self primary].enabled && self.launches==0);
    assert(![NSUserDefaults.standardUserDefaults boolForKey:@"WoWRepairRequested.wowf"]);
    atomic_store(&failure,true); [self.controller refresh];
    [self performSelector:@selector(checkOffline) withObject:nil afterDelay:0.3];
}
- (void)checkOffline {
    assert([self primary].enabled && self.launches==0);
    atomic_store(&failure,false); [self tap];
    [self performSelector:@selector(startThenBackground) withObject:nil afterDelay:0.3];
}
- (void)startThenBackground {
    assert([self primary].enabled);
    atomic_store(&slow,true); [self tap];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    assert(![self primary].enabled && UIApplication.sharedApplication.idleTimerDisabled);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    assert([[self status] isEqual:@"Check paused"] && [self primary].enabled);
    assert(!UIApplication.sharedApplication.idleTimerDisabled);
    [self performSelector:@selector(checkCancellation) withObject:nil afterDelay:0.7];
}
- (void)checkCancellation {
    assert(self.launches==0 && [[self status] isEqual:@"Check paused"]); atomic_store(&slow,false);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [self performSelector:@selector(checkResumed) withObject:nil afterDelay:0.3];
}
- (void)checkResumed {
    assert(self.launches==0 && [[self status] isEqual:@"Ready to play"]);
    assert(!UIApplication.sharedApplication.idleTimerDisabled);
    unsigned before=atomic_load(&requests);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    assert(atomic_load(&requests)==before);
    [self captureAndLaunch];
}
- (void)captureAndLaunch {
    assert([self primary].enabled);
    [self.window layoutIfNeeded];
    CGRect button=[[self primary] convertRect:[self primary].bounds toView:self.window];
    assert(CGRectContainsRect(self.window.bounds,button));
    UILabel *label=(id)Find(self.controller.view,@"wow.status");
    CGRect text=[label textRectForBounds:label.bounds limitedToNumberOfLines:label.numberOfLines];
    NSLog(@"DESCENDER_METRICS: frame=%@ text=%@ lineHeight=%g ascender=%g descender=%g",NSStringFromCGRect(label.frame),NSStringFromCGRect(text),label.font.lineHeight,label.font.ascender,label.font.descender);
    assert(label.bounds.size.height + 0.01 >= label.font.lineHeight);
    assert(text.origin.y >= 0 && CGRectGetMaxY(text) <= label.bounds.size.height + 0.5);
    self.controller.traitOverrides.preferredContentSizeCategory=UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
    [self performSelector:@selector(captureLargeText) withObject:nil afterDelay:0.3];
}
- (void)captureLargeText {
    [self.window layoutIfNeeded];
    UILabel *label=(id)Find(self.controller.view,@"wow.status");
    assert(label.bounds.size.height + 0.01 >= label.font.lineHeight);
    assert(CGRectGetMaxY([label textRectForBounds:label.bounds limitedToNumberOfLines:label.numberOfLines]) <= label.bounds.size.height + 0.5);
    UIScrollView *scroll=(id)Find(self.controller.view,@"wow.scroll");
    [scroll scrollRectToVisible:[label convertRect:label.bounds toView:scroll] animated:NO];
    [self capture:@"wow-home-large-text.png"];
    self.controller.traitOverrides.preferredContentSizeCategory=UIContentSizeCategoryLarge;
    [self performSelector:@selector(captureDefaultText) withObject:nil afterDelay:0.3];
}
- (void)captureDefaultText {
    [self.window layoutIfNeeded];
    UIScrollView *scroll=(id)Find(self.controller.view,@"wow.scroll");
    scroll.contentOffset=CGPointZero;
    [self capture:@"wow-home.png"];
    UIBarButtonItem *addonsItem=[self.controller valueForKey:@"addonsItem"];
    assert(addonsItem.enabled && [addonsItem.accessibilityIdentifier isEqual:@"wow.addons"]);
    NSString *example=[fixture.directory stringByAppendingPathComponent:@"Interface/AddOns/ExampleAddon"];
    assert([NSFileManager.defaultManager createDirectoryAtPath:example withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([@"## Interface: 16001\n## Title: Example addon\n## Version: 2.1\n" writeToFile:[example stringByAppendingPathComponent:@"Example.toc"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    NSString *database=[fixture.directory stringByAppendingPathComponent:@"Interface/AddOns/Database"];
    assert([NSFileManager.defaultManager createDirectoryAtPath:database withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSMutableString *largeTOC=[@"## Interface: 16001\n## Title: Database fixture\n## Version: 1\n" mutableCopy];
    [largeTOC appendString:[@"x" stringByPaddingToLength:1024*1024 withString:@"x" startingAtIndex:0]];
    assert([largeTOC writeToFile:[database stringByAppendingPathComponent:@"Database_Forever.toc"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    NSArray<TKWoWAddon *> *listed=TKWoWAddonsAtDirectory(database.stringByDeletingLastPathComponent);
    assert(listed.count==2 && [listed.firstObject.title isEqual:@"Database fixture"]);
    [self.controller manageAddons];
    TKWoWAddonManagerViewController *manager=(id)self.controller.navigationController.topViewController;
    assert([manager isKindOfClass:TKWoWAddonManagerViewController.class]);
    assert([[[manager valueForKey:@"store"] valueForKey:@"product"] isEqual:@"wowf"]);
    assert([[manager valueForKey:@"store"] records].count==2);
    [manager loadViewIfNeeded];
    [self performSelector:@selector(captureAddonManager) withObject:nil afterDelay:0.4];
}
- (void)captureAddonManager {
    [self capture:@"wow-addons.png"];
    TKWoWAddonManagerViewController *manager=(id)self.controller.navigationController.topViewController;
    assert(Find(manager.view,@"wow.addons.browse"));
    assert(![manager respondsToSelector:NSSelectorFromString(@"setupKey")]);
    assert(!NSClassFromString(@"TKCurseForgeClient") && !NSClassFromString(@"TKAddonCredentialStore"));
    [self.controller.navigationController popToRootViewControllerAnimated:NO];
    [self tap]; [self performSelector:@selector(checkLaunch) withObject:nil afterDelay:0.3];
}
- (void)capture:(NSString *)name {
    [self.window layoutIfNeeded];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context; [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
    }];
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    assert([UIImagePNGRepresentation(image) writeToFile:[documents stringByAppendingPathComponent:name] atomically:YES]);
}
- (void)checkLaunch {
    assert(self.launches==1); self.controller.sessionUsed=YES;
    [self.controller beginStartup];
    self.controller.startupStatusLabel.text=@"Preparing to run. This can take a few minutes. Keep this app open.";
    assert(![self primary].enabled && !self.controller.launchProgress.hidden);
    assert(![(UIBarButtonItem *)[self.controller valueForKey:@"addonsItem"] isEnabled]);
    [self.controller manageAddons];
    assert(self.controller.navigationController.topViewController==self.controller);
    assert([[self status] isEqual:@"Starting…"]);
    assert(self.controller.navigationController.viewControllers.count==1);
    TKLaunchProgressView *progress=self.controller.launchProgress;
    assert([progress.accessibilityLabel isEqual:@"Startup progress"]);
    [progress showPhase:TKLaunchPhaseMemory];
    [progress showPhase:TKLaunchPhaseConnection]; // A duplicate start cannot undo completed work.
    assert([progress.accessibilityValue containsString:@"1 of 3"]);
    [self.window layoutIfNeeded];
    CALayer *activity=ActivityLayer(progress.layer); assert(activity);
    [activity removeAllAnimations]; // The OS can do this during an app handoff.
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    assert([progress.accessibilityValue containsString:@"1 of 3"]);
    if (!UIAccessibilityIsReduceMotionEnabled()) assert([activity animationForKey:@"activity"]);
    [self performSelector:@selector(checkProgressFirstFrame) withObject:nil afterDelay:0.15];
}
- (void)checkProgressFirstFrame {
    CALayer *activity=ActivityLayer(self.controller.launchProgress.layer);
    self.activityPosition=activity.presentationLayer.position.x;
    [self performSelector:@selector(checkLaunchAfterProgress) withObject:nil afterDelay:0.30];
}
- (void)checkLaunchAfterProgress {
    TKLaunchProgressView *progress=self.controller.launchProgress;
    CALayer *activity=ActivityLayer(progress.layer);
    if (!UIAccessibilityIsReduceMotionEnabled())
        assert(fabs(activity.presentationLayer.position.x-self.activityPosition)>1);
    [progress showPhase:TKLaunchPhaseGame];
    assert([progress.accessibilityValue containsString:@"2 of 3"]);
    unsigned before=atomic_load(&requests);
    [self.controller refresh]; [self tap];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    assert(atomic_load(&requests)==before && self.launches==1);
    [self capture:@"wow-starting.png"];
    [self.controller finishStartupWithMessage:@"Synthetic startup failure" failed:YES];
    assert([[self status] isEqual:@"Could not start"] && ![self primary].enabled);
    assert(self.controller.launchProgress.hidden && !self.controller.diagnosticsButton.hidden);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    assert(![activity animationForKey:@"activity"]); // Returning after failure must stay stopped.
    [self capture:@"wow-startup-failed.png"];
    [self.controller finishStartupWithMessage:@"Session ended" failed:NO];
    assert(![self primary].enabled && self.controller.diagnosticsButton.hidden);
    // A recoverable preflight error must leave another attempt possible.
    self.controller.sessionUsed=NO;
    [self.controller beginStartup];
    assert([progress.accessibilityValue containsString:@"0 of 3"]);
    [self.controller finishStartupWithMessage:@"Synthetic missing container" failed:YES];
    assert([self primary].enabled);
    [self.controller about];
    UITextView *credits=(id)self.controller.navigationController.topViewController.view;
    assert([credits.text containsString:@"Vasilii Kharitonov"]);
    assert([credits.text containsString:@"Permission is hereby granted"]);
    assert([credits.text containsString:@"Martin Benjamins"]);
    [self.controller.navigationController popToRootViewControllerAnimated:NO];
    assert([credits.text containsString:@"John Klockenkemper"]);
    TKGameToolsViewController *tools=[[TKGameToolsViewController alloc] initWithWorkingDirectory:fixture.directory
        product:@"wow" edition:@"Retail" version:@"12.0.5.99999"];
    UINavigationController *toolNavigation=[[UINavigationController alloc] initWithRootViewController:tools];
    [toolNavigation loadViewIfNeeded]; [tools loadViewIfNeeded];
    assert([tools.tableView numberOfRowsInSection:0]==5);
    assert([tools.tableView numberOfSections]==1);
    [tools tableView:tools.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    TKWoWAddonManagerViewController *addons=(id)toolNavigation.topViewController;
    assert([addons isKindOfClass:TKWoWAddonManagerViewController.class]);
    assert([[addons valueForKey:@"installedGameVersion"] isEqual:@"12.0.5"]);
    assert([[[addons valueForKey:@"store"] valueForKey:@"product"] isEqual:@"wow"]);
    [self.controller.navigationController popToRootViewControllerAnimated:NO];
    TestAddonBrowserPolicy();
    TestLoginCallbacks();
    TestLoginRedirectFailures();
    puts("WoW UIKit PASS: addon launcher access, edition context, website download policy; automatic check/update, offline retry, edition race, background cancellation, verified launch, inline preparation/failure/session end, no duplicate launches and bundled licenses."); fflush(stdout);
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) exit(0);
    // Leave a ready home for visual inspection; no real download or guest runs.
    [self.controller refresh];
}

@end
@interface TKWoWFixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation TKWoWFixtureApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *config=[[UISceneConfiguration alloc] initWithName:@"WoW fixture" sessionRole:session.role];
    config.delegateClass=TKWoWFixtureDelegate.class; return config;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(TKWoWFixtureApp.class)); }
}
