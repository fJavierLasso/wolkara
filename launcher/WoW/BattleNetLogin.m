#import "BattleNetLogin.h"
#import <CommonCrypto/CommonCrypto.h>

NSString *const TKWoWBrowserLoginEnabledKey=@"WoWBrowserLoginEnabled";
static void Clear(void *bytes, size_t count) { volatile uint8_t *p=bytes; while (count--) *p++=0; }
static NSError *LoginError(NSString *message) {
    // Never incorporate an underlying web error/URL: it may contain a ticket.
    return [NSError errorWithDomain:@"Wolkara.BattleNetLogin" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL TicketValid(NSString *ticket) {
    if (![ticket isKindOfClass:NSString.class] || ticket.length>128) return NO;
    NSArray<NSString *> *parts=[ticket componentsSeparatedByString:@"-"];
    if (parts.count!=3 || ![@[@"US",@"EU",@"KR",@"CN",@"TW"] containsObject:parts[0]] ||
        parts[1].length!=32 || !parts[2].length || parts[2].length>20) return NO;
    return [parts[1] rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location==NSNotFound &&
        [parts[2] rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location==NSNotFound;
}
NSURL *TKWoWLoginURL(NSString *region) {
    if (![@[@"eu",@"us",@"kr",@"tw"] containsObject:region]) return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://%@.battle.net/login/en/?externalChallenge=login&app=WoW",region]];
}
BOOL TKWoWLoginPageIsTrusted(NSURL *url) {
    if (!url || url.absoluteString.length>8192) return NO;
    NSURLComponents *c=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (![c.scheme.lowercaseString isEqual:@"https"] || c.user || c.password || (c.port && c.port.integerValue!=443)) return NO;
    NSString *host=c.host.lowercaseString;
    for (NSString *domain in @[@"battle.net",@"blizzard.com",@"battlenet.com.cn",@"blizzard.cn"])
        if ([host isEqual:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]) return YES;
    return NO;
}
BOOL TKWoWLoginCallbackURL(NSURL *url) {
    if (!url || url.absoluteString.length>8192) return NO;
    NSURLComponents *c=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    return [c.scheme.lowercaseString isEqual:@"http"] && [c.host.lowercaseString isEqual:@"localhost"] &&
        c.port && c.port.integerValue==0 && !c.user && !c.password && !c.fragment &&
        (!c.path.length || [c.path isEqual:@"/"]);
}
NSString *TKWoWLoginTicketFromURL(NSURL *url) {
    if (!TKWoWLoginCallbackURL(url)) return nil;
    NSURLComponents *c=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *ticket=nil; NSUInteger count=0;
    for (NSURLQueryItem *item in c.queryItems) if ([item.name isEqual:@"ST"]) { count++; ticket=item.value; }
    return count==1 && TicketValid(ticket)?ticket:nil;
}
NSData *TKWoWEncryptLoginTicket(NSString *ticket, NSString *userName, NSError **error) {
    if (!TicketValid(ticket) || !userName.length) {
        if (error) *error=LoginError(@"Battle.net returned an unsupported login ticket."); return nil;
    }
    // Waypoint LaunchOptions.swift, 0BSD: RegistryDarwin's wire format.
    // This fixed format is interoperability, not a secure persistent vault.
    uint8_t password[16]={200,118,244,174,76,149,46,254,242,250,15,84,25,192,156,67};
    for (NSUInteger i=0;i<MIN(userName.length,sizeof password);i++) password[i]^=(uint8_t)[userName characterAtIndex:i];
    const uint8_t salt[]="someSalt"; uint8_t key[16]={0}, iv[16]={0};
    int status=CCKeyDerivationPBKDF(kCCPBKDF2,(const char *)password,sizeof password,
        salt,sizeof salt-1,kCCPRFHmacAlgSHA1,1000,key,sizeof key);
    Clear(password,sizeof password);
    NSMutableData *plain=[[ticket dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    NSMutableData *cipher=[NSMutableData dataWithLength:plain.length+kCCBlockSizeAES128]; size_t written=0;
    if (status==kCCSuccess) status=CCCrypt(kCCEncrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,
        key,sizeof key,iv,plain.bytes,plain.length,cipher.mutableBytes,cipher.length,&written);
    Clear(key,sizeof key); Clear(plain.mutableBytes,plain.length);
    if (status!=kCCSuccess) {
        Clear(cipher.mutableBytes,cipher.length);
        if (error) *error=LoginError(@"Could not prepare the Battle.net login handoff."); return nil;
    }
    cipher.length=written; return cipher;
}
static NSArray<NSString *> *HandoffKeys(void) {
    return @[@"WEB_TOKEN",@"ACCOUNT_TS",@"REGION",@"LOCALE",@"GAME_ACCOUNT",@"CONNECTION_STRING"];
}
static NSString *OptionKey(NSString *key) { return [@"Launch Options/WoW/" stringByAppendingString:key]; }
void TKWoWClearLoginHandoff(NSString *domain) {
    for (NSString *key in HandoffKeys()) CFPreferencesSetAppValue((__bridge CFStringRef)OptionKey(key),NULL,(__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}
@implementation TKWoWLoginHandoff {
    NSMutableData *_cipher;
    NSString *_product, *_region, *_locale, *_appID;
    NSDate *_createdAt;
}
- (instancetype)initWithTicket:(NSString *)ticket userName:(NSString *)userName
    product:(NSString *)product region:(NSString *)region locale:(NSString *)locale
    appID:(NSString *)appID createdAt:(NSDate *)date error:(NSError **)error {
    if (!(self=[super init])) return nil;
    if (![@[@"wowf",@"wow_classic_era",@"wow_classic",@"wow",@"wow_beta"] containsObject:product] ||
        !TKWoWLoginURL(region) || ![@[@"enUS",@"esES"] containsObject:locale] || !appID.length) {
        if (error) *error=LoginError(@"This game or region does not support browser login."); return nil;
    }
    _cipher=[TKWoWEncryptLoginTicket(ticket,userName,error) mutableCopy]; if (!_cipher) return nil;
    _product=[product copy]; _region=region.uppercaseString; _locale=[locale copy];
    _appID=[appID copy]; _createdAt=date; return self;
}
- (NSString *)description { return @"<TKWoWLoginHandoff: private>"; }
- (void)invalidate { if (_cipher) Clear(_cipher.mutableBytes,_cipher.length); _cipher=nil; }
- (void)dealloc { [self invalidate]; }
- (NSArray<NSString *> *)consumeForAppID:(NSString *)appID arguments:(NSArray<NSString *> *)arguments
    preferencesDomain:(NSString *)domain now:(NSDate *)date error:(NSError **)error {
    NSTimeInterval age=[date timeIntervalSinceDate:_createdAt];
    if (!_cipher || ![_appID isEqual:appID] || age<0 || age>600) {
        [self invalidate];
        if (error) *error=LoginError(@"The browser login expired. Close and reopen Wolkara to sign in again."); return nil;
    }
    // Consume once, including failures; never replay a previous account/attempt.
    NSData *cipher=[_cipher copy]; [self invalidate];
    TKWoWClearLoginHandoff(domain);
    NSDictionary *values=@{@"WEB_TOKEN":cipher,@"REGION":_region,@"LOCALE":_locale,
        @"ACCOUNT_TS":[NSString stringWithFormat:@"%.0f",date.timeIntervalSince1970]};
    for (NSString *key in values) CFPreferencesSetAppValue((__bridge CFStringRef)OptionKey(key),(__bridge CFPropertyListRef)values[key],(__bridge CFStringRef)domain);
    BOOL ok=CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    // iOS's preferences sandbox must expose the exact domain to the guest.
    for (NSString *key in values) {
        id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)OptionKey(key),(__bridge CFStringRef)domain));
        if (![value isEqual:values[key]]) ok=NO;
    }
    if (!ok) {
        TKWoWClearLoginHandoff(domain);
        if (error) *error=LoginError(@"Could not save the Battle.net handoff in this app's container."); return nil;
    }
    NSMutableArray *result=[NSMutableArray new];
    for (NSUInteger i=0;i<arguments.count;i++) {
        NSString *argument=arguments[i];
        if ([argument isEqual:@"-launcherlogin"]) continue;
        if ([argument isEqual:@"-uid"]) { if (i+1<arguments.count) i++; continue; }
        if ([argument hasPrefix:@"-uid="]) continue;
        [result addObject:argument];
    }
    [result addObjectsFromArray:@[@"-launcherlogin",@"-uid",_product]];
    return result;
}
@end
