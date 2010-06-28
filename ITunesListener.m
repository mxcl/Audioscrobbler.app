/***************************************************************************
 *   Copyright 2005-2009 Last.fm Ltd.                                      *
 *   Copyright 2010 Max Howell <max@methylblue.com>                        *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   51 Franklin Steet, Fifth Floor, Boston, MA  02110-1301, USA.          *
 ***************************************************************************/

#import "ITunesListener.h"
#import "HighResolutionTimer.h"
#import "iTunes.h"
#import "lastfm.h"
#import "NSDictionary+Track.h"
#import <Growl/GrowlApplicationBridge.h>
#import <time.h>

static time_t now()
{
    time_t t;
    time(&t);
    mktime(gmtime(&t));
    return t;
}


@implementation ITunesListener

-(id)initWithLastfm:(Lastfm*)lfm
{
    lastfm = [lfm retain];
    state = STATE_STOPPED;
    start_time = 0;
    itunes = [[SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"] retain];
    timer = [[HighResolutionTimer alloc] initWithTarget:self action:@selector(submit)];

    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(onPlayerInfo:)
                                                            name:@"com.apple.iTunes.playerInfo"
                                                          object:nil];

    if (itunes.isRunning && itunes.playerState == ITunesEPlSPlaying)
    {        
        ITunesTrack* t = itunes.currentTrack;
        
        unsigned long long pid;
        [[NSScanner scannerWithString:t.persistentID] scanHexLongLong:&pid];
        
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        [dict setObject:t.name forKey:@"Name"];
        [dict setObject:t.artist forKey:@"Artist"];
        [dict setObject:t.album forKey:@"Album"];
        [dict setObject:[NSNumber numberWithLongLong:((int64_t)t.duration)*1000] forKey:@"Total Time"];
        [dict setObject:@"Playing" forKey:@"Player State"];
        [dict setObject:[NSNumber numberWithLongLong:pid] forKey:@"PersistentID"];
        [self onPlayerInfo:[NSNotification notificationWithName:@"com.apple.iTunes.playerInfo"
                                                         object:nil
                                                       userInfo:dict]];
    }
    
    return self;
}

-(void)dealloc
{
    [timer release];
    [itunes release];
    [lastfm release];
    [super dealloc];
}


-(bool)transitionInvalid:(uint)transition
{
    switch (state) {
    case STATE_STOPPED:
        switch (transition) {
        case TrackStarted:
            return false;
        case PlaybackStopped:
        case TrackPaused:
        case TrackMetadataChanged:
        case TrackResumed:
            return true;
        }
    case STATE_PAUSED:
        switch (transition) {
        case PlaybackStopped:
        case TrackMetadataChanged:
        case TrackResumed:
        case TrackStarted:
            return false;
        case TrackPaused:
            return true;
        }
    case STATE_PLAYING:
        switch (transition) {
        case PlaybackStopped:
        case TrackPaused:
        case TrackMetadataChanged:
        case TrackStarted:
            return false;
        case TrackResumed:
            return true;
        }
    }
    return true;
}

-(void)announce:(uint)transition
{
    // TODO should apply to everything, no? Not just the UI announcement.
    if ([self transitionInvalid:transition])
        return;
    
    NSMutableDictionary* dict = [track mutableCopy];
    [dict setObject:[NSNumber numberWithUnsignedInt:transition] forKey:@"Transition"];
    
    NSNotification*notification = [NSNotification notificationWithName:@"playerInfo"
                                                                object:self
                                                              userInfo:dict];
    [[NSNotificationQueue defaultQueue] enqueueNotification:notification
                                               postingStyle:NSPostNow
                                               coalesceMask:NSNotificationCoalescingOnName
                                                   forModes:nil];
    [dict release];
}

-(void)submit
{
    [lastfm scrobble:track startTime:start_time];
}

-(void)start
{
    state = STATE_PLAYING;
    start_time = now();
    
    [timer scheduleWithTimeout:[Lastfm scrobblePointForTrackWithDurationInSeconds:track.duration]];

    // we wait a second so that we don't spam Last.fm and so that stuff like
    // Growl (for auth) doesn't fill the screen when you skip-skip-skip
    [NSObject cancelPreviousPerformRequestsWithTarget:lastfm];
    [lastfm performSelector:@selector(updateNowPlaying:) withObject:track afterDelay:2.0];

    [self announce:TrackStarted];
}

-(void)load_album_art
{
    @try {
        ITunesArtwork* art = (ITunesArtwork*)[itunes.currentTrack.artworks objectAtIndex:0];
        // NSImage is more useful, but Growl needs a TIFF and this way we
        // save on allocations, thus keeping our memory footprint down
        [track setObject:[[art data] TIFFRepresentation] forKey:@"Album Art"];
    }
    @catch(id e) {
        // for some reason [art exists] returns true, but it will still throw!
    }
}

-(void)amendMetadataIfAppropriate:(NSDictionary*)dict
{ 
    #define NOTEQUAL(x) ![[dict objectForKey:x] isEqualToString:[track objectForKey:x]]

    if (NOTEQUAL(@"Name") || NOTEQUAL(@"Artist") || NOTEQUAL(@"Album")) {
        track.artist = dict.artist;
        track.title = dict.title;
        track.album = dict.album;
        [self announce:TrackMetadataChanged];
    }

    #undef EQUAL
}

static void would_play_again_growl(NSDictionary* d)
{
    NSMutableDictionary* dict = [[d mutableCopy] autorelease];
    [dict setObject:ASGrowlLoveTrackQuery forKey:@"Notification Name"];
        
    [GrowlApplicationBridge notifyWithTitle:@"A+++++ Would Play Again!"
                                description:@"Click this notification to love this track at Last.fm"
                           notificationName:ASGrowlLoveTrackQuery
                                   iconData:nil
                                   priority:0
                                   isSticky:false
                               clickContext:dict];
}

static void ignore_growl(NSString* title, NSString* reason)
{
    [GrowlApplicationBridge notifyWithTitle:@"Will Not Scrobble"
                                description:[NSString stringWithFormat:@"“%@” is %@.", title, reason]
                           notificationName:ASGrowlTrackIgnored
                                   iconData:nil
                                   priority:0
                                   isSticky:false
                               clickContext:nil];
}

-(void)onPlayerInfo:(NSNotification*)note
{
    NSDictionary* newtrack = note.userInfo;
    
    switch (newtrack.playerState) {
    case STATE_PLAYING:
        if (itunes.currentTrack.podcast) {
            ignore_growl(newtrack.title, @"a podcast");
            goto stop;
        }
        if (![itunes.currentTrack.kind hasSuffix:@"audio file"]) {
            ignore_growl(newtrack.title, @"not music");
            goto stop;
        }

        if (track.pid != newtrack.pid) {
            [track release];
            track = [newtrack mutableCopy];
            [self load_album_art];
            [self start];
        }
        else if (state == STATE_PAUSED) {
            state = STATE_PLAYING;
            [timer resume];
            [self announce:TrackResumed];
        }
        else if ([track isEqualToTrack:newtrack]) {
            // user restarted the track that was already playing, probably
            [self start];
        }
        else {
            if (track.unrated && newtrack.rating >= 80)
                would_play_again_growl(newtrack);

            [self amendMetadataIfAppropriate:newtrack];
        }
        break;
    
    case STATE_PAUSED:
        state = STATE_PAUSED;
        [timer pause];
        [self announce:TrackPaused];
        break;

    case STATE_STOPPED:
    stop:
        [timer stop];
        state = STATE_STOPPED;
        [track release];
        track = nil;
        [self announce:PlaybackStopped];
        break;
    }
}

-(NSDictionary*)track
{
    return track;
}

@end
