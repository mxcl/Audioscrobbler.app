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
#import "lastfm.h"
#import "iTunes.h"
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

static uint scrobble_time(uint duration)
{
    if (duration > 240*2) return 240;
    if (duration < 30*2) return 30;
    return duration/2;
}


@implementation ITunesListener

-(id)initWithLastfm:(Lastfm*)lfm
{
    lastfm = [lfm retain];
    start_time = pause_time = 0;
    state = STATE_STOPPED;
    itunes = [[SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"] retain];

    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(onPlayerInfo:)
                                                            name:@"com.apple.iTunes.playerInfo"
                                                          object:nil];
#if __AS_DEBUGGING__    
    if ([itunes isRunning] && itunes.playerState == ITunesEPlSPlaying)
    {
        ITunesTrack* t = itunes.currentTrack;
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        [dict setObject:t.name forKey:@"Name"];
        [dict setObject:t.artist forKey:@"Artist"];
        [dict setObject:t.album forKey:@"Album"];
        [dict setObject:[NSNumber numberWithLongLong:((int64_t)t.duration)*1000] forKey:@"Total Time"];
        [dict setObject:@"Playing" forKey:@"Player State"];
        [dict setObject:[NSNumber numberWithLongLong:1] forKey:@"PersistentID"];
        [self onPlayerInfo:[NSNotification notificationWithName:@"com.apple.iTunes.playerInfo"
                                                         object:nil
                                                       userInfo:dict]];
    }
#endif
    
    return self;
}

-(void)dealloc
{
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
    time_t time = now();

    if (state == STATE_PAUSED)
        pause_time = time - pause_time;

    uint const duration = [[track objectForKey:@"Total Time"] longLongValue] / 1000;
    uint const playtime = time - (start_time + pause_time);
    // we take off three seconds because durations often have a small error
    uint const scrobtime = scrobble_time(duration) - 3;

    if (playtime >= scrobtime)
        [lastfm scrobble:track startTime:start_time];
}

-(void)updateNowPlaying:(NSDictionary*)dict
{
    [lastfm updateNowPlaying:dict];
}

-(void)start
{
    [self announce:TrackStarted];

    state = STATE_PLAYING;

    pause_time = 0;
    start_time = now();

    // we wait a second so that we don't spam Last.fm and so that stuff like
    // Growl (for auth) doesn't fill the screen when you skip-skip-skip
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self performSelector:@selector(updateNowPlaying:) withObject:track afterDelay:1];
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

-(void)onPlayerInfo:(NSNotification*)note
{
    NSDictionary* newtrack = note.userInfo;

    //TODO test that a playlist of just one track on repeat scrobbles consistently
    
    switch (newtrack.playerState) {
    case STATE_PLAYING:
        if (track.pid != newtrack.pid) {
            [self submit];
            
            [track release];
            track = [newtrack mutableCopy];
            
            [self load_album_art];
            [self start];
        }
        else if (state == STATE_PAUSED) {
            [self announce:TrackResumed];
            state = STATE_PLAYING;
            pause_time = now() - pause_time;
        }
        else if ([track isEqualToTrack:newtrack]) {
            // user restarted the track that was already playing, probably
            [self submit];
            [self start];
        }
        else {
            if (track.unrated && newtrack.rating >= 80)
                would_play_again_growl(newtrack);

            [self amendMetadataIfAppropriate:newtrack];
        }
        break;
    
    case STATE_PAUSED:
        [self announce:TrackPaused];
        state = STATE_PAUSED;
        pause_time = now() - pause_time;
        break;

    case STATE_STOPPED:
        [self submit];
        [self announce:PlaybackStopped];
        state = STATE_STOPPED;
        [track release];
        track = nil;
        break;
    }
}

-(NSDictionary*)track
{
    return track;
}

@end
