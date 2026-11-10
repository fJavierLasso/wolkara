// Original loader fixture; no third-party shaders or application code.
#import "../translation/Metal/Devices.m"
#include <assert.h>
extern void AKFixtureAutoreleaseTemporary(void);
extern unsigned AKFixtureLiveTemporaries(void);
void AKInstallMetalBackgroundSubmission(id<MTLDevice> device) { (void)device; }
void AKInstallMetalPresentationDiagnostics(id<MTLDevice> device) { (void)device; }
void AKInstallManagedStorage(Class device) { (void)device; }
static BOOL failLoad;
static id<MTLLibrary> fixtureLoad(id device,SEL selector,dispatch_data_t data,NSError *__autoreleasing *error) __attribute__((ns_returns_retained));
static id<MTLLibrary> fixtureLoad(id device,SEL selector,dispatch_data_t data,NSError *__autoreleasing *error) {
    (void)device; (void)selector; (void)data;
    AKFixtureAutoreleaseTemporary();
    if (failLoad) { if (error) *error=[NSError errorWithDomain:@"Fixture" code:7 userInfo:nil]; return nil; }
    if (error) *error=nil;
    return (id)[NSObject new];
}
int main(void) { @autoreleasepool {
    originalLibraryLoader=fixtureLoad;
    NSObject *device=[NSObject new];
    // Zero-sized input takes the transparent native fallback, exercising the
    // same pool boundary without creating any files or translating a shader.
    for (unsigned i=0;i<1000;i++) {
        NSError *error=nil;
        id library=captureLibrary(device,@selector(newLibraryWithData:error:),dispatch_data_empty,&error);
        assert(library && !error);
        assert(AKFixtureLiveTemporaries()==0);
    }
    failLoad=YES;
    NSError *error=nil;
    assert(!captureLibrary(device,@selector(newLibraryWithData:error:),dispatch_data_empty,&error));
    assert([error.domain isEqual:@"Fixture"] && error.code==7);
    assert(AKFixtureLiveTemporaries()==0);
    __weak NSObject *cached;
    @autoreleasepool {
        NSObject *library=[NSObject new]; cached=library;
        [libraryCache((id)device) setObject:(id)library forKey:@"fixture"];
    }
    assert(cached);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    assert(!cached);
    puts("Metal library temporaries and retained result/error lifetime: PASS");
} }
