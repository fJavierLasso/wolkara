#import "TouchActionLayout.h"
#include <math.h>

static NSString *const ActionsKey=@"WolkaraTouchAbilitiesV1";
static CGFloat Bounded(CGFloat x,CGFloat low,CGFloat high,CGFloat fallback) { return isfinite(x)?MAX(low,MIN(high,x)):fallback; }
static CGFloat Number(id value,CGFloat fallback) { return [value isKindOfClass:NSNumber.class]?[value doubleValue]:fallback; }
static NSString *DefaultGroup(NSString *identifier) {
    NSArray *parts=[identifier componentsSeparatedByString:@"."];
    if (parts.count==2 && [@[@"0",@"1",@"2",@"3"] containsObject:parts[0]]) {
        if ([@[@"up",@"right",@"down",@"left"] containsObject:parts[1]]) return [parts[0] stringByAppendingString:@".dpad"];
        if ([@[@"Y",@"B",@"A",@"X"] containsObject:parts[1]]) return [parts[0] stringByAppendingString:@".face"];
    }
    return identifier;
}
@implementation AKTouchAction
- (NSString *)label {
    NSString *prefix=@[@"",@"LT + ",@"RT + ",@"LT + RT + "][MIN(self.modifiers,3)];
    NSString *button=@{@"up":@"↑",@"right":@"→",@"down":@"↓",@"left":@"←"}[self.button]?:self.button;
    return [prefix stringByAppendingString:button];
}
@end

