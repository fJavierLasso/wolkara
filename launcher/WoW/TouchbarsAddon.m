#import "TouchbarsAddon.h"
#import "Client.h"
#import <objc/message.h>

static NSString *const TouchbarsRevision=@"6ac5bf2e02dba2e2160cf444eef533a4e0118b91";
static BOOL Fail(NSError **error, NSString *message) {
    if (error) *error=[NSError errorWithDomain:@"Wolkara.Touchbars" code:1
                                     userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}

@implementation TKTouchbarsAddon {
    TKAddonStore *_store;
}
- (instancetype)initWithStore:(TKAddonStore *)store {
    if ((self=[super init])) _store=store;
    return self;
}
- (void)reload { [_store reload]; }
- (NSArray<TKAddonRecord *> *)matchingRecords {
    NSMutableArray *matches=[NSMutableArray new];
    for (TKAddonRecord *record in _store.records) {
        for (NSString *folder in record.folders) {
            if ([folder caseInsensitiveCompare:@"SPTouchBars"]==NSOrderedSame) {
                [matches addObject:record]; break;
            }
        }
    }
    return matches;
}
- (BOOL)enabled {
    for (TKAddonRecord *record in [self matchingRecords]) if (!record.disabled) return YES;
    return NO;
}
- (BOOL)canToggle {
    NSArray<TKAddonRecord *> *matches=[self matchingRecords];
    if (!matches.count) return YES;
    // Never adopt an unowned folder, or toggle a bundle containing other addons.
    TKAddonRecord *record=matches.firstObject;
    return matches.count==1 && record.managed &&
        [record.folders isEqualToArray:@[@"SPTouchBars"]];
}
- (BOOL)prepareArchiveAtURL:(NSURL *)url error:(NSError **)error {
    TKWoWClient *client=[TKWoWClient new];
    NSMutableDictionary *files=[NSMutableDictionary new];
    for (NSString *name in @[@"SPTouchBars.toc", @"SPTouchBars.lua", @"SPTouchBars.tga", @"LICENSE"]) {
        NSString *path=[name isEqualToString:@"LICENSE"] ? name : [@"SPTouchBars/" stringByAppendingString:name];
        NSString *source=[NSString stringWithFormat:@"https://raw.githubusercontent.com/rollarz/Touchbars/%@/%@",TouchbarsRevision,path];
        NSData *data=[client fetch:[NSURL URLWithString:source] limit:2*1024*1024 error:error];
        if (!data) return NO;
        files[name]=data;
    }
    Class writer=NSClassFromString(@"TKTouchbarsArchive");
    SEL selector=NSSelectorFromString(@"writeFiles:toURL:error:");
    if (![writer respondsToSelector:selector]) return Fail(error,@"Touchbars installation is unavailable in this build.");
    BOOL (*write)(id,SEL,NSDictionary *,NSURL *,NSError **)=(void *)objc_msgSend;
    return write(writer,selector,files,url,error);
}
- (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
    [self reload];
    if (!self.canToggle) return Fail(error,@"An existing Touchbars folder or addon bundle is managed separately. Use Manage addons to review it; no files were changed.");
    TKAddonRecord *record=[self matchingRecords].firstObject;
    if (record) {
        if (record.disabled!=enabled) return YES;
        // The store acquires the edition update lock itself. Do not hold it
        // across this call (or a download), which would deadlock the importer.
        return [_store setDisabled:!enabled record:record error:error];
    }
    if (!enabled) return YES;
    NSFileManager *manager=NSFileManager.defaultManager;
    NSURL *job=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                URLByAppendingPathComponent:[@"wolkara-touchbars-" stringByAppendingString:NSUUID.UUID.UUIDString]
                isDirectory:YES];
    if (![manager createDirectoryAtURL:job withIntermediateDirectories:NO attributes:nil error:error]) return NO;
    @try {
        NSURL *archive=[job URLByAppendingPathComponent:@"Touchbars.zip"];
        if (![self prepareArchiveAtURL:archive error:error]) return NO;
        // Import only: a file installed while downloading must not be replaced.
        return [_store importZIPAtURL:archive error:error];
    } @finally { [manager removeItemAtURL:job error:NULL]; }
}
@end
