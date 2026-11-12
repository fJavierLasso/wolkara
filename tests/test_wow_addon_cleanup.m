#import <Foundation/Foundation.h>
#import "../launcher/WoW/AddonCleanup.h"
#import "../launcher/WoW/AddonStore.h"
#import "../launcher/WoW/UpdateLock.h"
#include <assert.h>

static void TestManagedTouchbarsRemoval(NSString *parent) {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSData *bytes=[@"synthetic addon and saved-layout sentinel" dataUsingEncoding:NSUTF8StringEncoding];
    for (NSString *scenario in @[@"active", @"disabled", @"unmanaged", @"bundle"]) {
        NSString *root=[parent stringByAppendingPathComponent:scenario];
        NSString *addons=[root stringByAppendingPathComponent:@"Interface/AddOns"];
        assert([fm createDirectoryAtPath:addons withIntermediateDirectories:YES attributes:nil error:NULL]);
        TKAddonStore *store=[[TKAddonStore alloc] initWithAddOnsDirectory:addons product:@"wowf" gameVersion:@"1.60.1"];
        NSString *support=[store valueForKey:@"support"];
        BOOL disabled=[scenario isEqual:@"disabled"];
        BOOL managed=![scenario isEqual:@"unmanaged"];
        BOOL bundle=[scenario isEqual:@"bundle"];
        NSString *base=disabled ? [support stringByAppendingPathComponent:@"disabled/SPTouchBars"] : addons;
        NSString *folder=[base stringByAppendingPathComponent:@"SPTouchBars"];
        assert([fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]);
        assert([bytes writeToFile:[folder stringByAppendingPathComponent:@"SPTouchBars.toc"] atomically:YES]);
        NSString *other=[addons stringByAppendingPathComponent:@"OtherAddon"];
        assert([fm createDirectoryAtPath:other withIntermediateDirectories:NO attributes:nil error:NULL]);
        assert([bytes writeToFile:[other stringByAppendingPathComponent:@"OtherAddon.toc"] atomically:YES]);
        NSString *saved=[root stringByAppendingPathComponent:@"WTF/SPTouchBars.lua"];
        assert([fm createDirectoryAtPath:saved.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
        assert([bytes writeToFile:saved atomically:YES]);
        NSDictionary *package=@{@"identifier":@"SPTouchBars", @"uuid":NSUUID.UUID.UUIDString,
            @"name":@"SPTouchBars", @"version":@"0.7.0", @"source":@"zip", @"archiveSHA256":@"fixture",
            @"folders":bundle ? @[@"SPTouchBars",@"OtherAddon"] : @[@"SPTouchBars"],
            @"disabled":@(disabled), @"pinned":@YES};
        NSString *manifest=[addons stringByAppendingPathComponent:@".wolkaraforever-addons.json"];
        NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"format":@2,@"revision":@1,@"packages":managed ? @[package] : @[]} options:0 error:NULL];
        assert([data writeToFile:manifest atomically:YES]);
        NSError *error=nil;
        assert(TKWoWRetireTouchAddon(root,&error));
        int lock=TKWoWAcquireUpdateLock(root.stringByDeletingLastPathComponent,&error); assert(lock>=0);
        assert(!TKWoWRetireManagedTouchbars(root,@"wowf",@"1.60.1",&error));
        assert([fm fileExistsAtPath:folder]);
        TKWoWReleaseUpdateLock(lock); error=nil;
        assert(TKWoWRetireManagedTouchbars(root,@"wowf",@"1.60.1",&error) && !error);
        assert([fm fileExistsAtPath:folder]==(!managed || bundle));
        assert([[NSData dataWithContentsOfFile:saved] isEqual:bytes]);
        assert([[NSData dataWithContentsOfFile:[other stringByAppendingPathComponent:@"OtherAddon.toc"]] isEqual:bytes]);
        if (managed && !bundle) {
            [store reload]; assert(store.records.count==1 && !store.records.firstObject.managed);
            NSString *previous=[support stringByAppendingPathComponent:@"previous"];
            NSArray *copies=[fm contentsOfDirectoryAtPath:previous error:NULL]; assert(copies.count==1);
            NSString *copy=[[previous stringByAppendingPathComponent:copies[0]] stringByAppendingPathComponent:@"SPTouchBars/SPTouchBars.toc"];
            assert([[NSData dataWithContentsOfFile:copy] isEqual:bytes]);
        }
        assert(TKWoWRetireManagedTouchbars(root,@"wowf",@"1.60.1",&error));
        // Reinstalling explicitly later is respected, even if managed again.
        if (managed && !bundle) {
            assert([fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]);
            assert([bytes writeToFile:[folder stringByAppendingPathComponent:@"SPTouchBars.toc"] atomically:YES]);
            assert([data writeToFile:manifest atomically:YES]);
            assert(TKWoWRetireManagedTouchbars(root,@"wowf",@"1.60.1",&error) && [fm fileExistsAtPath:folder]);
        }
        [fm removeItemAtPath:support error:NULL];
    }
}

