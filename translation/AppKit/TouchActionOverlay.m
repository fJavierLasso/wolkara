#import "TouchActionOverlay.h"
#import "TouchGamepad.h"
#include <math.h>

@class AKActionCircle;
@interface AKTouchActionOverlay (Tracking)
- (void)up:(AKActionCircle *)circle;
- (void)updateAppearance;
@end
@interface AKActionCircle : UIButton
@property(nonatomic, strong) AKTouchAction *action;
@property(nonatomic) BOOL inputHeld;
@property(nonatomic, weak) AKTouchActionOverlay *owner;
- (void)cancelPendingTouch;
@end
@implementation AKActionCircle {
    __weak UITouch *_finger;
    CGPoint _origin;
    BOOL _dragged, _forwarded;
}
- (void)layoutSubviews {
    [super layoutSubviews]; self.layer.cornerRadius=self.bounds.size.width/2; self.clipsToBounds=YES;
}
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event {
    (void)event; return hypot(p.x-self.bounds.size.width/2,p.y-self.bounds.size.height/2)<=self.bounds.size.width/2;
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    if (_finger || self.owner.editing || !self.owner.active || !self.owner.layout.enabled || !self.action.enabled) return NO;
    _finger=touch; _origin=[touch locationInView:self.owner]; _dragged=NO; _forwarded=NO;
    self.inputHeld=YES; [self.owner updateAppearance]; return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event; if (touch!=_finger) return NO;
    CGPoint point=[touch locationInView:self.owner];
    if (!_dragged && hypot(point.x-_origin.x,point.y-_origin.y)>=AKTouchDragThreshold) {
        _dragged=YES; self.inputHeld=NO; [self.owner updateAppearance];
        _forwarded=self.owner.beginDrag && self.owner.beginDrag(touch,_origin);
    }
    if (_forwarded && self.owner.moveDrag) self.owner.moveDrag(touch);
    return YES; // Keep the drag after the finger leaves the circle.
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (touch!=_finger) return;
    CGPoint point=[touch locationInView:self.owner];
    BOOL tap=!_dragged && hypot(point.x-_origin.x,point.y-_origin.y)<AKTouchDragThreshold &&
             [self pointInside:[touch locationInView:self] withEvent:event];
    if (_forwarded && self.owner.endDrag) self.owner.endDrag(touch,NO);
    _finger=nil; _forwarded=NO; self.inputHeld=NO; [self.owner updateAppearance];
    if (tap) [self.owner up:self]; // Leave rejection feedback visible after lift.
}
- (void)cancelPendingTouch {
    if (_forwarded && _finger && self.owner.endDrag) self.owner.endDrag(_finger,YES);
    _finger=nil; _forwarded=NO; self.inputHeld=NO;
}
- (void)cancelTrackingWithEvent:(UIEvent *)event { (void)event; [self cancelPendingTouch]; [self.owner updateAppearance]; }
- (BOOL)accessibilityActivate {
    if (self.owner.editing || !self.owner.active || !self.action.enabled) return NO;
    [self.owner up:self]; return YES;
}
@end

