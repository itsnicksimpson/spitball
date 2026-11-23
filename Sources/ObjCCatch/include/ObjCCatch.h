#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, turning an Objective-C exception into a Swift error.
/// AVAudioEngine and Core Audio raise NSExceptions (which Swift can't catch) when
/// hardware disappears mid-call, e.g. AirPods hopping to another device.
BOOL SBTry(NS_NOESCAPE void (^block)(void), NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
