#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Public web-login / macOS launch-options format; see NOTICE.md.
FOUNDATION_EXPORT NSString *const TKWoWBrowserLoginEnabledKey;
NSURL * _Nullable TKWoWLoginURL(NSString *region);
BOOL TKWoWLoginPageIsTrusted(NSURL * _Nullable url);
BOOL TKWoWLoginCallbackURL(NSURL * _Nullable url);
NSString * _Nullable TKWoWLoginTicketFromURL(NSURL * _Nullable url);
NSData * _Nullable TKWoWEncryptLoginTicket(NSString *ticket, NSString *userName, NSError **error);

// Only an encrypted, short-lived handoff is retained. No password, persistent
// login, account inspection or token in arguments/environment/logs.
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
