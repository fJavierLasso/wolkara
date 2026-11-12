#import "GameToolsViewController.h"
#import "AddonManager.h"
#import "ForeverUI.h"
#import "UpdateLock.h"
#import "TouchbarsAddon.h"

@implementation TKGameToolsViewController {
    NSString *_directory, *_product, *_edition, *_version;
    BOOL _busy;
    TKTouchbarsAddon *_touchbars;
    BOOL _touchbarsEnabled, _touchbarsCanToggle;
}
- (instancetype)initWithWorkingDirectory:(NSString *)directory product:(NSString *)product
                                edition:(NSString *)edition version:(NSString *)version {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        _directory=directory.copy; _product=product.copy; _edition=edition.copy; _version=version.copy;
        self.title=@"Game tools";
        TKAddonStore *store=[[TKAddonStore alloc] initWithAddOnsDirectory:[directory stringByAppendingPathComponent:@"Interface/AddOns"]
                                                               product:product gameVersion:version];
        _touchbars=[[TKTouchbarsAddon alloc] initWithStore:store];
        [self refreshTouchbarsState];
    }
    return self;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!_busy) { [_touchbars reload]; [self refreshTouchbarsState]; [self.tableView reloadData]; }
}
- (void)refreshTouchbarsState {
    _touchbarsEnabled=_touchbars.enabled;
    _touchbarsCanToggle=_touchbars.canToggle;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView; return [@[@"wowf", @"wow"] containsObject:_product] ? 2 : 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; return section==0 ? 5 : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; return section==0 ? _edition : @"Optional touch addon";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section==1) {
        if (!_touchbarsCanToggle) return @"An existing Touchbars installation is managed separately. Review it in Manage addons before using this switch.";
        return @"Downloads Touchbars 0.7.0 by rollarz / Slashplayed contributors (MIT) on first use. Applies at the next game launch. Type /sptouch in WoW to assign, move and resize abilities. Empty buttons are initially hidden; the editor reveals them. Original game bars are hidden by default; restore them in More → Default bars. Wolkara controls stay unchanged. Turning this off keeps your saved layout.";
    }
    return @"Changes apply only to this edition, while the game is closed. Backups contain WTF and Interface, including settings and addons. Graphics are changed only when you request it.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if (indexPath.section==1) {
        cell.textLabel.text=_busy ? @"Please wait…" : @"Touchbars (experimental)";
        cell.accessibilityIdentifier=@"game.tools.touchbars";
        cell.selectionStyle=UITableViewCellSelectionStyleNone;
        UISwitch *toggle=[UISwitch new];
        toggle.accessibilityIdentifier=@"game.tools.touchbars.toggle";
        toggle.accessibilityLabel=@"Touchbars addon";
        toggle.on=_touchbarsEnabled; toggle.enabled=!_busy && _touchbarsCanToggle;
        [toggle addTarget:self action:@selector(toggleTouchbars:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView=toggle;
        return cell;
    }
    cell.textLabel.text=@[@"Manage addons", @"Back up settings and addons", @"Restore latest backup", @"Enable gamepad", @"Reset graphics settings"][indexPath.row];
    cell.accessibilityIdentifier=[NSString stringWithFormat:@"game.tools.%ld",(long)indexPath.row];
    cell.textLabel.enabled=!_busy;
    if (indexPath.row==0) cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)setOperationBusy:(BOOL)busy {
    // Cache model state only after the worker finishes; UIKit may ask for
    // cells during rotation while the install is still mutating the store.
    if (!busy) [self refreshTouchbarsState];
    _busy=busy; self.navigationItem.hidesBackButton=busy; self.modalInPresentation=busy;
    self.navigationController.interactivePopGestureRecognizer.enabled=!busy;
    [self.tableView reloadData];
}
- (void)toggleTouchbars:(UISwitch *)toggle {
    if (_busy) return;
    BOOL enabled=toggle.on;
    [self setOperationBusy:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;
        BOOL success=[self->_touchbars setEnabled:enabled error:&error];
        [self->_touchbars reload];
        dispatch_async(dispatch_get_main_queue(),^{
            [self setOperationBusy:NO];
            [self showResult:success ? (enabled ? @"Touchbars is ready for the next game launch. Type /sptouch to open its editor and assign abilities. If it does not appear, enable SPTouchBars in WoW's AddOns list."
                                                : @"Touchbars is off for the next game launch. Your saved layout is retained.")
                                     : error.localizedDescription ?: @"Touchbars could not be changed. Try again."];
        });
    });
}
- (void)showResult:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Game tools" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)performOperation:(NSInteger)operation {
    if (_busy) return;
    [self setOperationBusy:YES];
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
        [self->_touchbars reload];
        dispatch_async(dispatch_get_main_queue(),^{
            [self setOperationBusy:NO];
            [self showResult:error.localizedDescription ?: message ?: @"The operation could not finish."];
        });
    });
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_busy || indexPath.section!=0) return;
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
