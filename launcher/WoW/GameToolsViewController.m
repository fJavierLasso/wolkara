#import "GameToolsViewController.h"
#import "AddonManager.h"
#import "ForeverUI.h"
#import "UpdateLock.h"

@implementation TKGameToolsViewController {
    NSString *_directory, *_product, *_edition, *_version;
    BOOL _busy;
}
- (instancetype)initWithWorkingDirectory:(NSString *)directory product:(NSString *)product
                                edition:(NSString *)edition version:(NSString *)version {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        _directory=directory.copy; _product=product.copy; _edition=edition.copy; _version=version.copy;
        self.title=@"Game tools";
    }
    return self;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return 5;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section; return _edition;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return @"Changes apply only to this edition, while the game is closed. Backups contain WTF and Interface, including settings and addons. Graphics are changed only when you request it.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text=@[@"Manage addons", @"Back up settings and addons", @"Restore latest backup", @"Enable gamepad", @"Reset graphics settings"][indexPath.row];
    cell.accessibilityIdentifier=[NSString stringWithFormat:@"game.tools.%ld",(long)indexPath.row];
    cell.textLabel.enabled=!_busy;
    if (indexPath.row==0) cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)showResult:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Game tools" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)performOperation:(NSInteger)operation {
    if (_busy) return;
    _busy=YES; self.navigationItem.hidesBackButton=YES; self.modalInPresentation=YES;
    self.navigationController.interactivePopGestureRecognizer.enabled=NO;
    [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil; NSString *message=nil;
        int lock=TKWoWAcquireUpdateLock(self->_directory.stringByDeletingLastPathComponent,&error);
        if (lock>=0) {
            @try {
                BOOL recovered=[TKForeverUI recoverInterruptedRestoreInWorkingDirectory:self->_directory error:&error];
                if (recovered && operation==1) {
                    NSString *backup=[TKForeverUI createUIBackupInWorkingDirectory:self->_directory edition:self->_product error:&error];
                    if (backup) message=[NSString stringWithFormat:@"Backup saved: %@",backup.lastPathComponent];
                } else if (recovered && operation==2) {
                    NSString *backup=[TKForeverUI newestUIBackupInWorkingDirectory:self->_directory error:&error];
                    if (backup && [TKForeverUI restoreUIBackupNamed:backup inWorkingDirectory:self->_directory edition:self->_product error:&error]) message=@"Settings and addons restored.";
                    else if (!backup && !error) message=@"No backup exists for this installation yet.";
                } else if (recovered && operation==3) {
                    if ([TKForeverUI enableGamepadInWorkingDirectory:self->_directory error:&error]) message=@"Gamepad enabled. Start the game to use it.";
                } else if (recovered && operation==4) {
                    if ([TKForeverUI resetGraphicsInWorkingDirectory:self->_directory error:&error]) message=@"Graphics settings reset. Your other settings are preserved.";
                }
            } @finally { TKWoWReleaseUpdateLock(lock); }
        }
        dispatch_async(dispatch_get_main_queue(),^{
            self->_busy=NO; self.navigationItem.hidesBackButton=NO; self.modalInPresentation=NO;
            self.navigationController.interactivePopGestureRecognizer.enabled=YES;
            [self.tableView reloadData];
            [self showResult:error.localizedDescription ?: message ?: @"The operation could not finish."];
        });
    });
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_busy) return;
    NSInteger operation=indexPath.row;
    if (!operation) {
        NSString *addons=[_directory stringByAppendingPathComponent:@"Interface/AddOns"];
        TKWoWAddonManagerViewController *controller=[[TKWoWAddonManagerViewController alloc]
            initWithAddOnsDirectory:addons edition:_edition product:_product gameVersion:_version];
        [self.navigationController pushViewController:controller animated:YES];
    } else if (operation==2 || operation==4) {
        NSString *message=operation==2 ? @"Replace this edition's WTF and Interface with the latest backup? Make a new backup first if you want to keep the current files." : @"Reset this edition's graphics settings? Account, input, audio and other settings are preserved.";
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:operation==2 ? @"Restore backup" : @"Reset graphics" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:operation==2 ? @"Restore" : @"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { (void)action; [self performOperation:operation]; }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else [self performOperation:operation];
}
@end
