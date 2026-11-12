#import "AddonCleanup.h"
#import "AddonStore.h"
#import "UpdateLock.h"
#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>

static BOOL Fail(NSError **error) {
    if (error) *error = [NSError errorWithDomain:@"Wolkara.AddonCleanup" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"Could not retire an experimental Wolkara addon. Move WolkaraTouch and the bundled WolkaraMobile out of Interface/AddOns before playing."}];
    return NO;
}
BOOL TKWoWRetireTouchAddon(NSString *editionDirectory, NSError **error) {
    struct stat status;
    if (!editionDirectory.isAbsolutePath || lstat(editionDirectory.fileSystemRepresentation,&status) || !S_ISDIR(status.st_mode)) return Fail(error);
    // Accept the container's /var alias, then reject symlinks below the root.
    char *resolved = realpath(editionDirectory.fileSystemRepresentation,NULL);
    if (!resolved) return Fail(error);
    NSString *root = [NSString stringWithUTF8String:resolved]; free(resolved);
    NSString *source = root;
    for (NSString *part in @[@"Interface",@"AddOns"]) {
        source = [source stringByAppendingPathComponent:part];
        if (lstat(source.fileSystemRepresentation,&status)) {
            if (errno != ENOENT) return Fail(error);
            source = nil; break;
        }
        if (!S_ISDIR(status.st_mode)) return Fail(error);
    }
    NSString *disabled = [root stringByAppendingPathComponent:@"Interface/DisabledAddOns"];
    for (NSString *name in @[@"WolkaraTouch", @"WolkaraMobile", @".WolkaraMobile-stage", @".WolkaraMobile-backup"]) {
        if (!source) break;
        NSString *candidate = [source stringByAppendingPathComponent:name];
        if (lstat(candidate.fileSystemRepresentation,&status)) {
            if (errno == ENOENT) continue;
            return Fail(error);
        }
        if (!S_ISDIR(status.st_mode)) return Fail(error);
        if (![name isEqual:@"WolkaraTouch"]) {
            // Only our installer-owned directories may be retired. Never follow
            // a marker link or remove a same-named addon installed by the user.
            NSString *marker = [candidate stringByAppendingPathComponent:@".wolkara-owner"];
            int fd = open(marker.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
            if (fd < 0) { if (errno == ENOENT) continue; return Fail(error); }
            BOOL regular = !fstat(fd,&status) && S_ISREG(status.st_mode) && status.st_size <= 128;
            char bytes[129]; ssize_t count = regular ? read(fd,bytes,sizeof bytes) : -1;
            close(fd);
            if (count < 0) return Fail(error);
            NSData *owner = [NSData dataWithBytes:bytes length:(NSUInteger)count];
            if (![owner isEqual:[@"WolkaraMobile bundled addon v1\n" dataUsingEncoding:NSUTF8StringEncoding]]) continue;
        }
        if (lstat(disabled.fileSystemRepresentation,&status)) {
            if (errno != ENOENT) return Fail(error);
            if (![NSFileManager.defaultManager createDirectoryAtPath:disabled withIntermediateDirectories:NO attributes:nil error:error]) return NO;
        } else if (!S_ISDIR(status.st_mode)) return Fail(error);
        NSString *destination = [disabled stringByAppendingPathComponent:[name stringByAppendingFormat:@"-%@",NSUUID.UUID.UUIDString]];
        if (![NSFileManager.defaultManager moveItemAtPath:candidate toPath:destination error:error]) return NO;
    }
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraMobileEnabled"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraMobileAvailable"];
    return YES;
}

BOOL TKWoWRetireManagedTouchbars(NSString *editionDirectory, NSString *product,
                               NSString *version, NSError **error) {
    NSString *receipt=[editionDirectory stringByAppendingPathComponent:@".wolkara-retired-touchbars-v1"];
    struct stat info;
    if (!lstat(receipt.fileSystemRepresentation,&info)) {
        return S_ISREG(info.st_mode) ? YES : Fail(error);
    }
    if (errno!=ENOENT) return Fail(error);
    // The preceding legacy cleanup validates the edition/Interface/AddOns
    // paths. Only a single, explicitly managed package may be retired here.
    NSString *addons=[editionDirectory stringByAppendingPathComponent:@"Interface/AddOns"];
    TKAddonStore *store=[[TKAddonStore alloc] initWithAddOnsDirectory:addons product:product gameVersion:version];
    for (__strong TKAddonRecord *record in store.records) {
        if (!record.managed || ![record.folders isEqualToArray:@[@"SPTouchBars"]]) continue;
        // Disable first: even if removal of the ownership record later fails,
        // the addon cannot run or continue hiding the original action bars.
        if (!record.disabled && [NSFileManager.defaultManager fileExistsAtPath:[addons stringByAppendingPathComponent:@"SPTouchBars"]]) {
            if (![store setDisabled:YES record:record error:error]) return NO;
            for (TKAddonRecord *current in store.records) {
                if ([current.uuid isEqual:record.uuid]) { record=current; break; }
            }
        }
        if (![store removeRecord:record error:error]) return NO;
    }
    // Do not keep removing a deliberate manual reinstall on future launches.
    // This receipt lives with the edition, so app upgrades keep it in place.
    int lock=TKWoWAcquireUpdateLock(editionDirectory.stringByDeletingLastPathComponent,error);
    if (lock<0) return NO;
    @try {
        return [[NSData data] writeToFile:receipt options:NSDataWritingAtomic error:error];
    } @finally { TKWoWReleaseUpdateLock(lock); }
}
