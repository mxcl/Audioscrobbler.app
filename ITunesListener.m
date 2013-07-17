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
#import <time.h>

static time_t now()
{
    time_t t;
    time(&t);
    mktime(gmtime(&t));
    return t;
}


// Can't make this a category sadly, due to ScriptingFramework oddness
static NSData* itunes_current_track_artwork_as_data(ITunesApplication* itunes)
{
    @try {
        ITunesArtwork* iart = [itunes.currentTrack.artworks objectAtIndex:0];
        // NSImage is more useful, but Growl needs a TIFF and this way we
        // save on allocations, thus keeping our memory footprint down
        return [iart.data.TIFFRepresentation retain];
    }
    @catch(id e) {
        NSLog(@"%@", e);
        // seems to throw sometimes even if we check for the right stuff first
    }
    return nil;
}


@implementation ITunesListener

-(id)initWithLastfm:(Lastfm*)lfm delegate:(id)helegate
{
    self = [self init];
    delegate = helegate;
    lastfm = [lfm retain];
    state = StateStopped;
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
    [track release];
    [art release];
    [super dealloc];
}

-(void)submit
{
    [lastfm scrobble:track startTime:start_time];
}

-(void)amendMetadataIfAppropriate:(NSDictionary*)dict
{ 
    #define NOTEQUAL(x) ![[dict objectForKey:x] isEqualToString:[track objectForKey:x]]

    if (NOTEQUAL(@"Name") || NOTEQUAL(@"Artist") || NOTEQUAL(@"Album")) {
        track.artist = dict.artist;
        track.title = dict.title;
        track.album = dict.album;
        [delegate iTunesTrackMetadataUpdated:track];
    }

    #undef EQUAL
}

-(void)onPlayerInfo:(NSNotification*)note
{
    NSDictionary* newtrack = note.userInfo;
    
    switch (newtrack.playerState) {
    case StatePlaying:
        if (itunes.currentTrack.podcast) {
            [delegate iTunesWontScrobble:newtrack because:@"a podcast"];
            goto stop;
        }
        if (![itunes.currentTrack.kind hasSuffix:@"audio file"]) {
            [delegate iTunesWontScrobble:newtrack because:@"not music"];
            goto stop;
        }

        if (track.pid != newtrack.pid) {
            [track release];
            [art release];
            track = [newtrack mutableCopy];
            art = itunes_current_track_artwork_as_data(itunes);
            goto start;
        }
        else if (state == StatePaused) {
            state = StatePlaying;
            [timer resume];
            [delegate iTunesTrackResumed:track art:art];
        }
        else if ([track isEqualToDictionary:newtrack]) {
            // user restarted the track that was already playing, probably
            goto start;
        }
        else {
            [self amendMetadataIfAppropriate:newtrack];

            if (track.unrated && newtrack.rating >= 80) {
                track.rating = newtrack.rating;
                [delegate iTunesTrackWasRatedFourStarsOrAbove:track];
            }
        }
        break;
            
    start:
        state = StatePlaying;
        start_time = now();
        
        [timer scheduleWithTimeout:[Lastfm scrobblePointForTrackWithDurationInSeconds:track.duration]];
        
        // we wait a bit so that we don't spam Last.fm when you skip-skip-skip
        [NSObject cancelPreviousPerformRequestsWithTarget:lastfm];
        [lastfm performSelector:@selector(updateNowPlaying:) withObject:track afterDelay:2.0];
        
        [delegate iTunesTrackStarted:track art:art];
        break;

    case StatePaused:
        if (state == StatePaused || state == StateStopped)
            break;
        state = StatePaused;
        [timer pause];
        [delegate iTunesTrackPaused:track];
        break;

    case StateStopped:
    stop:
        if (state == StateStopped)
            break;
        state = StateStopped;
        [timer stop];
        [track release];
        [art release];
        track = nil;
        art = nil;
        [delegate iTunesPlaybackStopped];
        break;
    }
}

@synthesize track;

@end
