#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Public web-login / macOS launch-options format; see NOTICE.md.
FOUNDATION_EXPORT NSString *const TKWoWBrowserLoginEnabledKey;
NSURL * _Nullable TKWoWLoginURL(NSString *region);
BOOL TKWoWLoginPageIsTrusted(NSURL * _Nullable url);
BOOL TKWoWLoginTicketIsValid(NSString * _Nullable ticket);
BOOL TKWoWLoginCallbackURL(NSURL * _Nullable url);
NSString * _Nullable TKWoWLoginTicketFromURL(NSURL * _Nullable url);
NSData * _Nullable TKWoWEncryptLoginTicket(NSString *ticket, NSString *userName, NSError **error);

// A launch retains only an encrypted, short-lived handoff. Remembered tickets
// live separately in the device-only Keychain, never in arguments or logs.
@interface TKWoWLoginHandoff : NSObject
- (nullable instancetype)initWithTicket:(NSString *)ticket userName:(NSString *)userName
    product:(NSString *)product region:(NSString *)region locale:(NSString *)locale
    appID:(NSString *)appID createdAt:(NSDate *)date error:(NSError **)error;
- (nullable NSArray<NSString *> *)consumeForAppID:(NSString *)appID
    arguments:(NSArray<NSString *> *)arguments preferencesDomain:(NSString *)domain
    now:(NSDate *)date error:(NSError **)error;
- (void)invalidate;
@end
// Call only for Wolkara's own sandbox. Tests use a unique throwaway domain.
void TKWoWClearLoginHandoff(NSString *domain);
NS_ASSUME_NONNULL_END
