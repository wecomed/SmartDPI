#import "VirtualDisplayBridge.h"
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
#include <math.h>

NSErrorDomain const SDVirtualDisplayErrorDomain = @"com.smartdpi.virtual-display";

// These minimal declarations describe undocumented runtime selectors. Keeping
// class lookup dynamic lets a future macOS release fail without a link failure.
@protocol SDPrivateVirtualDescriptor <NSObject>
@property(nonatomic, strong) NSString *name;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int serialNumber;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) CGPoint redPrimary;
@property(nonatomic) CGPoint greenPrimary;
@property(nonatomic) CGPoint bluePrimary;
@property(nonatomic) CGPoint whitePoint;
@property(nonatomic, strong) id queue;
@end

@protocol SDPrivateVirtualMode <NSObject>
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@protocol SDPrivateVirtualSettings <NSObject>
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic, strong) NSArray *modes;
@end

@protocol SDPrivateVirtualDisplay <NSObject>
@property(nonatomic, readonly) unsigned int displayID;
- (instancetype)initWithDescriptor:(id<SDPrivateVirtualDescriptor>)descriptor;
- (BOOL)applySettings:(id<SDPrivateVirtualSettings>)settings;
@end

static BOOL SDHasSelectors(Class cls, NSArray<NSString *> *selectors) {
    if (cls == Nil) return NO;
    for (NSString *selector in selectors) {
        if (![cls instancesRespondToSelector:NSSelectorFromString(selector)]) return NO;
    }
    return YES;
}

static BOOL SDPrivateAPIAvailable(void) {
    return SDHasSelectors(NSClassFromString(@"CGVirtualDisplay"),
                          @[@"initWithDescriptor:", @"applySettings:", @"displayID"])
        && SDHasSelectors(NSClassFromString(@"CGVirtualDisplayDescriptor"),
                           @[@"init", @"setName:", @"setVendorID:", @"setProductID:",
                             @"setSerialNum:", @"setMaxPixelsWide:", @"setMaxPixelsHigh:",
                             @"setSizeInMillimeters:", @"setQueue:", @"setRedPrimary:",
                             @"setGreenPrimary:", @"setBluePrimary:", @"setWhitePoint:"])
        && SDHasSelectors(NSClassFromString(@"CGVirtualDisplaySettings"),
                           @[@"init", @"setHiDPI:", @"setModes:"])
        && SDHasSelectors(NSClassFromString(@"CGVirtualDisplayMode"),
                           @[@"initWithWidth:height:refreshRate:"]);
}

static void SDSetError(NSError **error, SDVirtualDisplayError code, NSString *message) {
    if (error != NULL) {
        *error = [NSError errorWithDomain:SDVirtualDisplayErrorDomain
                                    code:code
                                userInfo:@{NSLocalizedDescriptionKey: message}];
    }
}

@implementation SDVirtualDisplay {
    id<SDPrivateVirtualDisplay> _virtualDisplay;
    uint32_t _displayID;
}

+ (BOOL)available {
    @try {
        return SDPrivateAPIAvailable();
    } @catch (NSException *exception) {
        return NO;
    }
}

