#import <Foundation/Foundation.h>

// Retires abandoned WolkaraTouch and installer-owned WolkaraMobile experiments,
// outside WoW's AddOns folder, including interrupted mobile installs.
// Preserves its files, saved variables, other addons and all game data.
BOOL TKWoWRetireTouchAddon(NSString *editionDirectory, NSError **error);

// One-time removal of the retired Touchbars experiment. Call after UI restore
// recovery and outside the update lock: the addon store locks its own writes.
// SavedVariables and the removed package's recoverable copy are preserved.
BOOL TKWoWRetireManagedTouchbars(NSString *editionDirectory, NSString *product,
                               NSString *version, NSError **error);
