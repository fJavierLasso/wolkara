#import "AddonStore.h"
#import "UpdateLock.h"
#include <stdio.h>

#define CHECK(condition, message) do { if (!(condition)) { fprintf(stderr, "FAIL: %s (%s)\n", message, error.localizedDescription.UTF8String ?: "no error"); return 1; } } while (0)
// The managed record the store is holding now. Each mutation reloads, so the object from before
// one is not the object to pass to the next - and the directory now holds an unmanaged folder
// too, which sorts before the managed one.
static TKAddonRecord *ManagedRecord(TKAddonStore *store) {
    for (TKAddonRecord *record in store.records) if (record.managed) return record;
    return nil;
}
int TestRealAddonImport(const char *fixtures, const char *temporary) {
    @autoreleasepool {
        NSString *root = [NSString stringWithUTF8String:temporary];
        NSString *directory = [root stringByAppendingPathComponent:@"Game/Interface/AddOns"];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *error = nil;
        CHECK([fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error], "create sandbox");
        TKAddonStore *store = [[TKAddonStore alloc] initWithAddOnsDirectory:directory product:@"wowf" gameVersion:@"1.60.1"];
        NSURL *zip = [NSURL fileURLWithPath:[[NSString stringWithUTF8String:fixtures] stringByAppendingPathComponent:@"valid.zip"]];
        CHECK([TKAddonInterfaceForVersion(@"1.60.1.70755") isEqual:@"16001"], "Forever interface version");
        CHECK([TKAddonInterfaceForVersion(@"1.15.7") isEqual:@"11507"], "Classic Era interface version");
        CHECK([TKAddonInterfaceForVersion(@"12.0.5") isEqual:@"120005"], "Retail interface version");
        CHECK(!TKAddonInterfaceForVersion(@"unknown") && !TKAddonInterfaceForVersion(@"1.100.1"), "unknown/malformed version refused");
        int updateLock=TKWoWAcquireUpdateLock(root,&error);
        CHECK(updateLock>=0, "updater acquires installation lock");
        CHECK(![store importZIPAtURL:zip error:&error], "addon write blocked by active game update");
        TKWoWReleaseUpdateLock(updateLock); error=nil;
        CHECK([store importZIPAtURL:zip error:&error], "real Swift ZIP imports through Objective-C bridge");
        CHECK(store.records.count == 1 && store.records.firstObject.managed, "managed manifest survives reload");
        NSString *toc = [directory stringByAppendingPathComponent:@"Fixture/Fixture.toc"];
        NSData *before = [NSData dataWithContentsOfFile:toc];
        CHECK(![store importZIPAtURL:zip error:&error], "duplicate import refused");
        CHECK([before isEqual:[NSData dataWithContentsOfFile:toc]], "duplicate preserves original bytes");
        CHECK([store setDisabled:YES record:store.records.firstObject error:&error], "disable imported addon");
        CHECK(store.records.firstObject.disabled && ![fm fileExistsAtPath:toc], "disabled state");
        CHECK([store setDisabled:NO record:store.records.firstObject error:&error], "restore imported addon");
        CHECK([before isEqual:[NSData dataWithContentsOfFile:toc]], "restore preserves bytes");
        CHECK([store removeRecord:store.records.firstObject error:&error], "remove owned addon");
        CHECK(store.records.count == 0 && ![fm fileExistsAtPath:toc], "removed state");
        // A removal that cannot write its record must not move anything. The state that loses
        // a package is folders moved aside while the record still claims them, so the record
        // is written first; making the add-on directory unwritable is what proves the order,
        // and the package has to be there and still be listed afterwards.
        CHECK([store importZIPAtURL:zip error:&error], "re-import for the removal checks");
        NSDictionary *permissions = [fm attributesOfItemAtPath:directory error:&error];
        CHECK([fm setAttributes:@{ NSFilePosixPermissions: @(0500) } ofItemAtPath:directory error:&error], "make the add-on directory unwritable");
        CHECK(![store removeRecord:store.records.firstObject error:&error], "removal refused when its record cannot be written");
        CHECK([fm fileExistsAtPath:toc], "and the package's folders are still there");
        CHECK([fm setAttributes:@{ NSFilePosixPermissions: permissions[NSFilePosixPermissions] } ofItemAtPath:directory error:&error], "put the directory back");
        CHECK(store.records.count == 1 && store.records.firstObject.managed, "and it is still listed as managed");
        CHECK([store removeRecord:store.records.firstObject error:&error], "removal works once it can write again");
        CHECK(store.records.count == 0 && ![fm fileExistsAtPath:toc], "and then removes it");
        // One previous copy per package, not one per removal: nothing reads that directory,
        // so a copy per removal was storage that grew for ever and could never be used.
        CHECK([store importZIPAtURL:zip error:&error], "re-import for the pruning check");
        CHECK([store removeRecord:store.records.firstObject error:&error], "remove a second time");
        NSString *previousRoot = [[store valueForKey:@"support"] stringByAppendingPathComponent:@"previous"];
        NSUInteger copies = 0;
        for (NSString *name in [fm contentsOfDirectoryAtPath:previousRoot error:&error]) if ([name hasPrefix:@"Fixture-"]) copies += 1;
        CHECK(copies == 1, "one previous copy is kept, not one per removal");
        NSURL *bad = [NSURL fileURLWithPath:[[NSString stringWithUTF8String:fixtures] stringByAppendingPathComponent:@"corrupt.zip"]];
        NSString *support = [store valueForKey:@"support"];
        NSArray *jobsBefore = [fm contentsOfDirectoryAtPath:support error:&error];
        CHECK(![store importZIPAtURL:bad error:&error], "corrupt ZIP rejected by real store");
        NSArray *jobsAfter = [fm contentsOfDirectoryAtPath:support error:&error];
        CHECK([[NSSet setWithArray:jobsBefore] isEqual:[NSSet setWithArray:jobsAfter]], "failed extraction leaves no staging job");
        // --- provider identity is recorded, never inferred
        NSDictionary *identity = @{ @"kind": @"curseforge", @"projectID": @61284,
                                    @"fileID": @100, @"fileName": @"Fixture-1.zip",
                                    @"version": @"1", @"compatibility": @"verified" };
        CHECK([store importZIPAtURL:zip provider:identity error:&error], "import records a provider identity");
        TKAddonRecord *owned = ManagedRecord(store);
        CHECK(owned.providerUpdatable, "a package with a CurseForge project and file is provider-updatable");
        CHECK([owned.provider[@"projectID"] isEqual:@61284], "the identity is the API's, not the folder's");
        CHECK(owned.uuid.length > 0, "the package has a stable identity of its own");
        CHECK([owned.compatibility isEqual:@"verified"], "a TOC declaring Forever's interface is verified");
        // An add-on the user already had is displayed and left alone, and it is never treated
        // as a CurseForge package just because its folder has a familiar name.
        NSString *unmanaged = [directory stringByAppendingPathComponent:@"Details"];
        CHECK([fm createDirectoryAtPath:unmanaged withIntermediateDirectories:YES attributes:nil error:&error], "create an unmanaged folder");
        CHECK([@"## Title: Details\n## Version: 1\n## Interface: 11509\n" writeToFile:[unmanaged stringByAppendingPathComponent:@"Details.toc"]
              atomically:YES encoding:NSUTF8StringEncoding error:&error], "with its own TOC");
        [store reload];
        TKAddonRecord *foreign = nil;
        for (TKAddonRecord *record in store.records) if ([record.identifier isEqual:@"Details"]) foreign = record;
        CHECK(foreign != nil && !foreign.managed, "an existing folder is not managed");
        CHECK(!foreign.providerUpdatable, "and never becomes provider-updatable from its name");
        CHECK([foreign.compatibility isEqual:@"unverified"], "an older interface is unverified, not refused");

        // --- a pinned package is not updated, and unpinning restores the ability
        CHECK([store setPinned:YES record:owned error:&error], "pin the package");
        // Each mutation reloads, so the object to pass on is the one the store is holding now.
        TKAddonRecord *pinned = ManagedRecord(store);
        CHECK(pinned.pinned, "the store reports it pinned");
        CHECK(![store updateRecord:pinned archiveURL:zip provider:pinned.provider error:&error],
              "a pinned package is refused, because pinned means leave it alone");
        CHECK([store setPinned:NO record:ManagedRecord(store) error:&error], "unpin it");

        // --- the transactional update itself
        NSInteger beforeUpdate = store.manifestRevision;
        NSDictionary *next = @{ @"kind": @"curseforge", @"projectID": @61284, @"fileID": @101,
                                @"fileName": @"Fixture-2.zip", @"version": @"2", @"compatibility": @"verified" };
        CHECK([store updateRecord:ManagedRecord(store) archiveURL:zip provider:next error:&error],
              "a managed package updates from an archive");
        CHECK(store.manifestRevision > beforeUpdate, "and the manifest revision moves");
        CHECK([ManagedRecord(store).provider[@"fileID"] isEqual:@101], "the record now names the new file");
        CHECK([fm fileExistsAtPath:toc], "the package's folders are where they were");

        // --- a failed update changes nothing at all
        NSInteger beforeFailure = store.manifestRevision;
        NSData *bytesBefore = [NSData dataWithContentsOfFile:toc];
        NSURL *corrupt = [NSURL fileURLWithPath:[[NSString stringWithUTF8String:fixtures] stringByAppendingPathComponent:@"corrupt.zip"]];
        CHECK(![store updateRecord:ManagedRecord(store) archiveURL:corrupt provider:next error:&error],
              "a corrupt archive is refused before anything is mutated");
        CHECK(store.manifestRevision == beforeFailure, "the manifest revision does not move");
        CHECK([bytesBefore isEqual:[NSData dataWithContentsOfFile:toc]], "and the installed bytes are untouched");
        CHECK([ManagedRecord(store).provider[@"fileID"] isEqual:@101], "and the record still names the installed file");

        // --- disabled state survives an update, and the package updates where it actually is
        CHECK([store setDisabled:YES record:ManagedRecord(store) error:&error], "disable the package");
        CHECK(![fm fileExistsAtPath:toc], "a disabled package is stored privately");
        CHECK([store updateRecord:ManagedRecord(store) archiveURL:zip provider:next error:&error],
              "a disabled package updates in place");
        CHECK(ManagedRecord(store).disabled, "and stays disabled");
        CHECK([store setDisabled:NO record:ManagedRecord(store) error:&error], "restore it");

        // --- users may remove any listed package; the operation stays inside its exact folder
        CHECK([store removeRecord:ManagedRecord(store) error:&error], "remove the managed package");
        CHECK([fm fileExistsAtPath:[unmanaged stringByAppendingPathComponent:@"Details.toc"]],
              "the existing folder remains until the user removes it");
        CHECK([store removeRecord:foreign error:&error], "remove an existing package at the user's request");
        CHECK(![fm fileExistsAtPath:[unmanaged stringByAppendingPathComponent:@"Details.toc"]],
              "the requested existing folder is removed");
        TKAddonRecord *unsafe = [TKAddonRecord new];
        unsafe.folders = @[@".."];
        unsafe.managed = NO;
        CHECK(![store removeRecord:unsafe error:&error], "refuse an existing-package removal outside AddOns");

        // A package is one record even if an update changes its top-level folders.
        CHECK([store importZIPAtURL:zip provider:identity error:&error], "install before a renamed multi-folder update");
        NSData *oldManifest=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@".wolkaraforever-addons.json"]];
        NSInteger oldRevision=store.manifestRevision;
        NSString *stableID=ManagedRecord(store).identifier;
        NSURL *renamed=[NSURL fileURLWithPath:[[NSString stringWithUTF8String:fixtures] stringByAppendingPathComponent:@"renamed-update.zip"]];
        CHECK([store updateRecord:ManagedRecord(store) archiveURL:renamed provider:next error:&error], "replace original folder and add a companion");
        CHECK(store.records.count==1 && [ManagedRecord(store).identifier isEqual:stableID], "one stable package, no unmanaged companion rows");
        CHECK(ManagedRecord(store).folders.count==2 && ![fm fileExistsAtPath:toc], "new folders replace the old folder");

        // A crash after the manifest commit must retain the new package, even if
        // its journal and old backup have not yet been deleted.
        NSString *updateJournal=[support stringByAppendingPathComponent:@"update-journal.json"];
        NSDictionary *completedJournal=@{@"base":directory, @"oldFolders":@[@"Fixture"],
            @"newFolders":ManagedRecord(store).folders, @"revision":@(oldRevision)};
        CHECK([oldManifest writeToFile:[support stringByAppendingPathComponent:@"update-manifest-backup.json"] atomically:YES], "old manifest backup");
        CHECK([[NSJSONSerialization dataWithJSONObject:completedJournal options:0 error:&error] writeToFile:updateJournal atomically:YES], "committed journal left by an interruption");
        NSInteger committedRevision=store.manifestRevision;
        [store reload];
        CHECK(store.manifestRevision==committedRevision && ManagedRecord(store).folders.count==2, "recovery keeps the committed manifest");
        CHECK([fm fileExistsAtPath:[directory stringByAppendingPathComponent:@"Replacement/Replacement.toc"]], "recovery keeps the committed new files");
        CHECK([store removeRecord:ManagedRecord(store) error:&error], "remove both owned folders");
        CHECK(![fm fileExistsAtPath:[directory stringByAppendingPathComponent:@"Companion"]], "companion is removed with its package");

        // Read all flavor TOCs and re-evaluate against the actual selected client.
        NSURL *flavors=[NSURL fileURLWithPath:[[NSString stringWithUTF8String:fixtures] stringByAppendingPathComponent:@"multi-flavor.zip"]];
        CHECK([store importZIPAtURL:flavors error:&error], "import multiple flavor manifests");
        TKAddonStore *retail=[[TKAddonStore alloc] initWithAddOnsDirectory:directory product:@"wowf" gameVersion:@"12.0.5"];
        CHECK([retail.records.firstObject.compatibility isEqual:TKAddonCompatibilityVerified], "Retail uses the matching secondary TOC");
        TKAddonStore *different=[[TKAddonStore alloc] initWithAddOnsDirectory:directory product:@"wowf" gameVersion:@"1.15.7"];
        CHECK([different.records.firstObject.compatibility isEqual:TKAddonCompatibilityUnverified], "old compatibility does not carry over to a different client");
        CHECK([store removeRecord:ManagedRecord(store) error:&error], "remove flavor fixture");

        CHECK([store importZIPAtURL:zip provider:identity error:&error], "older package retains its recorded provider identity");
        CHECK([store installZIPAtURL:zip error:&error], "website ZIP installs without provider credentials");
        CHECK(!ManagedRecord(store).providerUpdatable, "website replacement drops stale provider file identity");
        NSInteger webRevision=store.manifestRevision;
        CHECK([store installZIPAtURL:zip error:&error], "another download updates the same managed package");
        CHECK(store.records.count==1 && store.manifestRevision>webRevision, "website re-download keeps one package");
        CHECK([store setPinned:YES record:ManagedRecord(store) error:&error], "pin website package");
        CHECK(![store installZIPAtURL:zip error:&error], "website update respects pinning");
        CHECK([store setPinned:NO record:ManagedRecord(store) error:&error], "unpin website package");
        CHECK([store setDisabled:YES record:ManagedRecord(store) error:&error], "disable website package");
        CHECK([store installZIPAtURL:zip error:&error] && ManagedRecord(store).disabled, "website update preserves disabled state");
        CHECK([store removeRecord:ManagedRecord(store) error:&error], "remove website fixture");
        CHECK([fm createDirectoryAtPath:toc.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error], "create existing unmanaged folder");
        CHECK([before writeToFile:toc atomically:YES], "unmanaged bytes");
        CHECK(![store installZIPAtURL:zip error:&error] && [before isEqual:[NSData dataWithContentsOfFile:toc]], "website never overwrites unmanaged files");
        [fm removeItemAtPath:toc.stringByDeletingLastPathComponent error:NULL];

        // A TOC with embedded database data is still an add-on. Inspect only its
        // header, while importing/updating the complete original bytes.
        NSURL *database=[NSURL fileURLWithPath:[[NSString stringWithUTF8String:fixtures] stringByAppendingPathComponent:@"database-toc.zip"]];
        CHECK([store installZIPAtURL:database error:&error], "large database TOCs install from website ZIP");
        CHECK([ManagedRecord(store).name isEqual:@"Database fixture"] &&
              [ManagedRecord(store).compatibility isEqual:TKAddonCompatibilityVerified], "large TOC metadata remains readable");
        NSString *databaseTOC=[directory stringByAppendingPathComponent:@"Database/Database_Forever.toc"];
        NSData *databaseBytes=[NSData dataWithContentsOfFile:databaseTOC];
        CHECK(databaseBytes.length>15*1024*1024, "whole database TOC is installed");
        NSString *header=TKAddonReadTOCHeader(databaseTOC);
        CHECK(header.length<64*1024 && ![header containsString:@"X-Data"], "bounded header drops a cut line");
        CHECK([store installZIPAtURL:database error:&error], "large TOC website update works");
        CHECK([databaseBytes isEqual:[NSData dataWithContentsOfFile:databaseTOC]], "large TOC update preserves all bytes");
        CHECK([store setDisabled:YES record:ManagedRecord(store) error:&error], "large TOC can be disabled");
        CHECK([store setDisabled:NO record:ManagedRecord(store) error:&error], "large TOC can be restored");
        CHECK([databaseBytes isEqual:[NSData dataWithContentsOfFile:databaseTOC]], "large TOC restore preserves all bytes");
        CHECK([store removeRecord:ManagedRecord(store) error:&error], "remove database fixture");

        NSString *headerPath=[root stringByAppendingPathComponent:@"header.toc"];
        CHECK([@"## Title: Caf\u00e9\n## Version: 2" writeToFile:headerPath atomically:YES encoding:NSUTF8StringEncoding error:&error], "UTF-8 header fixture");
        CHECK([TKAddonReadTOCHeader(headerPath) isEqual:@"## Title: Caf\u00e9\n## Version: 2"], "small TOC keeps UTF-8 and last line without newline");
        NSString *linkPath=[root stringByAppendingPathComponent:@"header-link.toc"];
        CHECK([fm createSymbolicLinkAtPath:linkPath withDestinationPath:headerPath error:&error], "symlink fixture");
        CHECK(!TKAddonReadTOCHeader(linkPath) && !TKAddonReadTOCHeader(root), "header reader rejects symlinks and directories");

        // Generic fallback TOCs may be an intentional error stub. Select the
        // current client's metadata without changing any bytes in the package.
        NSString *flavorRoot=[root stringByAppendingPathComponent:@"Flavors/Interface/AddOns"];
        CHECK([fm createDirectoryAtPath:flavorRoot withIntermediateDirectories:YES attributes:nil error:&error], "flavor sandbox");
        TKAddonStore *flavorStore=[[TKAddonStore alloc] initWithAddOnsDirectory:flavorRoot product:@"wowf" gameVersion:@"1.60.1"];
        NSURL *flavorZIP=[NSURL fileURLWithPath:[[NSString stringWithUTF8String:fixtures] stringByAppendingPathComponent:@"flavor.zip"]];
        CHECK([flavorStore importZIPAtURL:flavorZIP error:&error], "import multi-client package");
        CHECK([flavorStore.records.firstObject.name isEqual:@"Forever quests"] && [flavorStore.records.firstObject.version isEqual:@"12"], "Forever metadata beats unsupported stub and Camelot alias");
        NSString *generic=[flavorRoot stringByAppendingPathComponent:@"Flavor/Flavor.toc"];
        NSData *genericBytes=[NSData dataWithContentsOfFile:generic];
        CHECK([flavorStore setDisabled:YES record:flavorStore.records.firstObject error:&error], "disable multi-client package");
        CHECK([flavorStore.records.firstObject.name isEqual:@"Forever quests"], "disabled metadata still selects client");
        CHECK([flavorStore setDisabled:NO record:flavorStore.records.firstObject error:&error], "restore multi-client package");
        CHECK([genericBytes isEqual:[NSData dataWithContentsOfFile:generic]], "do not rewrite fallback manifest");
        TKAddonStore *era=[[TKAddonStore alloc] initWithAddOnsDirectory:flavorRoot product:@"wow_classic_era" gameVersion:@"1.15.9"];
        CHECK([era.records.firstObject.name isEqual:@"Era quests"], "switching clients selects matching interface metadata");
        TKAddonStore *unknown=[[TKAddonStore alloc] initWithAddOnsDirectory:flavorRoot product:@"unknown" gameVersion:@"unknown"];
        CHECK([unknown.records.firstObject.name isEqual:@"game client not supported"], "unknown clients retain generic fallback");
        // Previously installed, unmanaged folders benefit without reinstalling.
        CHECK([fm removeItemAtPath:[flavorRoot stringByAppendingPathComponent:@".wolkaraforever-addons.json"] error:&error], "remove fixture ownership only");
        [flavorStore reload];
        CHECK(!flavorStore.records.firstObject.managed && [flavorStore.records.firstObject.name isEqual:@"Forever quests"], "unmanaged flavor metadata");

        // --- format-1 -> format-2 migration, and recovery from an interrupted one
        NSString *legacyRoot = [root stringByAppendingPathComponent:@"Legacy/Interface/AddOns"];
        CHECK([fm createDirectoryAtPath:[legacyRoot stringByAppendingPathComponent:@"LegacyAddon"]
                withIntermediateDirectories:YES attributes:nil error:&error], "create a legacy installation");
        CHECK([@"## Title: Legacy Addon\n## Version: 1\n## Interface: 16001\n"
                writeToFile:[[legacyRoot stringByAppendingPathComponent:@"LegacyAddon"] stringByAppendingPathComponent:@"LegacyAddon.toc"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "with a package");
        NSString *formatOne = @"{\"format\":1,\"product\":\"wowf\",\"gameVersion\":\"1.60.1\",\"packages\":["
            "{\"identifier\":\"LegacyAddon\",\"name\":\"Legacy Addon\",\"version\":\"1\",\"source\":\"zip\","
            "\"archiveSHA256\":\"abc\",\"folders\":[\"LegacyAddon\"],\"pinned\":true,\"disabled\":false}]}";
        CHECK([formatOne writeToFile:[legacyRoot stringByAppendingPathComponent:@".wolkaraforever-addons.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "write a format-1 manifest");
        updateLock=TKWoWAcquireUpdateLock(root,&error);
        CHECK(updateLock>=0, "hold game-update lock during manager open");
        TKAddonStore *locked=[[TKAddonStore alloc] initWithAddOnsDirectory:legacyRoot product:@"wowf" gameVersion:@"1.60.1"];
        CHECK(locked.records.count==0, "opening the manager waits for the active writer");
        CHECK([[NSString stringWithContentsOfFile:[legacyRoot stringByAppendingPathComponent:@".wolkaraforever-addons.json"] encoding:NSUTF8StringEncoding error:&error] isEqual:formatOne], "opening under lock does not migrate the manifest");
        TKWoWReleaseUpdateLock(updateLock); error=nil;
        TKAddonStore *legacy = [[TKAddonStore alloc] initWithAddOnsDirectory:legacyRoot product:@"wowf" gameVersion:@"1.60.1"];
        CHECK(legacy.manifestFormat == 2, "a format-1 manifest is migrated on first read");
        CHECK(legacy.manifestRevision >= 1, "and the migration commits a revision");
        CHECK(legacy.records.count == 1 && legacy.records.firstObject.managed, "the package survives the migration");
        CHECK(legacy.records.firstObject.uuid.length > 0, "and gains a stable identity");
        CHECK(legacy.records.firstObject.pinned, "and keeps its pinned state");

        // The interrupted case: the journal is on disk, the format-2 write never finished.
        NSString *legacySupport = [legacy valueForKey:@"support"];
        CHECK([fm createDirectoryAtPath:legacySupport withIntermediateDirectories:YES attributes:nil error:&error], "create the legacy support folder");
        CHECK([formatOne writeToFile:[legacySupport stringByAppendingPathComponent:@"manifest-v1-backup.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "keep the format-1 backup");
        CHECK([@"{\"from\":1,\"to\":2,\"revision\":2}" writeToFile:[legacySupport stringByAppendingPathComponent:@"manifest-journal.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "and the journal");
        CHECK([@"{\"format\":2,\"revision\":2,\"packages\":[{\"identifier\":\"LegacyAddon\"}]}"
                writeToFile:[legacyRoot stringByAppendingPathComponent:@".wolkaraforever-addons.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "and a half-written format-2 manifest");
        TKAddonStore *recovered = [[TKAddonStore alloc] initWithAddOnsDirectory:legacyRoot product:@"wowf" gameVersion:@"1.60.1"];
        CHECK(recovered.recoveredInterruptedWrite, "an interrupted migration is reported as recovered");
        CHECK(recovered.records.count == 1 && recovered.records.firstObject.managed,
              "and the package that was there before is back");
        CHECK(recovered.manifestFormat == 2, "and the retried migration completes");

        // Clean only this fixture's private support directories, never another import.
        CHECK([fm removeItemAtPath:support error:&error], "remove fixture staging and backups");
        CHECK([fm removeItemAtPath:legacySupport error:&error], "remove the legacy support folder");
        puts("ADDON IMPORT PASS: real ZIP -> Objective-C bridge -> store -> provider identity, migration, transactional update, rollback, unmanaged folders");
        return 0;
    }
}
