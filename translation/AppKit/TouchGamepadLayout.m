#import "TouchGamepadLayout.h"
#include <math.h>

static NSString *const LayoutKey = @"WolkaraForeverTouchLayoutV1";
NSNotificationName const AKGamepadLayoutDidChangeNotification = @"AKGamepadLayoutDidChange";
static CGFloat Clamp(CGFloat value, CGFloat minimum, CGFloat maximum, CGFloat fallback) {
    return isfinite(value) ? MAX(minimum,MIN(maximum,value)) : fallback;
}
static CGFloat Number(id value, CGFloat fallback) {
    return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
}
@implementation AKGamepadLayout {
    NSUserDefaults *_defaults;
    NSString *_profileKey;
    BOOL _performanceDirty, _performanceOverlayEnabled;
    NSMutableDictionary *_positions;
    NSMutableDictionary *_toolbarPositions;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    return [self initWithDefaults:defaults simple:[defaults boolForKey:@"TKTouchGamepadSimple"]];
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults simple:(BOOL)simple {
    if ((self = [super init])) {
        _defaults = defaults;
        id saved = [defaults objectForKey:LayoutKey];
        // Import the former app's preferences once; current settings take priority.
        if (!saved) {
            id legacy = [defaults objectForKey:@"WowkaraTouchLayoutV1"];
            if ([legacy isKindOfClass:NSDictionary.class]) {
                saved = legacy;
                [defaults setObject:legacy forKey:LayoutKey];
            }
        }
        NSDictionary *legacy = [saved isKindOfClass:NSDictionary.class] ? saved : @{};
        // Seed BOTH profiles before either can be edited. Keep the old store for
        // rollback, including its identity-based simple.LB/simple.RB positions.
        for (NSString *mode in @[@"full",@"simple"]) {
            NSString *key = [@"WolkaraTouchLayoutV2." stringByAppendingString:mode];
            if (![defaults objectForKey:key]) [defaults setObject:legacy forKey:key];
        }
        _simple = simple;
        _profileKey = [@"WolkaraTouchLayoutV2." stringByAppendingString:simple?@"simple":@"full"];
        id profile = [defaults objectForKey:_profileKey];
        NSDictionary *values = [profile isKindOfClass:NSDictionary.class] ? profile : @{};
        self.opacity = Number(values[@"opacity"],0.8);
        self.rearScale = Number(values[@"rearScale"],1);
        self.frontScale = Number(values[@"frontScale"],1);
        self.hapticsEnabled = Number(values[@"hapticsEnabled"],1) != 0;
        // Keep existing layouts in their original order. New/reset layouts put
        // triggers inside; an explicit stored choice always takes precedence.
        self.swapShoulders = Number(values[@"swapShoulders"],values.count ? 0 : 1) != 0;
        _positions = [NSMutableDictionary new];
        id positions = values[@"positions"];
        if ([positions isKindOfClass:NSDictionary.class]) for (NSString *key in positions) {
            id point = positions[key];
            if (![key isKindOfClass:NSString.class] || ![point isKindOfClass:NSArray.class] || [point count] != 2) continue;
            CGFloat x = Number(point[0],NAN), y = Number(point[1],NAN);
            if (isfinite(x) && isfinite(y)) _positions[key] = @[@(Clamp(x,0,1,0)),@(Clamp(y,0,1,0))];
        }
        _toolbarPositions = [NSMutableDictionary new];
        id toolbar = values[@"toolbarPositions"];
        if ([toolbar isKindOfClass:NSDictionary.class]) for (NSString *key in toolbar) {
            id point = toolbar[key];
            if (![key isKindOfClass:NSString.class] || ![point isKindOfClass:NSArray.class] || ([point count] != 2 && [point count] != 3)) continue;
            CGFloat x = Number(point[0],NAN), y = Number(point[1],NAN);
            BOOL bottom = [point count] == 3 && Number(point[2],0) == 1;
            if (isfinite(x) && isfinite(y)) _toolbarPositions[key] = @[@(x),@(y),@(bottom)];
        }
    }
    return self;
}
- (BOOL)performanceOverlayEnabled {
    if (_performanceDirty) return _performanceOverlayEnabled;
    return Number([_defaults dictionaryForKey:LayoutKey][@"performanceOverlayEnabled"],0) != 0;
}
- (void)setPerformanceOverlayEnabled:(BOOL)value { _performanceOverlayEnabled = value; _performanceDirty = YES; }
- (void)setOpacity:(CGFloat)value { _opacity = Clamp(value,0.2,1,0.8); }
- (void)setRearScale:(CGFloat)value { _rearScale = Clamp(value,0.8,1.5,1); }
- (void)setFrontScale:(CGFloat)value { _frontScale = Clamp(value,0.65,1.4,1); }
- (CGRect)frameForItem:(NSString *)item defaultFrame:(CGRect)frame inBounds:(CGRect)bounds {
    CGFloat width = MAX(0,MIN(frame.size.width,bounds.size.width));
    CGFloat height = MAX(0,MIN(frame.size.height,bounds.size.height));
    CGFloat dx = MAX(0,bounds.size.width-width), dy = MAX(0,bounds.size.height-height);
    NSArray *point = _positions[item];
    CGFloat x = point ? [point[0] doubleValue]*dx : frame.origin.x-bounds.origin.x;
    CGFloat y = point ? [point[1] doubleValue]*dy : frame.origin.y-bounds.origin.y;
    return CGRectMake(bounds.origin.x+Clamp(x,0,dx,0),bounds.origin.y+Clamp(y,0,dy,0),width,height);
}
- (void)moveItem:(NSString *)item toFrame:(CGRect)frame inBounds:(CGRect)bounds {
    CGFloat dx = MAX(0,bounds.size.width-frame.size.width), dy = MAX(0,bounds.size.height-frame.size.height);
    CGFloat x = dx > 0 ? (frame.origin.x-bounds.origin.x)/dx : 0;
    CGFloat y = dy > 0 ? (frame.origin.y-bounds.origin.y)/dy : 0;
    _positions[item] = @[@(Clamp(x,0,1,0)),@(Clamp(y,0,1,0))];
}
- (void)storeToolbarFrames:(NSDictionary<NSString *,NSValue *> *)frames inBounds:(CGRect)bounds {
    [_toolbarPositions removeAllObjects];
    for (NSString *key in frames) {
        CGRect frame = frames[key].CGRectValue;
        BOOL bottom = CGRectGetMidY(frame) > CGRectGetMidY(bounds);
        CGFloat edge = bottom ? CGRectGetMaxY(bounds) : CGRectGetMinY(bounds);
        _toolbarPositions[key] = @[@(frame.origin.x-CGRectGetMidX(bounds)),@(frame.origin.y-edge),@(bottom)];
    }
}
- (NSDictionary<NSString *,NSValue *> *)framesForToolbar:(NSDictionary<NSString *,NSValue *> *)defaults inBounds:(CGRect)bounds {
    if (bounds.size.width <= 0 || bounds.size.height <= 0 || !defaults.count) return defaults;
    if (!_toolbarPositions.count) {
        // Old layouts stored each button as a fraction of the window. Resolve
        // that layout once, including untouched buttons, then retain its spacing.
        BOOL legacy = NO;
        for (NSString *key in defaults) if (_positions[key]) { legacy = YES; break; }
        if (!legacy) return defaults;
        NSMutableDictionary<NSString *,NSValue *> *frames = [NSMutableDictionary new];
        for (NSString *key in defaults)
            frames[key] = [NSValue valueWithCGRect:[self frameForItem:key defaultFrame:defaults[key].CGRectValue inBounds:bounds]];
        [self storeToolbarFrames:frames inBounds:bounds];
        [self save];
    }
    NSMutableDictionary<NSString *,NSValue *> *frames = [NSMutableDictionary new];
    CGRect group = CGRectNull;
    CGRect rows[2] = {CGRectNull,CGRectNull};
    for (NSString *key in defaults) {
        CGRect frame = defaults[key].CGRectValue;
        NSArray *point = _toolbarPositions[key];
        BOOL bottom = point && [point[2] boolValue];
        if (point) frame.origin = CGPointMake(CGRectGetMidX(bounds)+[point[0] doubleValue],
            (bottom ? CGRectGetMaxY(bounds) : CGRectGetMinY(bounds))+[point[1] doubleValue]);
        frames[key] = [NSValue valueWithCGRect:frame];
        group = CGRectUnion(group,frame);
        rows[bottom] = CGRectUnion(rows[bottom],frame);
    }
    // If a custom arrangement physically cannot fit, use the compact default
    // temporarily. Do not shrink targets, overlap buttons or overwrite it.
    if (group.size.width > bounds.size.width) return defaults;
    CGFloat dx = Clamp(0,CGRectGetMinX(bounds)-CGRectGetMinX(group),CGRectGetMaxX(bounds)-CGRectGetMaxX(group),0);
    CGFloat dy[2] = {0,0};
    // Controls near the bottom stay near the bottom, independently of the top
    // row. Resizing changes the empty space between rows, not within each row.
    for (NSUInteger row=0; row<2; row++) if (!CGRectIsNull(rows[row])) {
        if (rows[row].size.height > bounds.size.height) return defaults;
        dy[row] = Clamp(0,CGRectGetMinY(bounds)-CGRectGetMinY(rows[row]),CGRectGetMaxY(bounds)-CGRectGetMaxY(rows[row]),0);
        rows[row] = CGRectOffset(rows[row],dx,dy[row]);
    }
    if (!CGRectIsNull(rows[0]) && !CGRectIsNull(rows[1]) && CGRectIntersectsRect(rows[0],rows[1])) return defaults;
    for (NSString *key in defaults) {
        BOOL bottom = [_toolbarPositions[key][2] boolValue];
        frames[key] = [NSValue valueWithCGRect:CGRectOffset(frames[key].CGRectValue,dx,dy[bottom])];
    }
    return frames;
}
- (void)moveToolbarItem:(NSString *)item toFrame:(CGRect)frame currentFrames:(NSDictionary<NSString *,NSValue *> *)frames inBounds:(CGRect)bounds {
    if (!frames[item] || bounds.size.width <= 0 || bounds.size.height <= 0) return;
    frame.origin.x = Clamp(frame.origin.x,CGRectGetMinX(bounds),MAX(CGRectGetMinX(bounds),CGRectGetMaxX(bounds)-frame.size.width),CGRectGetMinX(bounds));
    frame.origin.y = Clamp(frame.origin.y,CGRectGetMinY(bounds),MAX(CGRectGetMinY(bounds),CGRectGetMaxY(bounds)-frame.size.height),CGRectGetMinY(bounds));
    NSMutableDictionary *moved = [frames mutableCopy];
    moved[item] = [NSValue valueWithCGRect:frame];
    [self storeToolbarFrames:moved inBounds:bounds];
}
- (void)save {
    [_defaults setObject:@{@"opacity":@(_opacity),@"rearScale":@(_rearScale),
        @"frontScale":@(_frontScale),@"hapticsEnabled":@(_hapticsEnabled),@"swapShoulders":@(_swapShoulders),
        @"positions":_positions,@"toolbarPositions":_toolbarPositions} forKey:_profileKey];
    // A save from an older layout object must not undo a HUD toggle elsewhere.
    if (_performanceDirty) {
        NSMutableDictionary *global = [[_defaults dictionaryForKey:LayoutKey] mutableCopy] ?: [NSMutableDictionary new];
        global[@"performanceOverlayEnabled"] = @(_performanceOverlayEnabled);
        [_defaults setObject:global forKey:LayoutKey]; _performanceDirty = NO;
    }
    [NSNotificationCenter.defaultCenter postNotificationName:AKGamepadLayoutDidChangeNotification object:_defaults];
}
- (void)reset {
    self.opacity = 0.8; self.rearScale = 1; self.frontScale = 1;
    self.hapticsEnabled = YES; self.swapShoulders = YES;
    [_positions removeAllObjects]; [_toolbarPositions removeAllObjects]; [self save];
}
@end