- (instancetype)initWithLogicalWidth:(NSUInteger)width
                              height:(NSUInteger)height
                         refreshRate:(double)hz
                              serial:(uint32_t)serial
                               error:(NSError **)error {
    self = [super init];
    if (self == nil) return nil;
    if (error != NULL) *error = nil;

    if (width == 0 || height == 0 || width > 3840 || height > 2160
        || !isfinite(hz) || hz < 1.0 || hz > 1000.0 || serial == 0) {
        SDSetError(error, SDVirtualDisplayErrorInvalidArgument,
                   @"Virtual display requires dimensions within 3840 × 2160, a refresh rate from 1 to 1000 Hz, and a nonzero serial number.");
        return nil;
    }

    @try {
        if (!SDPrivateAPIAvailable()) {
            SDSetError(error, SDVirtualDisplayErrorUnavailable,
                       @"This version of macOS does not provide the virtual display APIs required by SmartDPI.");
            return nil;
        }

        const unsigned int pixelWidth = (unsigned int)(width * 2);
        const unsigned int pixelHeight = (unsigned int)(height * 2);
        id<SDPrivateVirtualDescriptor> descriptor =
            [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        id<SDPrivateVirtualSettings> settings =
            [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        // Private API implementations expose different mode conventions. Supply
        // a backing-size anchor plus the logical size; the Swift caller must
        // verify both CGDisplayMode dimensions before touching a physical screen.
        id<SDPrivateVirtualMode> mode =
            [(id<SDPrivateVirtualMode>)[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:hz];
        id<SDPrivateVirtualMode> anchor =
            [(id<SDPrivateVirtualMode>)[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                initWithWidth:pixelWidth height:pixelHeight refreshRate:hz];
        if (descriptor == nil || settings == nil || mode == nil || anchor == nil) {
            SDSetError(error, SDVirtualDisplayErrorCreationFailed,
                       @"macOS could not allocate the virtual display configuration.");
            return nil;
        }

        descriptor.name = @"SmartDPI HiDPI";
        descriptor.vendorID = 0x5344;
        descriptor.productID = 0x5049;
        descriptor.serialNum = serial;
        if ([descriptor respondsToSelector:@selector(setSerialNumber:)]) {
            descriptor.serialNumber = serial;
        }
        descriptor.maxPixelsWide = pixelWidth;
        descriptor.maxPixelsHigh = pixelHeight;
        descriptor.sizeInMillimeters = CGSizeMake(pixelWidth * 25.4 / 220.0,
                                                  pixelHeight * 25.4 / 220.0);
        descriptor.queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        descriptor.redPrimary = CGPointMake(0.64, 0.33);
        descriptor.greenPrimary = CGPointMake(0.30, 0.60);
        descriptor.bluePrimary = CGPointMake(0.15, 0.06);
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290);

        settings.hiDPI = 1;
        settings.modes = @[anchor, mode];

        // Keep ownership until invalidation/deallocation; releasing this object
        // removes only its virtual display. No physical-display APIs are called.
        _virtualDisplay =
            [(id<SDPrivateVirtualDisplay>)[NSClassFromString(@"CGVirtualDisplay") alloc]
                initWithDescriptor:descriptor];
        if (_virtualDisplay == nil) {
            SDSetError(error, SDVirtualDisplayErrorCreationFailed,
                       @"macOS declined to create the virtual display.");
            return nil;
        }
        if (![_virtualDisplay applySettings:settings]) {
            // Chromium uses a single logical-size mode. Try that convention if
            // the OS declines the anchor list, while still requiring validation.
            settings.modes = @[mode];
            if (![_virtualDisplay applySettings:settings]) {
                [self invalidate];
                SDSetError(error, SDVirtualDisplayErrorSettingsRejected,
                           @"macOS rejected the requested virtual display mode.");
                return nil;
            }
        }
        _displayID = _virtualDisplay.displayID;
        if (_displayID == kCGNullDirectDisplay) {
            [self invalidate];
            SDSetError(error, SDVirtualDisplayErrorCreationFailed,
                       @"macOS created the virtual display without a usable identifier.");
            return nil;
        }
    } @catch (NSException *exception) {
        [self invalidate];
        SDSetError(error, SDVirtualDisplayErrorPrivateAPIException,
                   [NSString stringWithFormat:@"The macOS virtual display API failed (%@): %@",
                    exception.name, exception.reason ?: @"unknown reason"]);
        return nil;
    }
    return self;
}

- (uint32_t)displayID {
    @synchronized (self) {
        return _displayID;
    }
}

- (void)invalidate {
    @synchronized (self) {
        _displayID = kCGNullDirectDisplay;
        _virtualDisplay = nil;
    }
}

@end
