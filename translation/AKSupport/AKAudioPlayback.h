// Host/adapter notification boundary. Only the host owns AVAudioSession.
#import <Foundation/Foundation.h>
static NSString *const AKGameAudioRecovered = @"TKGameAudioPlaybackRecovered";
static NSString *const AKGameAudioGainChanged = @"TKGameAudioGainChanged";
