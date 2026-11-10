#import "BackgroundExecution.h"
#import "AKSupport.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#import <stdatomic.h>

static NSCondition *gpuLifecycle;
static NSHashTable<id<MTLCommandBuffer>> *gpuInFlight;
static BOOL gpuPaused;
static atomic_uint gpuFailures;
static _Thread_local unsigned gpuCommitDepth;
static char deviceHooked, queueHooked, commandHooked;

// Called with the condition locked. A desktop renderer can run on the UIKit
// thread; it must keep delivering activation notifications while parked.
static void AKWaitForGPUUnlocked(void) {
    while (gpuPaused) {
        if (NSThread.isMainThread) {
            [gpuLifecycle unlock];
            SInt32 result=CFRunLoopRunInMode(kCFRunLoopDefaultMode,.02,true);
            if (result==kCFRunLoopRunFinished) [NSThread sleepForTimeInterval:.005];
            [gpuLifecycle lock];
        } else [gpuLifecycle wait];
    }
}
void AKWaitForMetalForeground(void) {
    [gpuLifecycle lock];
    AKWaitForGPUUnlocked();
    [gpuLifecycle unlock];
}
static void AKSetGPUPaused(BOOL paused) {
    [gpuLifecycle lock];
    BOOL changed=gpuPaused!=paused;
    gpuPaused=paused;
    NSArray<id<MTLCommandBuffer>> *pending=paused?gpuInFlight.allObjects:nil;
    if (!paused) [gpuLifecycle broadcast];
    [gpuLifecycle unlock];

    // iOS requires previously committed work to be scheduled before suspension.
    // Check scheduling, never GPU completion. Unlike waitUntilScheduled, this
    // also bounds the lifecycle callback when a desktop queue contains an
    // explicitly enqueued buffer that its owner has not committed yet.
    double deadline=NSProcessInfo.processInfo.systemUptime+.15;
    for (;;) {
        BOOL unscheduled=NO;
        for (id<MTLCommandBuffer> command in pending)
            if (command.status==MTLCommandBufferStatusCommitted) { unscheduled=YES; break; }
        if (!unscheduled) break;
        if (NSProcessInfo.processInfo.systemUptime>=deadline) {
            AKLog(@"Metal background: scheduling drain timed out; new submissions remain paused");
            break;
        }
        [NSThread sleepForTimeInterval:.001];
    }
    if (changed) AKLog(@"Metal background: %@",paused?@"GPU submissions paused":@"GPU submissions resumed");
}
void AKInstallMetalBackgroundLifecycle(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        gpuLifecycle=[NSCondition new];
        // Do not retain completed buffers, their queues, or their textures.
        gpuInFlight=[NSHashTable weakObjectsHashTable];
        gpuPaused=UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;
        NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { AKSetGPUPaused(YES); }];
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { AKSetGPUPaused(YES); }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { AKSetGPUPaused(NO); }];
    });
}
static void AKSubmitMetalCommand(id<MTLCommandBuffer> command, SEL selector, IMP original) { @autoreleasepool {
    // Metal debug/capture layers can forward through another hooked class.
    if (gpuCommitDepth) { ((void (*)(id,SEL))original)(command,selector); return; }
    [gpuLifecycle lock];
    @try {
        AKWaitForGPUUnlocked();
        ++gpuCommitDepth;
        [command addCompletedHandler:^(id<MTLCommandBuffer> completed) { @autoreleasepool {
            if (completed.status==MTLCommandBufferStatusError && atomic_fetch_add(&gpuFailures,1)<8)
                AKLog(@"Metal command failed: domain=%@ code=%ld",completed.error.domain,(long)completed.error.code);
        } }];
        // Serialize the native submission with deactivation. Do not return a
        // fake success or enqueue a replay: the original buffer and its resource
        // lifetimes stay with its caller until it can really be committed.
        ((void (*)(id,SEL))original)(command,selector);
        for (id<MTLCommandBuffer> previous in gpuInFlight.allObjects)
            if (previous.status>=MTLCommandBufferStatusScheduled) [gpuInFlight removeObject:previous];
        [gpuInFlight addObject:command];
    } @finally {
        if (gpuCommitDepth) --gpuCommitDepth;
        [gpuLifecycle unlock];
    }
} }
static void AKObserveCommand(id<MTLCommandBuffer> command) {
    if (!command) return;
    @synchronized(CAMetalLayer.class) {
        Class cls=object_getClass(command);
        if (objc_getAssociatedObject(cls,&commandHooked)) return;
        SEL selector=@selector(commit);
        Method method=class_getInstanceMethod(cls,selector);
        if (!method) return;
        IMP original=method_getImplementation(method);
        IMP replacement=imp_implementationWithBlock(^(id receiver) { AKSubmitMetalCommand(receiver,selector,original); });
        class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
        objc_setAssociatedObject(cls,&commandHooked,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static void AKObserveQueue(id<MTLCommandQueue> queue) {
    if (!queue) return;
    @synchronized(CAMetalLayer.class) {
        Class cls=object_getClass(queue);
        if (objc_getAssociatedObject(cls,&queueHooked)) return;
        for (NSString *name in @[@"commandBuffer",@"commandBufferWithUnretainedReferences",@"commandBufferWithDescriptor:"]) {
            SEL selector=NSSelectorFromString(name);
            Method method=class_getInstanceMethod(cls,selector);
            if (!method) continue;
            IMP original=method_getImplementation(method), replacement;
            if ([name hasSuffix:@":"]) {
                replacement=imp_implementationWithBlock(^id(id receiver,id descriptor) {
                    id command=((id (*)(id,SEL,id))original)(receiver,selector,descriptor);
                    AKObserveCommand(command); return command;
                });
            } else {
                replacement=imp_implementationWithBlock(^id(id receiver) {
                    id command=((id (*)(id,SEL))original)(receiver,selector);
                    AKObserveCommand(command); return command;
                });
            }
            class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
        }
        objc_setAssociatedObject(cls,&queueHooked,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
void AKInstallMetalBackgroundSubmission(id<MTLDevice> device) {
    if (!device) return;
    AKInstallMetalBackgroundLifecycle();
    @synchronized(CAMetalLayer.class) {
        Class cls=object_getClass(device);
        if (objc_getAssociatedObject(cls,&deviceHooked)) return;
        // Discover the platform's concrete queue classes through each factory.
        // Class hooks then cover new queues too, including upload-only queues.
        @autoreleasepool {
            AKObserveQueue([device newCommandQueue]);
            AKObserveQueue([device newCommandQueueWithMaxCommandBufferCount:1]);
            if (@available(iOS 18.0,*)) AKObserveQueue([device newCommandQueueWithDescriptor:[MTLCommandQueueDescriptor new]]);
        }
        objc_setAssociatedObject(cls,&deviceHooked,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
