#import "ObjCCatch.h"

BOOL SBTry(NS_NOESCAPE void (^block)(void), NSError * _Nullable * _Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *e) {
        if (error) {
            *error = [NSError errorWithDomain:@"Spitball.ObjCException" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""]}];
        }
        return NO;
    }
}