int main(void) { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSError *error = nil;
    assert(TKWoWRetireTouchAddon(root,&error) && !error);
    NSString *addons = [root stringByAppendingPathComponent:@"Interface/AddOns"];
    NSString *source = [addons stringByAppendingPathComponent:@"WolkaraTouch"];
    assert([fm createDirectoryAtPath:source withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSData *original = [@"original synthetic addon" dataUsingEncoding:NSUTF8StringEncoding];
    assert([original writeToFile:[source stringByAppendingPathComponent:@"Fixture.lua"] atomically:YES]);
    NSString *other = [addons stringByAppendingPathComponent:@"OtherAddon"];
    assert([fm createDirectoryAtPath:other withIntermediateDirectories:NO attributes:nil error:NULL]);
    assert([original writeToFile:[other stringByAppendingPathComponent:@"Keep.lua"] atomically:YES]);
    assert(TKWoWRetireTouchAddon(root,&error) && ![fm fileExistsAtPath:source]);
    NSString *disabled = [root stringByAppendingPathComponent:@"Interface/DisabledAddOns"];
    NSArray *backups = [fm contentsOfDirectoryAtPath:disabled error:NULL]; assert(backups.count == 1);
    NSString *backup = [[disabled stringByAppendingPathComponent:backups[0]] stringByAppendingPathComponent:@"Fixture.lua"];
    assert([[NSData dataWithContentsOfFile:backup] isEqual:original]);
    assert([[NSData dataWithContentsOfFile:[other stringByAppendingPathComponent:@"Keep.lua"]] isEqual:original]);
    assert(TKWoWRetireTouchAddon(root,&error)); // Idempotent and no empty backups.
    assert([fm contentsOfDirectoryAtPath:disabled error:NULL].count == 1);
    // Repeated installs do not overwrite an earlier backup.
    assert([fm createDirectoryAtPath:source withIntermediateDirectories:NO attributes:nil error:NULL]);
    assert(TKWoWRetireTouchAddon(root,&error));
    assert([fm contentsOfDirectoryAtPath:disabled error:NULL].count == 2);
    // Retire only installer-owned mobile directories, including interrupted installs.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:YES forKey:@"WolkaraMobileEnabled"];
    [defaults setBool:YES forKey:@"WolkaraMobileAvailable"];
    [defaults setObject:@"keep layout" forKey:@"WolkaraTouchAbilitiesV1"];
    NSArray *names = @[@"WolkaraMobile",@".WolkaraMobile-stage",@".WolkaraMobile-backup"];
    for (NSString *name in names) {
        NSString *folder = [addons stringByAppendingPathComponent:name];
        assert([fm createDirectoryAtPath:folder withIntermediateDirectories:NO attributes:nil error:NULL]);
        assert([@"WolkaraMobile bundled addon v1\n" writeToFile:[folder stringByAppendingPathComponent:@".wolkara-owner"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        assert([original writeToFile:[folder stringByAppendingPathComponent:@"Fixture.lua"] atomically:YES]);
    }
    assert(TKWoWRetireTouchAddon(root,&error));
    assert(![defaults objectForKey:@"WolkaraMobileEnabled"] && ![defaults objectForKey:@"WolkaraMobileAvailable"]);
    assert([[defaults stringForKey:@"WolkaraTouchAbilitiesV1"] isEqual:@"keep layout"]);
    for (NSString *name in names) {
        assert(![fm fileExistsAtPath:[addons stringByAppendingPathComponent:name]]);
        NSArray *matches = [[fm contentsOfDirectoryAtPath:disabled error:NULL] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH %@",[name stringByAppendingString:@"-"]]];
        assert(matches.count == 1);
        NSString *file = [[disabled stringByAppendingPathComponent:matches[0]] stringByAppendingPathComponent:@"Fixture.lua"];
        assert([[NSData dataWithContentsOfFile:file] isEqual:original]);
    }
    assert(TKWoWRetireTouchAddon(root,&error) && [fm contentsOfDirectoryAtPath:disabled error:NULL].count == 5);
    NSString *foreign = [addons stringByAppendingPathComponent:@"WolkaraMobile"];
    assert([fm createDirectoryAtPath:foreign withIntermediateDirectories:NO attributes:nil error:NULL]);
    assert(TKWoWRetireTouchAddon(root,&error) && [fm fileExistsAtPath:foreign]);
    NSString *marker = [foreign stringByAppendingPathComponent:@".wolkara-owner"];
    assert([@"Someone else's addon" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    assert(TKWoWRetireTouchAddon(root,&error) && [fm fileExistsAtPath:foreign]);
    assert([fm removeItemAtPath:marker error:NULL]);
    assert([fm createSymbolicLinkAtPath:marker withDestinationPath:[other stringByAppendingPathComponent:@"Keep.lua"] error:NULL]);
    assert(!TKWoWRetireTouchAddon(root,&error) && [fm fileExistsAtPath:foreign]);
    assert([[NSData dataWithContentsOfFile:[other stringByAppendingPathComponent:@"Keep.lua"]] isEqual:original]);
    assert([fm removeItemAtPath:foreign error:NULL]);
    [defaults removeObjectForKey:@"WolkaraTouchAbilitiesV1"];
    // No links at the source or its ancestors may reach another installation.
    assert([fm createSymbolicLinkAtPath:source withDestinationPath:other error:NULL]);
    assert(!TKWoWRetireTouchAddon(root,&error) && error);
    assert([fm removeItemAtPath:source error:NULL]);
    assert([fm removeItemAtPath:addons error:NULL]);
    assert([fm createSymbolicLinkAtPath:addons withDestinationPath:disabled error:NULL]);
    assert(!TKWoWRetireTouchAddon(root,&error));
    assert([fm removeItemAtPath:addons error:NULL]);
    assert([fm createDirectoryAtPath:source withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([fm removeItemAtPath:disabled error:NULL]);
    assert([fm createSymbolicLinkAtPath:disabled withDestinationPath:root error:NULL]);
    assert(!TKWoWRetireTouchAddon(root,&error) && [fm fileExistsAtPath:source]);
    TestManagedTouchbarsRemoval([root stringByAppendingPathComponent:@"ManagedFixtures"]);
    assert([fm removeItemAtPath:root error:NULL]);
    puts("Addon cleanup PASS: legacy and managed Touchbars retirement, saved layout and backup preservation, shared lock, unmanaged/bundled isolation, one-time removal and symlink rejection.");
} return 0; }