@interface AKTouchActionOverlay () <UIGestureRecognizerDelegate>
@end
@implementation AKTouchActionOverlay {
    NSMutableArray<AKActionCircle *> *_circles;
    AKTouchAction *_selected;
    UIView *_panel;
    UISegmentedControl *_mode;
    UISlider *_size, *_border;
    UISwitch *_enabled, *_shown;
    UILabel *_sizeLabel, *_selectionLabel;
    UIButton *_binding, *_modifier;
    UIStackView *_bindingRow;
    CGFloat _pinchInitial;
    CGSize _lastViewportSize;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.multipleTouchEnabled=YES;
        _layout=[[AKTouchActionLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults simple:NO];
        [self rebuildCircles];
        UIPinchGestureRecognizer *pinch=[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
        pinch.delegate=self; [self addGestureRecognizer:pinch];
    }
    return self;
}
- (void)selectSimpleLayout:(BOOL)simple {
    if (_layout.simple==simple) return;
    [self finishEditing]; [self releaseTouches]; [_layout save];
    _layout=[[AKTouchActionLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults simple:simple];
    _selected=nil; [self rebuildCircles];
}
- (CGRect)placementBounds { return self.bounds; } // Same viewport as the game's UI, including its bottom anchor.
- (void)rebuildCircles {
    [self releaseTouches];
    for (UIView *view in _circles) [view removeFromSuperview];
    _circles=[NSMutableArray new];
    for (AKTouchAction *action in self.layout.actions) {
        AKActionCircle *circle=[AKActionCircle buttonWithType:UIButtonTypeCustom]; circle.action=action; circle.owner=self;
        circle.exclusiveTouch=NO; circle.titleLabel.font=[UIFont systemFontOfSize:9 weight:UIFontWeightBold];
        circle.titleLabel.numberOfLines=2; circle.titleLabel.textAlignment=NSTextAlignmentCenter;
        circle.accessibilityIdentifier=[@"wolkara.ability." stringByAppendingString:action.identifier];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        pan.delegate=self; [circle addGestureRecognizer:pan];
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(selectCircle:)];
        tap.delegate=self; [circle addGestureRecognizer:tap]; [tap requireGestureRecognizerToFail:pan];
        [self addSubview:circle]; [_circles addObject:circle];
    }
    if (_panel) [self bringSubviewToFront:_panel];
    [self updateAppearance];
}
- (void)setActive:(BOOL)active {
    if (_active && !active) [self releaseTouches]; _active=active; [self updateAppearance];
}
- (void)updateAppearance {
    self.hidden=!self.editing && (!self.active || !self.layout.enabled);
    for (AKActionCircle *circle in _circles) {
        BOOL selected=circle.action==_selected || (_mode.selectedSegmentIndex==1 && [circle.action.groupIdentifier isEqual:_selected.groupIdentifier]);
        circle.hidden=!self.editing && !circle.action.enabled;
        circle.layer.borderWidth=self.editing?2:(self.layout.borderOpacity>0?1:0);
        circle.layer.borderColor=(self.editing?(selected?UIColor.systemYellowColor:UIColor.systemCyanColor):
            [UIColor.whiteColor colorWithAlphaComponent:self.layout.borderOpacity]).CGColor;
        circle.backgroundColor=circle.inputHeld?[UIColor.systemCyanColor colorWithAlphaComponent:.25]:UIColor.clearColor;
        circle.alpha=self.editing && !circle.action.enabled?.35:1;
        [circle setTitle:self.editing?circle.action.label:@"" forState:UIControlStateNormal];
        circle.accessibilityLabel=circle.action.label;
        circle.accessibilityValue=circle.action.enabled?@"Enabled":@"Hidden";
    }
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGSizeEqualToSize(_lastViewportSize,self.bounds.size)) {
        _lastViewportSize=self.bounds.size; [self releaseTouches];
    }
    for (AKActionCircle *circle in _circles) {
        circle.frame=[self.layout frameForAction:circle.action inBounds:[self placementBounds]];
        circle.layer.cornerRadius=circle.bounds.size.width/2;
    }
    if (_panel) {
        CGRect safe=UIEdgeInsetsInsetRect(self.bounds,self.safeAreaInsets);
        CGFloat width=MIN(760,safe.size.width-16),height=MIN(176,safe.size.height*.44);
        _panel.frame=CGRectMake(CGRectGetMidX(safe)-width/2,CGRectGetMinY(safe)+50,width,height);
    }
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event]; return hit==self?nil:hit;
}
- (BOOL)editorContainsPoint:(CGPoint)point inView:(UIView *)view {
    return self.editing && CGRectContainsPoint(_panel.bounds,[_panel convertPoint:point fromView:view]);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (!self.editing) return NO;
    if ([gesture isKindOfClass:UIPinchGestureRecognizer.class])
        return ![self editorContainsPoint:[gesture locationInView:self] inView:self];
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    (void)gesture;
    return self.editing && (!_panel || ![touch.view isDescendantOfView:_panel]);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    (void)a; (void)b; return NO;
}
- (void)up:(AKActionCircle *)circle {
    if (self.editing || !self.active || !self.layout.enabled || !circle.action.enabled) return;
    BOOL accepted=self.press && self.press(circle.action);
    if (accepted && self.released) self.released(circle.action);
    [self updateAppearance];
    if (!accepted) {
        // Reject an incompatible chord visibly, without typing a different shortcut.
        circle.layer.borderWidth=2; circle.layer.borderColor=UIColor.systemOrangeColor.CGColor;
    }
}
- (void)releaseTouches {
    if (self.cancelledAll) self.cancelledAll();
    for (AKActionCircle *circle in _circles) [circle cancelPendingTouch];
    [self updateAppearance];
}
- (void)selectCircle:(UITapGestureRecognizer *)tap {
    if (!self.editing || tap.state!=UIGestureRecognizerStateEnded) return;
    _selected=((AKActionCircle *)tap.view).action; [self updateEditor];
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    if (!self.editing) return;
    AKTouchAction *action=((AKActionCircle *)pan.view).action;
    if (pan.state==UIGestureRecognizerStateBegan) _selected=action;
    CGPoint delta=[pan translationInView:self];
    if (_mode.selectedSegmentIndex==0) [self.layout moveGroupBy:delta inBounds:[self placementBounds]];
    else if (_mode.selectedSegmentIndex==1) [self.layout moveButtonGroupForAction:action by:delta inBounds:[self placementBounds]];
    else [self.layout moveAction:action by:delta inBounds:[self placementBounds]];
    [pan setTranslation:CGPointZero inView:self]; [self updateEditor];
    if (pan.state==UIGestureRecognizerStateEnded || pan.state==UIGestureRecognizerStateCancelled) [self.layout save];
}
- (void)pinch:(UIPinchGestureRecognizer *)pinch {
    if (!self.editing) return;
    BOOL group=_mode.selectedSegmentIndex==0;
    if (pinch.state==UIGestureRecognizerStateBegan) _pinchInitial=group?self.layout.scale:_selected.diameter;
    if (group) self.layout.scale=_pinchInitial*pinch.scale;
    else if (_mode.selectedSegmentIndex==1) [self.layout resizeButtonGroupForAction:_selected diameter:_pinchInitial*pinch.scale inBounds:[self placementBounds]];
    else if (_selected) _selected.diameter=MAX(20,MIN(160,_pinchInitial*pinch.scale));
    [self updateEditor];
    if (pinch.state==UIGestureRecognizerStateEnded || pinch.state==UIGestureRecognizerStateCancelled) [self.layout save];
}
- (UILabel *)label:(NSString *)text {
    UILabel *label=[UILabel new]; label.text=text; label.textColor=UIColor.whiteColor;
    label.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium]; label.numberOfLines=2; return label;
}
- (UIButton *)button:(NSString *)title action:(SEL)action identifier:(NSString *)identifier {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:title forState:UIControlStateNormal];
    button.accessibilityIdentifier=identifier; [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (UIStackView *)row:(NSArray<UIView *> *)views {
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:views]; row.axis=UILayoutConstraintAxisHorizontal;
    row.spacing=10; row.alignment=UIStackViewAlignmentCenter; return row;
}
- (void)beginEditing {
    if (self.editing) return;
    [self releaseTouches]; _editing=YES; _selected=self.layout.actions.firstObject;
    _panel=[UIView new]; _panel.backgroundColor=[UIColor colorWithRed:.06 green:.08 blue:.11 alpha:1];
    _panel.layer.cornerRadius=14; _panel.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    _panel.accessibilityIdentifier=@"wolkara.abilities.editor"; [self addSubview:_panel];
    UIScrollView *scroll=[UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO; [_panel addSubview:scroll];
    UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=8;
    stack.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:stack];
    _enabled=[UISwitch new]; _enabled.on=self.layout.enabled; _enabled.accessibilityLabel=@"Touch abilities";
    _enabled.accessibilityIdentifier=@"wolkara.abilities.enabled";
    [_enabled addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    UIButton *done=[self button:@"Done" action:@selector(finishEditing) identifier:@"wolkara.abilities.done"];
    UILabel *title=[self label:@"Touch abilities"]; title.numberOfLines=1;
    [title setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [stack addArrangedSubview:[self row:@[title,_enabled,
        [self button:@"Add" action:@selector(addCircle) identifier:@"wolkara.abilities.add"],
        [self button:@"Reset" action:@selector(resetLayout) identifier:@"wolkara.abilities.reset"]]]];
    _mode=[[UISegmentedControl alloc] initWithItems:@[@"Whole layout",@"Group of 4",@"One circle"]]; _mode.selectedSegmentIndex=0;
    _mode.accessibilityIdentifier=@"wolkara.abilities.mode";
    [_mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:_mode];
    _sizeLabel=[self label:@"Size"];
    [_sizeLabel.widthAnchor constraintEqualToConstant:105].active=YES;
    _size=[UISlider new]; _size.accessibilityIdentifier=@"wolkara.abilities.size";
    [_size addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:[self row:@[_sizeLabel,_size]]];
    _binding=[UIButton buttonWithType:UIButtonTypeSystem]; _binding.showsMenuAsPrimaryAction=YES;
    _binding.accessibilityIdentifier=@"wolkara.abilities.binding";
    _modifier=[UIButton buttonWithType:UIButtonTypeSystem]; _modifier.showsMenuAsPrimaryAction=YES;
    _modifier.accessibilityIdentifier=@"wolkara.abilities.modifier";
    _shown=[UISwitch new]; _shown.accessibilityLabel=@"Circle enabled";
    [_shown addTarget:self action:@selector(shownChanged:) forControlEvents:UIControlEventValueChanged];
    _bindingRow=[self row:@[_binding,_modifier,_shown,[self button:@"Delete" action:@selector(deleteCircle) identifier:@"wolkara.abilities.delete"]]];
    [stack addArrangedSubview:_bindingRow];
    _border=[UISlider new]; _border.minimumValue=0; _border.maximumValue=.8; _border.value=self.layout.borderOpacity;
    _border.accessibilityLabel=@"Circle border opacity";
    [_border addTarget:self action:@selector(borderChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:[self row:@[[self label:@"Borders"],_border]]];
    _selectionLabel=[self label:@""]; [stack addArrangedSubview:_selectionLabel];
    done.translatesAutoresizingMaskIntoConstraints=NO; [_panel addSubview:done];
    [NSLayoutConstraint activateConstraints:@[
        [done.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-12], [done.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:4],
        [done.widthAnchor constraintEqualToConstant:64], [done.heightAnchor constraintEqualToConstant:40],
        [scroll.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:12], [scroll.trailingAnchor constraintEqualToAnchor:done.leadingAnchor constant:-8],
        [scroll.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:8], [scroll.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor constant:-8],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    [self updateEditor]; if (self.configurationChanged) self.configurationChanged();
}
- (void)updateEditor {
    if (!self.editing) return;
    BOOL group=_mode.selectedSegmentIndex==0;
    _size.minimumValue=group?.4:20; _size.maximumValue=group?4:160;
    _size.value=group?self.layout.scale:_selected.diameter; _size.enabled=group || _selected!=nil;
    BOOL quad=_mode.selectedSegmentIndex==1;
    _sizeLabel.text=group?[NSString stringWithFormat:@"Layout %.0f%%",self.layout.scale*100]:[NSString stringWithFormat:quad?@"Group %.0f":@"Circle %.0f",_selected.diameter];
    _size.accessibilityLabel=group?@"Whole layout scale":quad?@"Button group size":@"Circle diameter";
    _size.accessibilityValue=_sizeLabel.text; _bindingRow.hidden=group || quad || !_selected;
    _selectionLabel.text=group?@"Drag any circle to move all. Pinch or use Size to scale the block.":quad?@"Drag a circle to move its group. Pinch or use Size to resize the group.":@"Tap a circle to select it. Drag to move; pinch or use Size to resize.";
    [_binding setTitle:[@"Button: " stringByAppendingString:_selected.button?:@"—"] forState:UIControlStateNormal];
    NSArray *modifiers=@[@"None",@"LT",@"RT",@"LT + RT"];
    [_modifier setTitle:modifiers[MIN(_selected.modifiers,3)] forState:UIControlStateNormal];
    _shown.on=_selected.enabled;
    __weak AKTouchActionOverlay *weakSelf=self;
    NSMutableArray *buttons=[NSMutableArray new],*mods=[NSMutableArray new];
    for (NSString *key in @[@"A",@"B",@"X",@"Y",@"LB",@"RB",@"up",@"right",@"down",@"left"]) {
        UIAction *action=[UIAction actionWithTitle:key image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a; AKTouchActionOverlay *self=weakSelf; if (!self) return; self->_selected.button=key; [self updateEditor];
        }]; action.state=[_selected.button isEqual:key]?UIMenuElementStateOn:UIMenuElementStateOff; [buttons addObject:action];
    }
    for (NSUInteger i=0;i<4;i++) {
        UIAction *action=[UIAction actionWithTitle:modifiers[i] image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a; AKTouchActionOverlay *self=weakSelf; if (!self) return; self->_selected.modifiers=i; [self updateEditor];
        }]; action.state=_selected.modifiers==i?UIMenuElementStateOn:UIMenuElementStateOff; [mods addObject:action];
    }
    _binding.menu=[UIMenu menuWithChildren:buttons]; _modifier.menu=[UIMenu menuWithChildren:mods];
    [self updateAppearance];
}
- (void)modeChanged { [self releaseTouches]; [self updateEditor]; }
- (void)enabledChanged:(UISwitch *)sender { [self releaseTouches]; self.layout.enabled=sender.on; [self updateAppearance]; }
- (void)shownChanged:(UISwitch *)sender { _selected.enabled=sender.on; [self updateEditor]; }
- (void)borderChanged:(UISlider *)sender { self.layout.borderOpacity=sender.value; }
- (void)sizeChanged:(UISlider *)sender {
    if (_mode.selectedSegmentIndex==0) self.layout.scale=sender.value;
    else if (_mode.selectedSegmentIndex==1) [self.layout resizeButtonGroupForAction:_selected diameter:sender.value inBounds:[self placementBounds]];
    else _selected.diameter=sender.value;
    [self updateEditor];
}
- (void)addCircle {
    AKTouchAction *added=[self.layout addAction]; if (!added) return;
    _selected=added; _mode.selectedSegmentIndex=2; [self rebuildCircles]; [self updateEditor];
}
- (void)deleteCircle { [self.layout removeAction:_selected]; _selected=self.layout.actions.firstObject; [self rebuildCircles]; [self updateEditor]; }
- (void)resetLayout {
    BOOL enabled=self.layout.enabled; [self.layout reset]; self.layout.enabled=enabled; _selected=self.layout.actions.firstObject;
    _border.value=self.layout.borderOpacity; [self rebuildCircles]; [self updateEditor];
}
- (void)finishEditing {
    if (!self.editing) return;
    [self releaseTouches]; [self.layout save]; _editing=NO; [_panel removeFromSuperview]; _panel=nil;
    [self updateAppearance]; if (self.configurationChanged) self.configurationChanged();
}
@end
