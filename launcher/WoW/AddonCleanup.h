#import <Foundation/Foundation.h>

// Retires abandoned WolkaraTouch and installer-owned WolkaraMobile experiments,
// outside WoW's AddOns folder, including interrupted mobile installs.
// Preserves its files, saved variables, other addons and all game data.
BOOL TKWoWRetireTouchAddon(NSString *editionDirectory, NSError **error);
