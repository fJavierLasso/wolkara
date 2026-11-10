#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#import "BackgroundExecution.h"
#import "AKSupport.h"

static id<CAMetalDrawable> (*originalNextDrawable)(id,SEL);
static id<CAMetalDrawable> pacedNextDrawable(id layer,SEL selector) {
    AKWaitForMetalForeground();
    return originalNextDrawable(layer,selector);
}
void AKInstallMetalBackgroundPacing(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        AKInstallMetalBackgroundLifecycle();
        Method method=class_getInstanceMethod(CAMetalLayer.class,@selector(nextDrawable));
        if (!method) { AKLog(@"background drawable pause could not install"); return; }
        originalNextDrawable=(void *)method_getImplementation(method);
        class_replaceMethod(CAMetalLayer.class,@selector(nextDrawable),(IMP)pacedNextDrawable,method_getTypeEncoding(method));
    });
}
// The adapter loads before any guest drawing. Submission hooks are installed
// when the guest obtains its Metal device; neither path caps foreground FPS.
__attribute__((constructor)) static void AKBackgroundPacingLoad(void) {
    AKInstallMetalBackgroundPacing();
}
