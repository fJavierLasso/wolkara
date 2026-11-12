#import "TouchbarsAddon.h"
#import "UpdateLock.h"
#include <assert.h>

@interface TKFixtureTouchbars : TKTouchbarsAddon
@property(nonatomic) NSURL *archive;
@property(nonatomic) NSUInteger downloads;
@property(nonatomic) BOOL failDownload;
@end
@implementation TKFixtureTouchbars
- (BOOL)prepareArchiveAtURL:(NSURL *)url error:(NSError **)error {
    self.downloads++;
    if (self.failDownload) {
        if (error) *error=[NSError errorWithDomain:@"fixture.offline" code:1 userInfo:nil];
        return NO;
    }
    return [NSFileManager.defaultManager copyItemAtURL:self.archive toURL:url error:error];
}
@end

void TestTouchbars(const char *temporary) {
    @autoreleasepool {
        NSFileManager *fm=NSFileManager.defaultManager;
        NSString *root=[NSString stringWithUTF8String:temporary];
        NSString *directory=[root stringByAppendingPathComponent:@"Game/Interface/AddOns"];
        NSString *saved=[root stringByAppendingPathComponent:@"Game/WTF/SPTouchBarsDB.lua"];
        assert([fm createDirectoryAtPath:saved.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSData *layout=[@"synthetic layout sentinel" dataUsingEncoding:NSUTF8StringEncoding];
        assert([layout writeToFile:saved atomically:YES]);
        TKAddonStore *store=[[TKAddonStore alloc] initWithAddOnsDirectory:directory product:@"wowf" gameVersion:@"1.60.1"];
        TKFixtureTouchbars *addon=[[TKFixtureTouchbars alloc] initWithStore:store];
        addon.archive=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"fixture.zip"]];
        assert(!addon.enabled && addon.canToggle);
        NSError *error=nil;
        assert([addon setEnabled:NO error:&error] && addon.downloads==0);
        addon.failDownload=YES;
        assert(![addon setEnabled:YES error:&error] && error && !addon.enabled && store.records.count==0);
        addon.failDownload=NO; addon.downloads=0;
        error=nil;
        BOOL installed=[addon setEnabled:YES error:&error];
        if (!installed) fprintf(stderr,"Touchbars fixture install failed: %s\n",error.localizedDescription.UTF8String);
        assert(installed && addon.enabled && addon.downloads==1);
        NSString *toc=[directory stringByAppendingPathComponent:@"SPTouchBars/SPTouchBars.toc"];
        NSData *bytes=[NSData dataWithContentsOfFile:toc]; assert(bytes.length);
        NSString *uuid=store.records.firstObject.uuid;
        assert([store setPinned:YES record:store.records.firstObject error:&error]);
        assert([addon setEnabled:YES error:&error] && addon.downloads==1);
        int lock=TKWoWAcquireUpdateLock(root,&error); assert(lock>=0);
        assert(![addon setEnabled:NO error:&error] && [fm fileExistsAtPath:toc]);
        TKWoWReleaseUpdateLock(lock);
        assert([addon setEnabled:NO error:&error] && !addon.enabled && ![fm fileExistsAtPath:toc]);
        assert([addon setEnabled:NO error:&error]);
        assert([layout isEqual:[NSData dataWithContentsOfFile:saved]]);
        // Fresh model and store: no preference drift after an app restart.
        TKAddonStore *reopened=[[TKAddonStore alloc] initWithAddOnsDirectory:directory product:@"wowf" gameVersion:@"1.60.1"];
        TKFixtureTouchbars *offline=[[TKFixtureTouchbars alloc] initWithStore:reopened]; offline.failDownload=YES;
        assert(!offline.enabled && offline.canToggle);
        assert([offline setEnabled:YES error:&error] && offline.enabled && offline.downloads==0);
        assert([bytes isEqual:[NSData dataWithContentsOfFile:toc]]);
        assert([reopened.records.firstObject.uuid isEqual:uuid] && reopened.records.firstObject.pinned);
        // Addon Manager and another edition remain independent.
        assert([reopened setDisabled:YES record:reopened.records.firstObject error:&error]);
        [addon reload]; assert(!addon.enabled);
        NSString *retailDirectory=[root stringByAppendingPathComponent:@"Retail/Interface/AddOns"];
        TKAddonStore *retail=[[TKAddonStore alloc] initWithAddOnsDirectory:retailDirectory product:@"wow" gameVersion:@"12.0.5"];
        TKTouchbarsAddon *other=[[TKTouchbarsAddon alloc] initWithStore:retail]; assert(!other.enabled && other.canToggle);
        // A manually added folder must not be adopted or overwritten.
        NSString *manual=[root stringByAppendingPathComponent:@"Manual/Interface/AddOns"];
        assert([fm createDirectoryAtPath:[manual stringByAppendingPathComponent:@"SPTouchBars"] withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSString *manualTOC=[manual stringByAppendingPathComponent:@"SPTouchBars/SPTouchBars.toc"];
        assert([bytes writeToFile:manualTOC atomically:YES]);
        TKAddonStore *manualStore=[[TKAddonStore alloc] initWithAddOnsDirectory:manual product:@"wowf" gameVersion:@"1.60.1"];
        TKTouchbarsAddon *unmanaged=[[TKTouchbarsAddon alloc] initWithStore:manualStore];
        assert(unmanaged.enabled && !unmanaged.canToggle);
        assert(![unmanaged setEnabled:NO error:&error] && ![unmanaged setEnabled:YES error:&error]);
        assert([bytes isEqual:[NSData dataWithContentsOfFile:manualTOC]]);
        // Even a managed ZIP must not toggle unrelated addons in the same package.
        assert([retail importZIPAtURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"bundle.zip"]] error:&error]);
        [other reload]; assert(!other.canToggle && ![other setEnabled:NO error:&error]);
        assert([layout isEqual:[NSData dataWithContentsOfFile:saved]]);
        for (TKAddonStore *item in @[store,retail,manualStore]) [fm removeItemAtPath:[item valueForKey:@"support"] error:NULL];
        puts("TOUCHBARS LIFECYCLE PASS: opt-in, failed download, offline toggles, shared lock, per-edition state, pinned copy, saved layout and unmanaged/bundled addon protection");
    }
}