@implementation AKTouchActionLayout {
    NSUserDefaults *_defaults;
    NSMutableArray<AKTouchAction *> *_items;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self=[super init])) {
        _defaults=defaults; [self reset];
        id stored=[defaults objectForKey:ActionsKey];
        if (![stored isKindOfClass:NSDictionary.class]) return self;
        NSDictionary *saved=stored;
        _enabled=Number(saved[@"enabled"],0)!=0;
        self.scale=Number(saved[@"scale"],1); self.borderOpacity=Number(saved[@"border"],.16);
        self.center=CGPointMake(Number(saved[@"x"],.5),Number(saved[@"y"],700./900));
        id actions=saved[@"actions"];
        if (![actions isKindOfClass:NSArray.class] || [actions count]>64) return self;
        NSMutableArray *loaded=[NSMutableArray new]; NSMutableSet *ids=[NSMutableSet new];
        for (id item in actions) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSString *identifier=item[@"id"], *button=item[@"button"];
            if (![identifier isKindOfClass:NSString.class] || !identifier.length || identifier.length>80 ||
                [ids containsObject:identifier] || ![@[@"A",@"B",@"X",@"Y",@"LB",@"RB",@"up",@"right",@"down",@"left"] containsObject:button]) continue;
            AKTouchAction *a=[AKTouchAction new]; a.identifier=identifier; a.button=button;
            id group=item[@"group"];
            a.groupIdentifier=[group isKindOfClass:NSString.class] && [group length]>0 && [group length]<=80 ? group : DefaultGroup(identifier);
            a.modifiers=(NSUInteger)Bounded(Number(item[@"modifiers"],0),0,3,0);
            a.position=CGPointMake(Bounded(Number(item[@"x"],0),-1200,1200,0),Bounded(Number(item[@"y"],0),-900,900,0));
            a.diameter=Bounded(Number(item[@"diameter"],36),20,160,36); a.enabled=Number(item[@"enabled"],1)!=0;
            [loaded addObject:a]; [ids addObject:identifier];
        }
        _items=loaded;
    }
    return self;
}
- (NSArray<AKTouchAction *> *)actions { return _items.copy; }
- (void)setScale:(CGFloat)value { _scale=Bounded(value,.4,4,1); }
- (void)setBorderOpacity:(CGFloat)value { _borderOpacity=Bounded(value,0,.8,.16); }
- (void)setCenter:(CGPoint)value { _center=CGPointMake(Bounded(value.x,0,1,.5),Bounded(value.y,0,1,700./900)); }
- (void)reset {
    _enabled=NO; _scale=1; _borderOpacity=.16; _center=CGPointMake(.5,700./900); _items=[NSMutableArray new];
    // User's 1280x900 screenshot: neutral above, LT left, RT right, LT+RT below.
    // Each group has a D-pad diamond then a Y/B/A/X diamond. Coordinates are
    // relative to (640,700), preserving the photo's proportions as one block.
    const CGPoint centers[4][2]={{{565,631},{710,631}},{{388,689},{500,689}},{{777,689},{889,689}},{{582,747},{694,747}}};
    NSArray *keys=@[@"up",@"right",@"down",@"left",@"Y",@"B",@"A",@"X"];
    for (NSUInteger group=0;group<4;group++) for (NSUInteger i=0;i<8;i++) {
        CGPoint p=centers[group][i/4]; CGFloat dx=group?32:43,dy=group?18:23;
        if (i%4==0) p.y-=dy; else if (i%4==1) p.x+=dx; else if (i%4==2) p.y+=dy; else p.x-=dx;
        AKTouchAction *a=[AKTouchAction new]; a.identifier=[NSString stringWithFormat:@"%lu.%@",(unsigned long)group,keys[i]];
        a.groupIdentifier=DefaultGroup(a.identifier);
        a.button=keys[i]; a.modifiers=group; a.position=CGPointMake(p.x-640,p.y-700); a.diameter=group?32:42; a.enabled=YES;
        [_items addObject:a];
    }
}
- (CGRect)referenceBounds {
    CGRect result=CGRectNull;
    for (AKTouchAction *a in _items) result=CGRectUnion(result,CGRectMake(a.position.x-a.diameter/2,a.position.y-a.diameter/2,a.diameter,a.diameter));
    return CGRectIsNull(result)?CGRectMake(-16,-16,32,32):result;
}
- (CGFloat)unitScaleInBounds:(CGRect)bounds {
    if (bounds.size.width<=0 || bounds.size.height<=0) return 0;
    CGRect content=[self referenceBounds];
    return MAX(0,MIN(bounds.size.height/900*self.scale,MIN(MAX(0,bounds.size.width-8)/content.size.width,MAX(0,bounds.size.height-8)/content.size.height)));
}
- (CGPoint)originInBounds:(CGRect)bounds unit:(CGFloat)unit {
    CGRect content=[self referenceBounds];
    CGFloat x=CGRectGetMinX(bounds)+self.center.x*bounds.size.width,y=CGRectGetMinY(bounds)+self.center.y*bounds.size.height;
    x=MAX(CGRectGetMinX(bounds)+4-CGRectGetMinX(content)*unit,MIN(CGRectGetMaxX(bounds)-4-CGRectGetMaxX(content)*unit,x));
    y=MAX(CGRectGetMinY(bounds)+4-CGRectGetMinY(content)*unit,MIN(CGRectGetMaxY(bounds)-4-CGRectGetMaxY(content)*unit,y));
    return CGPointMake(x,y);
}
- (CGPoint)pointForPosition:(CGPoint)position inBounds:(CGRect)bounds {
    CGFloat unit=[self unitScaleInBounds:bounds]; CGPoint origin=[self originInBounds:bounds unit:unit];
    return CGPointMake(origin.x+position.x*unit,origin.y+position.y*unit);
}
- (CGRect)frameForAction:(AKTouchAction *)action inBounds:(CGRect)bounds {
    CGFloat diameter=action.diameter*[self unitScaleInBounds:bounds];
    CGPoint center=[self pointForPosition:action.position inBounds:bounds];
    return CGRectMake(center.x-diameter/2,center.y-diameter/2,diameter,diameter);
}
- (void)moveGroupBy:(CGPoint)delta inBounds:(CGRect)bounds {
    if (bounds.size.width<=0 || bounds.size.height<=0) return;
    CGFloat unit=[self unitScaleInBounds:bounds]; CGPoint p=[self originInBounds:bounds unit:unit];
    self.center=CGPointMake((p.x+delta.x-bounds.origin.x)/bounds.size.width,(p.y+delta.y-bounds.origin.y)/bounds.size.height);
    p=[self originInBounds:bounds unit:unit]; self.center=CGPointMake((p.x-bounds.origin.x)/bounds.size.width,(p.y-bounds.origin.y)/bounds.size.height);
}
- (void)moveAction:(AKTouchAction *)action by:(CGPoint)delta inBounds:(CGRect)bounds {
    if (action) [self moveActions:@[action] by:delta inBounds:bounds];
}
- (NSArray<AKTouchAction *> *)groupForAction:(AKTouchAction *)action {
    if (!action) return @[];
    NSMutableArray *group=[NSMutableArray new];
    for (AKTouchAction *item in _items) if ([item.groupIdentifier isEqual:action.groupIdentifier]) [group addObject:item];
    return group;
}
- (void)moveButtonGroupForAction:(AKTouchAction *)action by:(CGPoint)delta inBounds:(CGRect)bounds {
    [self moveActions:[self groupForAction:action] by:delta inBounds:bounds];
}
- (void)moveActions:(NSArray<AKTouchAction *> *)actions by:(CGPoint)delta inBounds:(CGRect)bounds {
    CGFloat unit=[self unitScaleInBounds:bounds]; if (unit<=0) return;
    CGRect frame=CGRectNull;
    for (AKTouchAction *item in actions) frame=CGRectUnion(frame,[self frameForAction:item inBounds:bounds]);
    if (CGRectIsNull(frame)) return;
    // Freeze the actual anchor before changing extents. Otherwise clamping an
    // edited group can silently translate the untouched groups too.
    CGPoint anchor=[self originInBounds:bounds unit:unit];
    self.center=CGPointMake((anchor.x-bounds.origin.x)/bounds.size.width,(anchor.y-bounds.origin.y)/bounds.size.height);
    CGFloat x=Bounded(frame.origin.x+delta.x,CGRectGetMinX(bounds)+4,CGRectGetMaxX(bounds)-frame.size.width-4,frame.origin.x);
    CGFloat y=Bounded(frame.origin.y+delta.y,CGRectGetMinY(bounds)+4,CGRectGetMaxY(bounds)-frame.size.height-4,frame.origin.y);
    for (AKTouchAction *item in actions) item.position=CGPointMake(item.position.x+(x-frame.origin.x)/unit,item.position.y+(y-frame.origin.y)/unit);
}
- (void)resizeButtonGroupForAction:(AKTouchAction *)action diameter:(CGFloat)diameter inBounds:(CGRect)bounds {
    NSArray *group=[self groupForAction:action]; CGFloat unit=[self unitScaleInBounds:bounds];
    if (!group.count || unit<=0) return;
    CGRect frame=CGRectNull; CGFloat low=0,high=INFINITY;
    for (AKTouchAction *item in group) {
        frame=CGRectUnion(frame,[self frameForAction:item inBounds:bounds]);
        low=MAX(low,20/item.diameter); high=MIN(high,160/item.diameter);
    }
    CGPoint middle=CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame));
    high=MIN(high,2*MIN(middle.x-CGRectGetMinX(bounds)-4,CGRectGetMaxX(bounds)-4-middle.x)/frame.size.width);
    high=MIN(high,2*MIN(middle.y-CGRectGetMinY(bounds)-4,CGRectGetMaxY(bounds)-4-middle.y)/frame.size.height);
    CGFloat factor=Bounded(diameter/action.diameter,low,high,1);
    CGPoint anchor=[self originInBounds:bounds unit:unit];
    self.center=CGPointMake((anchor.x-bounds.origin.x)/bounds.size.width,(anchor.y-bounds.origin.y)/bounds.size.height);
    CGPoint center=CGPointMake((middle.x-anchor.x)/unit,(middle.y-anchor.y)/unit);
    for (AKTouchAction *item in group) {
        item.position=CGPointMake(center.x+(item.position.x-center.x)*factor,center.y+(item.position.y-center.y)*factor);
        item.diameter*=factor;
    }
}
- (AKTouchAction *)addAction {
    if (_items.count>=64) return nil;
    AKTouchAction *a=[AKTouchAction new]; a.identifier=NSUUID.UUID.UUIDString; a.button=@"A"; a.diameter=36; a.enabled=YES;
    a.groupIdentifier=a.identifier;
    [_items addObject:a]; return a;
}
- (void)removeAction:(AKTouchAction *)action { if (action) [_items removeObject:action]; }
- (void)save {
    NSMutableArray *actions=[NSMutableArray new];
    for (AKTouchAction *a in _items) [actions addObject:@{@"id":a.identifier,@"group":a.groupIdentifier?:a.identifier,@"button":a.button,@"modifiers":@(a.modifiers),@"x":@(a.position.x),@"y":@(a.position.y),@"diameter":@(a.diameter),@"enabled":@(a.enabled)}];
    [_defaults setObject:@{@"enabled":@(self.enabled),@"scale":@(self.scale),@"border":@(self.borderOpacity),@"x":@(self.center.x),@"y":@(self.center.y),@"actions":actions} forKey:ActionsKey];
}
@end
