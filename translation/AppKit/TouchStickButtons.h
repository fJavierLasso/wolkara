#import <GameController/GameController.h>

// Adds missing clickable sticks only to virtual controllers owned by this UI.
// Backing buttons come from Apple's public, writable snapshot API.
void AKRegisterTouchStickButtons(GCVirtualController *controller);
void AKUnregisterTouchStickButtons(GCVirtualController *controller);
BOOL AKSetTouchStickButton(GCController *controller, BOOL left, BOOL pressed);
