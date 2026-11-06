#import "TouchStickButtons.h"
#import <objc/runtime.h>

static NSHashTable<GCVirtualController *> *owned;
static char bridgeKey, profileKey;
static GCExtendedGamepad *(*nativeExtended)(id,SEL);
static GCPhysicalInputProfile *(*nativePhysical)(id,SEL);
static GCController *(*nativeCapture)(id,SEL);

@interface AKTouchStickButtons : NSObject
@property(nonatomic,weak) GCController *controller;
@property(nonatomic,strong) GCController *snapshot;
@property BOOL leftMissing, rightMissing;
@property(atomic) NSTimeInterval lastClickAt;
- (GCController *)capture;
@end

static BOOL OwnsController(GCController *controller) {
    if (!controller || controller.isSnapshot) return NO;
    @synchronized(GCController.class) {
        for (GCVirtualController *virtual in owned)
            if (virtual.controller == controller) return YES;
    }
    return NO;
}
static id BaseValue(id profile, SEL selector) {
    Class base = class_getSuperclass(object_getClass(profile));
    return ((id (*)(id,SEL))class_getMethodImplementation(base,selector))(profile,selector);
}
static GCControllerButtonInput *ExtraButton(id profile, BOOL left) {
    AKTouchStickButtons *bridge = objc_getAssociatedObject(profile,&profileKey);
    if (!bridge || !(left ? bridge.leftMissing : bridge.rightMissing)) return nil;
    return left ? bridge.snapshot.extendedGamepad.leftThumbstickButton : bridge.snapshot.extendedGamepad.rightThumbstickButton;
}
static id LeftButton(id profile, SEL selector) { return ExtraButton(profile,YES) ?: BaseValue(profile,selector); }
static id RightButton(id profile, SEL selector) { return ExtraButton(profile,NO) ?: BaseValue(profile,selector); }
static id Elements(id profile, SEL selector) {
    NSMutableDictionary *values = [BaseValue(profile,selector) mutableCopy] ?: [NSMutableDictionary new];
    if (ExtraButton(profile,YES)) values[GCInputLeftThumbstickButton] = ExtraButton(profile,YES);
    if (ExtraButton(profile,NO)) values[GCInputRightThumbstickButton] = ExtraButton(profile,NO);
    return values.copy;
}
static id AllElements(id profile, SEL selector) {
    NSMutableSet *values = [BaseValue(profile,selector) mutableCopy] ?: [NSMutableSet new];
    if (ExtraButton(profile,YES)) [values addObject:ExtraButton(profile,YES)];
    if (ExtraButton(profile,NO)) [values addObject:ExtraButton(profile,NO)];
    return values.copy;
}
static id Lookup(id profile, SEL selector, NSString *key) {
    if ([key isEqual:GCInputLeftThumbstickButton] && ExtraButton(profile,YES)) return ExtraButton(profile,YES);
    if ([key isEqual:GCInputRightThumbstickButton] && ExtraButton(profile,NO)) return ExtraButton(profile,NO);
    Class base = class_getSuperclass(object_getClass(profile));
    return ((id (*)(id,SEL,id))class_getMethodImplementation(base,selector))(profile,selector,key);
}
static NSTimeInterval LastEvent(id profile, SEL selector) {
    Class base = class_getSuperclass(object_getClass(profile));
    NSTimeInterval native = ((NSTimeInterval (*)(id,SEL))class_getMethodImplementation(base,selector))(profile,selector);
    AKTouchStickButtons *bridge = objc_getAssociatedObject(profile,&profileKey);
    return MAX(native,bridge.lastClickAt);
}
static id CaptureProfile(id profile, SEL selector) {
    (void)selector;
    AKTouchStickButtons *bridge = objc_getAssociatedObject(profile,&profileKey);
    return [bridge capture].extendedGamepad;
}
static void ExtendProfile(GCPhysicalInputProfile *profile, AKTouchStickButtons *bridge) {
    if (!profile || objc_getAssociatedObject(profile,&profileKey)) return;
    @synchronized(GCController.class) {
        if (objc_getAssociatedObject(profile,&profileKey)) return;
        Class base = object_getClass(profile);
        NSString *name = [@"AKClickable_" stringByAppendingString:NSStringFromClass(base)];
        Class extended = NSClassFromString(name);
        if (!extended) {
            extended = objc_allocateClassPair(base,name.UTF8String,0);
            class_addMethod(extended,@selector(leftThumbstickButton),(IMP)LeftButton,"@@:");
            class_addMethod(extended,@selector(rightThumbstickButton),(IMP)RightButton,"@@:");
            for (NSString *selector in @[@"elements",@"buttons"])
                class_addMethod(extended,NSSelectorFromString(selector),(IMP)Elements,"@@:");
            for (NSString *selector in @[@"allElements",@"allButtons"])
                class_addMethod(extended,NSSelectorFromString(selector),(IMP)AllElements,"@@:");
            class_addMethod(extended,@selector(objectForKeyedSubscript:),(IMP)Lookup,"@@:@");
            class_addMethod(extended,@selector(capture),(IMP)CaptureProfile,"@@:");
            class_addMethod(extended,@selector(lastEventTimestamp),(IMP)LastEvent,"d@:");
            objc_registerClassPair(extended);
        }
        objc_setAssociatedObject(profile,&profileKey,bridge,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        object_setClass(profile,extended);
    }
}
static AKTouchStickButtons *Bridge(GCController *controller) {
    if (!OwnsController(controller)) return nil;
    @synchronized(GCController.class) {
        AKTouchStickButtons *bridge = objc_getAssociatedObject(controller,&bridgeKey);
        if (bridge) return bridge;
        GCExtendedGamepad *profile = nativeExtended(controller,@selector(extendedGamepad));
        if (!profile || (profile.leftThumbstickButton && profile.rightThumbstickButton)) return nil;
        bridge = [AKTouchStickButtons new]; bridge.controller = controller;
        bridge.leftMissing = profile.leftThumbstickButton == nil;
        bridge.rightMissing = profile.rightThumbstickButton == nil;
        bridge.snapshot = [GCController controllerWithExtendedGamepad];
        if (!bridge.snapshot.extendedGamepad.leftThumbstickButton || !bridge.snapshot.extendedGamepad.rightThumbstickButton) return nil;
        objc_setAssociatedObject(controller,&bridgeKey,bridge,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return bridge;
    }
}
@implementation AKTouchStickButtons
- (GCController *)capture {
    GCController *copy = [GCController controllerWithExtendedGamepad];
    [copy.extendedGamepad setStateFromExtendedGamepad:self.controller.extendedGamepad];
    if (_leftMissing) [copy.extendedGamepad.leftThumbstickButton setValue:_snapshot.extendedGamepad.leftThumbstickButton.value];
    if (_rightMissing) [copy.extendedGamepad.rightThumbstickButton setValue:_snapshot.extendedGamepad.rightThumbstickButton.value];
    return copy;
}
@end
static id Extended(id controller,SEL selector) {
    id profile = nativeExtended(controller,selector);
    AKTouchStickButtons *bridge = Bridge(controller); if (bridge) ExtendProfile(profile,bridge);
    return profile;
}
static id Physical(id controller,SEL selector) {
    id profile = nativePhysical(controller,selector);
    AKTouchStickButtons *bridge = Bridge(controller); if (bridge) ExtendProfile(profile,bridge);
    return profile;
}
static id Capture(id controller,SEL selector) {
    AKTouchStickButtons *bridge = Bridge(controller);
    return bridge ? [bridge capture] : nativeCapture(controller,selector);
}
void AKRegisterTouchStickButtons(GCVirtualController *controller) {
    if (!controller) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        owned = [NSHashTable weakObjectsHashTable];
        // Lazy public getters expose the buttons even to the first connection
        // observer. Only identities in our weak registry get extended profiles.
        Class cls = GCController.class;
        Method method = class_getInstanceMethod(cls,@selector(extendedGamepad));
        nativeExtended = (void *)method_getImplementation(method); method_setImplementation(method,(IMP)Extended);
        method = class_getInstanceMethod(cls,@selector(physicalInputProfile));
        nativePhysical = (void *)method_getImplementation(method); method_setImplementation(method,(IMP)Physical);
        method = class_getInstanceMethod(cls,@selector(capture));
        nativeCapture = (void *)method_getImplementation(method); method_setImplementation(method,(IMP)Capture);
    });
    @synchronized(GCController.class) { [owned addObject:controller]; }
}
void AKUnregisterTouchStickButtons(GCVirtualController *controller) {
    @synchronized(GCController.class) { [owned removeObject:controller]; }
}
BOOL AKSetTouchStickButton(GCController *controller, BOOL left, BOOL pressed) {
    AKTouchStickButtons *bridge = Bridge(controller);
    if (!bridge || !(left ? bridge.leftMissing : bridge.rightMissing)) return NO;
    GCControllerButtonInput *button = left ? bridge.snapshot.extendedGamepad.leftThumbstickButton : bridge.snapshot.extendedGamepad.rightThumbstickButton;
    if (button.isPressed == pressed) return YES;
    bridge.lastClickAt = NSProcessInfo.processInfo.systemUptime;
    [button setValue:pressed ? 1 : 0]; // Apple's button invokes its own per-button handlers.
    // Snapshot button setters do not notify their containing profile. Deliver
    // aggregate notifications on the owner's public handler queue as well.
    dispatch_async(controller.handlerQueue ?: dispatch_get_main_queue(), ^{
        if (!OwnsController(controller)) return;
        GCExtendedGamepad *extended = controller.extendedGamepad;
        if (extended.valueChangedHandler) extended.valueChangedHandler(extended,button);
        GCPhysicalInputProfile *physical = controller.physicalInputProfile;
        if (physical.valueDidChangeHandler) physical.valueDidChangeHandler(physical,button);
    });
    return YES;
}
