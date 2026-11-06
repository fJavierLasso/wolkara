// Only linked into the input fixture's late-loaded library. No game is loaded.
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <assert.h>

extern void AKInstallMetalPresentationDiagnostics(id<MTLDevice> device);
extern void AKRecordMetalFramePresented(double timestamp);
void AKLog(NSString *format, ...) { (void)format; }
void AKInstallRenderDiagnostics(Class cls) { (void)cls; }
NSArray *AKRenderStatsForCommand(id command) { (void)command; return @[]; }

static IMP originalDrawable;
void AKTestPrepareLateMetal(void) {
    originalDrawable = class_getMethodImplementation(CAMetalLayer.class, @selector(nextDrawable));
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    assert(device);
    AKInstallMetalPresentationDiagnostics(device);
    assert(originalDrawable == class_getMethodImplementation(CAMetalLayer.class, @selector(nextDrawable)));
}
void AKTestRecordMetalFrames(void) {
    assert(originalDrawable != class_getMethodImplementation(CAMetalLayer.class, @selector(nextDrawable)));
    // Synthetic timestamps verify the HUD's measurement path, not device FPS.
    double now = CACurrentMediaTime();
    for (NSUInteger i = 0; i < 60; i++) AKRecordMetalFramePresented(now - (59-i)/60.0);
}

extern void AKEnableMetalFrameStatistics(void);
extern void AKDisableMetalFrameStatistics(void);
extern double AKMetalCurrentFPS(void);
extern double AKMetalLastFrameTimeMs(void);
void AKTestMetricIntervals(void) {
    AKDisableMetalFrameStatistics(); AKEnableMetalFrameStatistics();
    double now = CACurrentMediaTime();
    for (NSUInteger i=0;i<60;i++) AKRecordMetalFramePresented(now-(59-i)/60.0);
    assert(fabs(AKMetalCurrentFPS()-60)<0.01 && fabs(AKMetalLastFrameTimeMs()-1000.0/60)<0.01);
    AKRecordMetalFramePresented(NAN); AKRecordMetalFramePresented(now-2); AKRecordMetalFramePresented(now);
    assert(fabs(AKMetalCurrentFPS()-60)<0.01);
    AKDisableMetalFrameStatistics(); AKEnableMetalFrameStatistics();
    assert(AKMetalCurrentFPS()==0 && AKMetalLastFrameTimeMs()==0);
    for (NSUInteger i=0;i<60;i++) AKRecordMetalFramePresented(now-2-(59-i)/60.0);
    assert(AKMetalCurrentFPS()==0); // stale frames must not masquerade as live FPS.
    AKRecordMetalFramePresented(now-1.0/30); AKRecordMetalFramePresented(now);
    assert(fabs(AKMetalCurrentFPS()-30)<0.01);
}
