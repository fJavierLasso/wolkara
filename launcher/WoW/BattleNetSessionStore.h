#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// One user-authorized game ticket per region, in this app's device-only Keychain.
// Missing credentials return nil without error. No passwords or account metadata.
@interface TKWoWBattleNetSessionStore : NSObject
- (instancetype)initWithService:(NSString *)service;
- (nullable NSString *)ticketForRegion:(NSString *)region error:(NSError **)error;
- (BOOL)saveTicket:(NSString *)ticket region:(NSString *)region error:(NSError **)error;
- (BOOL)forgetRegion:(NSString *)region error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
