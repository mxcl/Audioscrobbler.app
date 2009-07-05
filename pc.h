//
// Prefix header for all source files of the 'Audioscrobbler' target in the 'Audioscrobbler' project
//

#ifdef __OBJC__
    #import <Cocoa/Cocoa.h>
#endif


// don't use these, make your own!
#define SCROBSUB_CLIENT_VERSION "2.0.0"
#define SCROBSUB_API_KEY "c8c7b163b11f92ef2d33ba6cd3c2c3c3"
#define SCROBSUB_SHARED_SECRET "73582dfc9e556d307aead069af110ab8"
#define SCROBSUB_CLIENT_ID "ass"
#define SCROBSUB_NO_RELAY 1


enum ASTransition{
    TrackStarted,
    TrackPaused,
    TrackResumed,
    PlaybackStopped,

    TrackMetadataChanged
};