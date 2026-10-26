#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const SDVirtualDisplayErrorDomain;

typedef NS_ERROR_ENUM(SDVirtualDisplayErrorDomain, SDVirtualDisplayError) {
    SDVirtualDisplayErrorUnavailable = 1,
    SDVirtualDisplayErrorInvalidArgument,
    SDVirtualDisplayErrorCreationFailed,
    SDVirtualDisplayErrorSettingsRejected,
    SDVirtualDisplayErrorPrivateAPIException,
};

/// Owns a temporary virtual display. This class never changes a physical display.
@interface SDVirtualDisplay : NSObject

/// Checks runtime API support without creating a display.
@property(class, nonatomic, readonly) BOOL available;

/// The CoreGraphics display identifier, or zero after invalidation.
@property(nonatomic, readonly) uint32_t displayID;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Creates a virtual display with a 2x backing buffer and stable identity.
/// The caller must verify the published CoreGraphics modes before using it.
- (nullable instancetype)initWithLogicalWidth:(NSUInteger)width
                                      height:(NSUInteger)height
                                 refreshRate:(double)hz
                                      serial:(uint32_t)serial
                                       error:(NSError * _Nullable * _Nullable)error
    NS_DESIGNATED_INITIALIZER;

/// Releases the virtual display. Safe to call more than once.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
