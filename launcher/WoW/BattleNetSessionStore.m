#import "BattleNetSessionStore.h"
#import "BattleNetLogin.h"
#import <Security/Security.h>

@implementation TKWoWBattleNetSessionStore {
    NSString *_service;
}
- (instancetype)init {
    return [self initWithService:[(NSBundle.mainBundle.bundleIdentifier ?: @"local.wolkara")
        stringByAppendingString:@".battle-net.session"]];
}
- (instancetype)initWithService:(NSString *)service {
    if ((self=[super init])) _service=[service copy];
    return self;
}
- (NSString *)description { return @"<TKWoWBattleNetSessionStore: private>"; }
- (NSDictionary *)queryForRegion:(NSString *)region {
    if (!TKWoWLoginURL(region)) return nil;
    NSMutableDictionary *query=[@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:_service, (__bridge id)kSecAttrAccount:region,
        (__bridge id)kSecAttrSynchronizable:@NO, (__bridge id)kSecUseDataProtectionKeychain:@YES} mutableCopy];
    // The integrated target also shares a pairing group with its tunnel. Never
    // put game tickets there. Other targets use their default app-only group.
    NSString *group=[NSBundle.mainBundle objectForInfoDictionaryKey:@"TKBattleNetKeychainAccessGroup"];
    if (group) {
        if (![group isKindOfClass:NSString.class] || !group.length || [group containsString:@"$("]) return nil;
        query[(__bridge id)kSecAttrAccessGroup]=group;
    }
    return query;
}
- (BOOL)result:(OSStatus)status error:(NSError **)error {
    if (status==errSecSuccess) return YES;
    if (error) *error=[NSError errorWithDomain:@"Wolkara.BattleNetSession" code:status
        userInfo:@{NSLocalizedDescriptionKey:@"Could not access the saved Battle.net login. Unlock your device and try again, or choose Battle.net account to forget it."}];
    return NO;
}
- (NSString *)ticketForRegion:(NSString *)region error:(NSError **)error {
    NSMutableDictionary *query=[[self queryForRegion:region] mutableCopy];
    if (!query) { [self result:errSecParam error:error]; return nil; }
    query[(__bridge id)kSecReturnData]=@YES;
    query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
    CFTypeRef item=NULL;
    OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&item);
    if (status==errSecItemNotFound) return nil;
    if (![self result:status error:error]) return nil;
    NSData *data=CFBridgingRelease(item);
    NSString *ticket=data.length<=128?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:nil;
    if (!TKWoWLoginTicketIsValid(ticket)) { [self result:errSecDecode error:error]; return nil; }
    return ticket;
}
- (BOOL)saveTicket:(NSString *)ticket region:(NSString *)region error:(NSError **)error {
    NSDictionary *query=[self queryForRegion:region];
    if (!query || !TKWoWLoginTicketIsValid(ticket)) return [self result:errSecParam error:error];
    NSDictionary *values=@{(__bridge id)kSecValueData:[ticket dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
    NSMutableDictionary *item=[query mutableCopy]; [item addEntriesFromDictionary:values];
    OSStatus status=SecItemAdd((__bridge CFDictionaryRef)item,NULL);
    if (status==errSecDuplicateItem) status=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)values);
    return [self result:status error:error];
}
- (BOOL)forgetRegion:(NSString *)region error:(NSError **)error {
    NSDictionary *query=[self queryForRegion:region];
    if (!query) return [self result:errSecParam error:error];
    OSStatus status=SecItemDelete((__bridge CFDictionaryRef)query);
    return status==errSecItemNotFound || [self result:status error:error];
}
@end
