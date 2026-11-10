// Owned synthetic queues and a tiny native Metal texture; no imported client.
#import "../translation/Metal/BackgroundExecution.m"
#import "../translation/Metal/BackgroundPacing.m"
#include <assert.h>
#include <string.h>
extern void AKInstallMetalPresentationDiagnostics(id<MTLDevice> device);
extern void AKEnableMetalFrameStatistics(void);
void AKInstallRenderDiagnostics(Class cls) { (void)cls; }
NSArray *AKRenderStatsForCommand(id command) { (void)command; return @[]; }

@interface AKTestCommand : NSObject
@property(atomic) MTLCommandBufferStatus status;
@property(atomic) unsigned commits;
@property(atomic) unsigned completions;
@property(atomic) BOOL schedule;
@property(nonatomic) NSUInteger payload;
@property(nonatomic,strong) NSError *error;
@property(nonatomic,strong) NSMutableArray *handlers;
- (void)commit;
- (void)addCompletedHandler:(MTLCommandBufferHandler)handler;
- (void)finish;
@end
@implementation AKTestCommand
- (instancetype)init { if ((self=[super init])) { _handlers=[NSMutableArray new]; _schedule=YES; } return self; }
- (void)commit { self.commits++; self.status=self.schedule?MTLCommandBufferStatusScheduled:MTLCommandBufferStatusCommitted; }
- (void)addCompletedHandler:(MTLCommandBufferHandler)handler { [self.handlers addObject:[handler copy]]; }
- (void)finish {
    self.status=self.error?MTLCommandBufferStatusError:MTLCommandBufferStatusCompleted;
    for (MTLCommandBufferHandler handler in self.handlers) handler((id)self);
    [self.handlers removeAllObjects]; self.completions++;
}
@end
// An overriding wrapper forwarding through an independently hooked superclass.
@interface AKTestUnretainedCommand : AKTestCommand @end
@implementation AKTestUnretainedCommand
- (void)commit { [super commit]; }
@end
@interface AKTestDescriptorCommand : AKTestCommand @end
@implementation AKTestDescriptorCommand @end
@interface AKTestQueue : NSObject
- (id<MTLCommandBuffer>)commandBuffer;
- (id<MTLCommandBuffer>)commandBufferWithUnretainedReferences;
- (id<MTLCommandBuffer>)commandBufferWithDescriptor:(MTLCommandBufferDescriptor *)descriptor;
@end
@implementation AKTestQueue
- (id<MTLCommandBuffer>)commandBuffer { return (id)[AKTestCommand new]; }
- (id<MTLCommandBuffer>)commandBufferWithUnretainedReferences { return (id)[AKTestUnretainedCommand new]; }
- (id<MTLCommandBuffer>)commandBufferWithDescriptor:(MTLCommandBufferDescriptor *)descriptor { assert(descriptor); return (id)[AKTestDescriptorCommand new]; }
@end
@interface AKTestLimitedQueue : AKTestQueue @end
@implementation AKTestLimitedQueue @end
@interface AKTestDescriptorQueue : AKTestQueue @end
@implementation AKTestDescriptorQueue @end
@interface AKTestDevice : NSObject
- (id<MTLCommandQueue>)newCommandQueue;
- (id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)count;
- (id<MTLCommandQueue>)newCommandQueueWithDescriptor:(MTLCommandQueueDescriptor *)descriptor API_AVAILABLE(ios(18.0));
@end
@implementation AKTestDevice
- (id<MTLCommandQueue>)newCommandQueue { return (id)[AKTestQueue new]; }
- (id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)count { assert(count); return (id)[AKTestLimitedQueue new]; }
- (id<MTLCommandQueue>)newCommandQueueWithDescriptor:(MTLCommandQueueDescriptor *)descriptor { assert(descriptor); return (id)[AKTestDescriptorQueue new]; }
@end
static void active(BOOL value) {
    [NSNotificationCenter.defaultCenter postNotificationName:value?UIApplicationDidBecomeActiveNotification:UIApplicationWillResignActiveNotification object:nil];
}
static void waitDone(dispatch_semaphore_t done) { assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0); }
static atomic_uint drawableCalls;
static id<CAMetalDrawable> fakeDrawable(id receiver,SEL selector) { (void)receiver; (void)selector; atomic_fetch_add(&drawableCalls,1); return nil; }
static void testDrawableAndMainThread(void) {
    originalNextDrawable=fakeDrawable;
    active(NO);
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ pacedNextDrawable(nil,NULL); dispatch_semaphore_signal(done); });
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,40*NSEC_PER_MSEC))!=0);
    assert(atomic_load(&drawableCalls)==0);
    active(YES); waitDone(done); assert(atomic_load(&drawableCalls)==1);
    active(NO);
    [NSTimer scheduledTimerWithTimeInterval:.02 repeats:NO block:^(__unused NSTimer *timer) { active(YES); }];
    double started=NSProcessInfo.processInfo.systemUptime;
    pacedNextDrawable(nil,NULL);
    assert(NSProcessInfo.processInfo.systemUptime-started<.5);
    assert(atomic_load(&drawableCalls)==2);
    pacedNextDrawable(nil,NULL); assert(atomic_load(&drawableCalls)==3);
}
static void testCommands(void) {
    AKTestDevice *device=[AKTestDevice new];
    AKInstallMetalBackgroundSubmission((id)device);
    AKInstallMetalBackgroundSubmission((id)device); // idempotent
    NSMutableArray *queues=[NSMutableArray arrayWithObjects:[device newCommandQueue],[device newCommandQueueWithMaxCommandBufferCount:2],nil];
    if (@available(iOS 18.0,*)) [queues addObject:[device newCommandQueueWithDescriptor:[MTLCommandQueueDescriptor new]]];
    for (id<MTLCommandQueue> queue in queues) {
        for (unsigned variant=0;variant<3;variant++) { @autoreleasepool {
            AKTestCommand *command=(id)(variant==0?[queue commandBuffer]:variant==1?[queue commandBufferWithUnretainedReferences]:[queue commandBufferWithDescriptor:[MTLCommandBufferDescriptor new]]);
            command.payload=0x12345678;
            __block BOOL completed=NO;
            [command addCompletedHandler:^(id<MTLCommandBuffer> buffer) { assert(buffer.status==MTLCommandBufferStatusCompleted); completed=YES; }];
            active(NO);
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
            dispatch_semaphore_t done=dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ @autoreleasepool {
                [command commit]; dispatch_semaphore_signal(done);
            } });
            assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC))!=0);
            assert(command.commits==0 && command.status==MTLCommandBufferStatusNotEnqueued && !completed);
            active(YES); waitDone(done);
            assert(command.commits==1 && command.payload==0x12345678 && !completed);
            // Exactly one original completion plus our observer, even through
            // forwarding/inherited wrappers. Nothing completes before native work.
            assert(command.handlers.count==2);
            [command finish]; assert(completed && command.completions==1);
        } }
    }
    AKTestCommand *main=(id)[queues[0] commandBuffer];
    active(NO);
    [NSTimer scheduledTimerWithTimeInterval:.02 repeats:NO block:^(__unused NSTimer *timer) { active(YES); }];
    [main commit]; assert(main.commits==1); [main finish];

    // Lifecycle drain waits for scheduling, not completion, on other queues.
    AKTestCommand *slow=(id)[queues[0] commandBuffer]; slow.schedule=NO; [slow commit];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ slow.status=MTLCommandBufferStatusScheduled; });
    active(NO); assert(slow.status==MTLCommandBufferStatusScheduled && slow.completions==0);
    [slow finish]; active(YES);
    // A queue hole cannot hang UIKit's background transition indefinitely.
    AKTestCommand *hole=(id)[queues[0] commandBuffer]; hole.schedule=NO; [hole commit];
    double start=NSProcessInfo.processInfo.systemUptime;
    active(NO); assert(NSProcessInfo.processInfo.systemUptime-start<.5);
    [hole finish]; active(YES);
    __weak AKTestCommand *weak;
    @autoreleasepool { AKTestCommand *temp=(id)[queues[0] commandBuffer]; weak=temp; [temp commit]; [temp finish]; }
    assert(!weak); // tracking does not keep buffers/resources alive
    AKTestCommand *failed=(id)[queues[0] commandBuffer];
    failed.error=[NSError errorWithDomain:MTLCommandBufferErrorDomain code:MTLCommandBufferErrorNotPermitted userInfo:nil];
    [failed commit]; [failed finish]; assert(atomic_load(&gpuFailures)==1);
}
static void testNativeTexture(void) {
    id<MTLDevice> device=MTLCreateSystemDefaultDevice(); assert(device);
    BOOL hudFirst=[NSProcessInfo.processInfo.arguments containsObject:@"--hud-first"];
    if (hudFirst) { AKInstallMetalPresentationDiagnostics(device); AKEnableMetalFrameStatistics(); }
    AKInstallMetalBackgroundSubmission(device);
    id<MTLCommandQueue> queue=[device newCommandQueue]; assert(queue);
    id<MTLBuffer> source=[device newBufferWithLength:512 options:MTLResourceStorageModeShared];
    id<MTLBuffer> result=[device newBufferWithLength:512 options:MTLResourceStorageModeShared];
    MTLTextureDescriptor *descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:2 mipmapped:NO];
    descriptor.storageMode=MTLStorageModePrivate;
    id<MTLTexture> texture=[device newTextureWithDescriptor:descriptor]; assert(source && result && texture);
    for (unsigned pass=0;pass<6;pass++) { @autoreleasepool {
        if (!hudFirst && pass==2) { AKInstallMetalPresentationDiagnostics(device); AKEnableMetalFrameStatistics(); }
        memset(source.contents,0x31+pass,512); memset(result.contents,0,512);
        id<MTLCommandBuffer> upload=pass%3==0?[queue commandBuffer]:pass%3==1?[queue commandBufferWithUnretainedReferences]:[queue commandBufferWithDescriptor:[MTLCommandBufferDescriptor new]];
        id<MTLBlitCommandEncoder> blit=[upload blitCommandEncoder];
        [blit copyFromBuffer:source sourceOffset:0 sourceBytesPerRow:256 sourceBytesPerImage:512 sourceSize:MTLSizeMake(2,2,1) toTexture:texture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
        [blit endEncoding];
        active(NO);
        dispatch_semaphore_t done=dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ @autoreleasepool { [upload commit]; dispatch_semaphore_signal(done); } });
        assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC))!=0);
        assert(upload.status==MTLCommandBufferStatusNotEnqueued);
        active(YES); waitDone(done); [upload waitUntilCompleted]; assert(upload.status==MTLCommandBufferStatusCompleted);
        id<MTLCommandBuffer> readback=[queue commandBuffer];
        blit=[readback blitCommandEncoder];
        [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(2,2,1) toBuffer:result destinationOffset:0 destinationBytesPerRow:256 destinationBytesPerImage:512];
        [blit endEncoding]; [readback commit]; [readback waitUntilCompleted];
        assert(readback.status==MTLCommandBufferStatusCompleted);
        assert(memcmp(source.contents,result.contents,8)==0 && memcmp((char *)source.contents+256,(char *)result.contents+256,8)==0);
    } }
}
int main(void) { @autoreleasepool {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ fputs("BACKGROUND_GPU_TIMEOUT\n",stderr); _Exit(1); });
    active(YES);
    testDrawableAndMainThread(); testCommands(); testNativeTexture();
    puts("BACKGROUND_GPU_PASS: main/worker resume, queue variants, bounded drain, lifetimes and six native texture upload/readbacks");
} return 0; }
