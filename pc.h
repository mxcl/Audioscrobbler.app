//
// Prefix header for all source files of the 'Audioscrobbler' target in the 'Audioscrobbler' project
//

#ifdef __OBJC__
    #import <Cocoa/Cocoa.h>
#endif


enum ASState {
    StateStopped,
    StatePlaying,
    StatePaused,
    StateUnknown
};


#define ASGrowlTrackStarted @"Track Started"
#define ASGrowlTrackPaused @"Track Paused"
#define ASGrowlTrackResumed @"Track Resumed"
#define ASGrowlPlaylistEnded @"Playlist Ended"
#define ASGrowlSubmissionStatus @"Scrobble Submission Status"
#define ASGrowlLoveTrackQuery @"Love Track Query"
#define ASGrowlAuthenticationRequired @"Authentication Required"
#define ASGrowlErrorCommunication @"Error Communication"
#define ASGrowlCorrectionSuggestion @"Correction Suggestion"
#define ASGrowlTrackIgnored @"Track Ignored"
