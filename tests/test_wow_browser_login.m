// Synthetic tickets only. Never touches the Mac's net.battle preferences.
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import "../launcher/WoW/BattleNetLogin.h"

static NSString *const Ticket=@"US-0123456789abcdef0123456789abcdef-123456789";
static NSString *Hex(NSData *data) {
    NSMutableString *s=[NSMutableString new]; const uint8_t *p=data.bytes;
    for (NSUInteger i=0;i<data.length;i++) [s appendFormat:@"%02x",p[i]]; return s;
}
static TKWoWLoginHandoff *Handoff(NSDate *date) {
    return [[TKWoWLoginHandoff alloc] initWithTicket:Ticket userName:@"testuser" product:@"wowf"
        region:@"eu" locale:@"enUS" appID:@"synthetic-app" createdAt:date error:NULL];
}
static void Put(NSString *domain, NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,(__bridge CFStringRef)domain);
}
static id Get(NSString *domain, NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,(__bridge CFStringRef)domain));
}
int main(void) { @autoreleasepool {
    assert([TKWoWLoginURL(@"eu").absoluteString isEqual:@"https://eu.battle.net/login/en/?externalChallenge=login&app=WoW"]);
    assert(!TKWoWLoginURL(@"eu.evil.test"));
    assert(TKWoWLoginPageIsTrusted(TKWoWLoginURL(@"us")));
    assert(TKWoWLoginPageIsTrusted([NSURL URLWithString:@"https://account.battle.net:443/login/"]));
    for (NSString *s in @[@"https://battle.net.evil.test/",@"http://eu.battle.net/",@"https://battle.net@evil.test/",
        @"https://user@battle.net/",@"https://battle.net:8443/",@"file:///battle.net",@"https://evilbattle.net/"])
        assert(!TKWoWLoginPageIsTrusted([NSURL URLWithString:s]));
    NSString *callback=[@"http://localhost:0/?ST=" stringByAppendingString:Ticket];
    assert([TKWoWLoginTicketFromURL([NSURL URLWithString:callback]) isEqual:Ticket]);
    assert([TKWoWLoginTicketFromURL([NSURL URLWithString:[callback stringByAppendingString:@"&accountId=123456789&flowTrackingId=&flow_type=hard_account_login"]]) isEqual:Ticket]);
    for (NSString *prefix in @[@"https://localhost:0/?ST=",@"http://localhost/?ST=",@"http://localhost:80/?ST=",
        @"http://localhost:0/path?ST=",@"http://localhost.evil.test:0/?ST=",@"http://user@localhost:0/?ST=",
        @"http://127.0.0.1:0/?ST=",@"https://eu.battle.net/?ST="])
        assert(!TKWoWLoginTicketFromURL([NSURL URLWithString:[prefix stringByAppendingString:Ticket]]));
    for (NSString *suffix in @[@"&ST=",@"&ST=other",@"#fragment",@"%0A",@"%00"])
        assert(!TKWoWLoginTicketFromURL([NSURL URLWithString:[callback stringByAppendingString:suffix]]));
    for (NSString *value in @[@"",@"US-short-1",@"XX-0123456789abcdef0123456789abcdef-1",
        @"US-0123456789abcdef0123456789abcdef-1x",@"US-0123456789abcdef0123456789abcdeg-1"])
        assert(!TKWoWEncryptLoginTicket(value,@"testuser",NULL));
    // Independently computed PBKDF2-HMAC-SHA1 / AES-CBC reference from Waypoint.
    NSData *cipher=TKWoWEncryptLoginTicket(Ticket,@"testuser",NULL);
    assert([Hex(cipher) isEqual:@"eaf1d64a585191b2d1544912b0041d0d34b9f4506cc2337d83bf0acb22397d6a4164b9bce5b47562d2de8c1b5c638d92"]);
    assert(![cipher isEqual:TKWoWEncryptLoginTicket(Ticket,@"otheruser",NULL)]);
    assert([TKWoWEncryptLoginTicket(Ticket,@"1234567890123456ignored",NULL) isEqual:TKWoWEncryptLoginTicket(Ticket,@"1234567890123456",NULL)]);
    assert(!TKWoWEncryptLoginTicket(Ticket,@"",NULL));

    NSString *domain=[@"org.wolkara.tests.auth." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *web=@"Launch Options/WoW/WEB_TOKEN";
    NSDate *date=[NSDate dateWithTimeIntervalSince1970:1700000000];
    @try {
        Put(domain,@"Unrelated",@"keep"); Put(domain,@"Launch Options/WoW/GAME_ACCOUNT",@"old-license");
        Put(domain,@"Launch Options/WoW/CONNECTION_STRING",@"old-server");
        TKWoWLoginHandoff *h=Handoff(date); assert(h);
        assert(![h.description containsString:Ticket]);
        NSArray *args=[h consumeForAppID:@"synthetic-app" arguments:@[@"-console",@"-launcherlogin",@"-uid",@"old",@"-uid=other"]
            preferencesDomain:domain now:date error:NULL];
        assert(([args isEqual:@[@"-console",@"-launcherlogin",@"-uid",@"wowf"]]));
        assert([Get(domain,web) isEqual:cipher]);
        assert([Get(domain,@"Launch Options/WoW/REGION") isEqual:@"EU"]);
        assert([Get(domain,@"Launch Options/WoW/LOCALE") isEqual:@"enUS"]);
        assert([Get(domain,@"Launch Options/WoW/ACCOUNT_TS") isEqual:@"1700000000"]);
        assert(!Get(domain,@"Launch Options/WoW/GAME_ACCOUNT"));
        assert(!Get(domain,@"Launch Options/WoW/CONNECTION_STRING"));
        assert(![h consumeForAppID:@"synthetic-app" arguments:@[] preferencesDomain:domain now:date error:NULL]);
        TKWoWClearLoginHandoff(domain); assert(!Get(domain,web)); assert([Get(domain,@"Unrelated") isEqual:@"keep"]);
        for (NSNumber *age in @[@(-1),@601]) {
            NSError *error=nil;
            assert(![Handoff(date) consumeForAppID:@"synthetic-app" arguments:@[] preferencesDomain:domain now:[date dateByAddingTimeInterval:age.doubleValue] error:&error]);
            assert(error && ![error.description containsString:Ticket]); assert(!Get(domain,web));
        }
        h=Handoff(date);
        assert(![h consumeForAppID:@"other-app" arguments:@[] preferencesDomain:domain now:date error:NULL]);
        assert(![h consumeForAppID:@"synthetic-app" arguments:@[] preferencesDomain:domain now:date error:NULL]);
        h=Handoff(date); [h invalidate];
        assert(![h consumeForAppID:@"synthetic-app" arguments:@[] preferencesDomain:domain now:date error:NULL]);
        assert(!Get(domain,web));
        assert(![[TKWoWLoginHandoff alloc] initWithTicket:Ticket userName:@"testuser" product:@"wowf --invalid"
            region:@"eu" locale:@"enUS" appID:@"synthetic-app" createdAt:date error:NULL]);
    } @finally {
        TKWoWClearLoginHandoff(domain); Put(domain,@"Unrelated",nil);
        CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:domain];
    }
    puts("Battle.net login PASS: URL boundaries, synthetic cipher vector, scoped preferences, one-shot handoff, expiration and cleanup.");
} return 0; }
