#pragma once
#import <Foundation/Foundation.h>

// Host sets this only after successfully preparing a browser-login handoff.
// A named volatile domain is not searched as a preference and never goes to disk.
static inline BOOL AKGameSessionUsesBattleNet(void) {
    return [[NSUserDefaults.standardUserDefaults volatileDomainForName:@"Wolkara.GameSession"][@"battleNetLogin"] boolValue];
}
static inline void AKSetGameSessionUsesBattleNet(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"battleNetLogin":@(enabled)} forName:@"Wolkara.GameSession"];
}
