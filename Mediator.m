/***************************************************************************
 *   Copyright 2005-2009 Last.fm Ltd.                                      *
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

// Created by Max Howell <max@last.fm>

#import "Mediator.h"
#import "scrobsub.h"
#import <Growl/GrowlApplicationBridge.h>
#import <time.h>

static time_t now()
{
    time_t t;
    time(&t);
    mktime(gmtime(&t));
    return t;
}

static Mediator* sharedMediator;


@implementation Mediator

-(void)awakeFromNib
{
    stack=[[NSMutableArray alloc] initWithCapacity:1];
    tracks=[[NSMutableDictionary alloc] initWithCapacity:1];
    sharedMediator = self;
    previous_start = 0;

    itunes=[ITunesListener alloc];
#if __AS_DEBUGGING__
    // ensure that all observers have registered before doing this
    [itunes performSelector:@selector(init) withObject:nil afterDelay:0];
#else
    [itunes init];
#endif
}

+(id)sharedMediator
{
    return sharedMediator;
}

-(void)announce:(NSDictionary*)track withTransition:(uint)transition
{
    NSMutableDictionary* dict = [[track mutableCopy] autorelease];
    [dict setObject:[NSNumber numberWithUnsignedInt:transition] forKey:@"Transition"];
    
    NSNotification*notification=[NSNotification notificationWithName:@"playerInfo"
                                                              object:self
                                                            userInfo:dict];
//    @try {
        [[NSNotificationQueue defaultQueue]enqueueNotification:notification
                                                  postingStyle:NSPostNow
                                                  coalesceMask:NSNotificationCoalescingOnName
                                                      forModes:nil];
//    }
//    @catch(NSException*e)
    {
        // don't allow exceptions to stop scrobub_start
    }
}

-(void)scrobsub_start:(NSDictionary*)dict
{
    if(!dict)return;
    
    #define nonullthx(x) NSString* ns##x=[dict objectForKey:@#x]; const char*x=!ns##x?"":[ns##x UTF8String];
    nonullthx(Artist);
    nonullthx(Name);
    
    scrobsub_start(Artist,
                   Name,
                   [(NSNumber*)[dict objectForKey:@"Total Time"] unsignedIntValue],
                   "",//[[dict objectForKey:@"Album"] UTF8String],
                   [(NSNumber*)[dict objectForKey:@"Track Number"] unsignedIntValue],
                   "");//[[dict objectForKey:@"MusicBrainz ID"] UTF8String]);
}

-(void)jig
{
    // a player just stopped or paused, find the next active connection

    for(NSString* o in stack){
        NSDictionary* track = [tracks objectForKey:o];
        if([[track objectForKey:@"Player State"] isEqualToString:@"Playing"]){
            active = o;           
            [self announce:track withTransition:TrackStarted];
            [self scrobsub_start:track];
            return;
        }
    }
}

-(IBAction)forceRejig:(id)sender
{
    [self jig];
}

-(void)scrobsub_start_active
{
    [self scrobsub_start:[tracks objectForKey:active]];
}

-(void)alreadyScrobblingGrowl:(NSDictionary*)track
{
    [GrowlApplicationBridge notifyWithTitle:@"Cannot Scrobble Multiple Tracks"
                                description:[NSString stringWithFormat:@"Pause %@ in order to scrobble “%@”.", active, [track objectForKey:@"Name"]]
                           notificationName:ASGrowlScrobbleMediationStatus
                                   iconData:nil
                                   priority:1
                                   isSticky:false
                               clickContext:nil
                                 identifier:ASGrowlScrobbleMediationStatus];
}

static void correct_empty(NSMutableDictionary* d, NSString* key)
{
    NSString* o = (NSString*)[d objectForKey:key];
    if(!o || [o length] == 0)
        [d setObject:@"[unknown]" forKey:key];
}

static void correct_metadata(NSMutableDictionary* d)
{
    if(![d objectForKey:@"Album"])
        [d setObject:@"" forKey:@"Album"]; //prevent crashes
    
    //TODO fingerprint and offer to correct
    correct_empty(d, @"Artist");
    correct_empty(d, @"Name");
}

-(void)start:(NSString*)id withTrack:(NSMutableDictionary*)track
{
    if(![stack containsObject:id])
        [stack addObject:id];
    
    time_t time = now();
    
    [tracks setObject:track forKey:id];
    [track setObject:@"Playing" forKey:@"Player State"];
    [track setObject:id forKey:@"Client ID"];
    [track setObject:[NSNumber numberWithUnsignedInt:time] forKey:@"Start Time"];

    correct_metadata(track);
    
    if(!active)
        active = id;
    if([active isEqualToString:id]){
        [self announce:track withTransition:TrackStarted];
        previous_start = time;

        // we wait 4 seconds so that we don't spam Last.fm and so that stuff
        // like Growl doesn't fill the screen when you skip-skip-skip
        if(time-previous_start < 4){
            [NSObject cancelPreviousPerformRequestsWithTarget:self];
            [self performSelector:@selector(scrobsub_start_active) withObject:nil afterDelay:4];
        }
        else
            [self scrobsub_start:track];
    }else
        [self alreadyScrobblingGrowl:[tracks objectForKey:id]];
}

-(void)pause:(NSString*)id
{
    if(![stack containsObject:id])
        NSLog(@"Invalid action: pausing an unknown player connection");
    else {
        [[tracks objectForKey:id] setObject:@"Paused" forKey:@"Player State"];
        if ([active isEqualToString:id]) {
            // jig the player stack, if we're still active then announce the pause
            [self jig];
            if([active isEqualToString:id]){
                scrobsub_pause();
                [self announce:[tracks objectForKey:active] withTransition:TrackPaused];
            }
        }
    }
}

-(void)resume:(NSString*)id
{
    if(![stack containsObject:id])
        NSLog(@"Invalid action: resuming an unknown player connection");
    else{
        NSMutableDictionary* track = [tracks objectForKey:id];
        [track setObject:@"Playing" forKey:@"Player State"];
        if([active isEqualToString:id]){
            [self announce:track withTransition:TrackResumed];
            scrobsub_resume();
        }
        else if(!active){
            active = id;
            [self announce:track withTransition:TrackStarted];
            [self scrobsub_start:track];
        }
        else
            [self alreadyScrobblingGrowl:[tracks objectForKey:id]];
    }
}

-(void)stop:(NSString*)id
{
    if(![stack containsObject:id])
        NSLog(@"Invalid action: resuming an unknown player connection");
    else{
        NSMutableDictionary* track = [tracks objectForKey:id];
        [track setObject:@"Stopped" forKey:@"Player State"];
        [track removeObjectForKey:@"Album Art"]; // save some mems
        if([id isEqualToString:active]){
            [self jig];
            if([id isEqualToString:active]){
                scrobsub_stop();
                [self announce:track withTransition:PlaybackStopped];
                active = nil;
            }
        }
    }
}

-(void)onScrobblingEnabledChanged:(id)sender
{
    //TODO
}

-(NSDictionary*)currentTrack
{
    return [tracks objectForKey:active];
}


-(void)changeMetadata:(NSString*)id
             forTrack:(NSString*)title
               artist:(NSString*)artist
                album:(NSString*)album
{
    if(!title)title=@"";
    if(!artist)artist=@"[unknown]";
    if(!album)album=@"[unknown]";    
    
    if(![stack containsObject:id])
        NSLog(@"Invalid action: resuming an unknown player connection");
    else{
        NSMutableDictionary* dict = [tracks objectForKey:id];
        
        if([artist isEqualToString:[dict objectForKey:@"Artist"]]
                    && [title isEqualToString:[dict objectForKey:@"Name"]]
                    && [album isEqualToString:[dict objectForKey:@"Album"]]){
            NSLog(@"Won't announce metadata changed as nothing important actually changed");
            return;
        }

        [dict setObject:title forKey:@"Name"];
        [dict setObject:artist forKey:@"Artist"];
        [dict setObject:album forKey:@"Album"];
        if([active isEqualToString:id]){
            [self announce:dict withTransition:TrackMetadataChanged];
            
            nonullthx(Artist);
            nonullthx(Album);
            nonullthx(Name);
            scrobsub_change_metadata(Artist, Name, Album);
        }
    }
}

-(bool)isEqualToCurrenTrack:(NSDictionary*)t
{
    NSDictionary* tt = [self currentTrack];
    NSNumber* pid = [t objectForKey:@"PersistentID"];
    if (pid && [pid isEqualToNumber:[tt objectForKey:@"PersistentID"]])
        return true;

    // no unique id so we have to fallback on this unsatisfactory method
    id a1 = [t objectForKey:@"Artist"];
    id a2 = [tt objectForKey:@"Artist"];
    id t1 = [t objectForKey:@"Artist"];
    id t2 = [tt objectForKey:@"Artist"];
    if ([a1 isEqualToString:a2] && [t1 isEqualToString:t2])
        return true;

    return false;
}

@end


@interface ASScriptCommand:NSScriptCommand{
}
@end

@implementation ASScriptCommand

-(id)performDefaultImplementation
{
    switch([[self commandDescription] appleEventCode]){
        case(FourCharCode)'strt':
            [[Mediator sharedMediator] start:[self directParameter] withTrack:[[[self evaluatedArguments] mutableCopy] autorelease]];
            break;
        case(FourCharCode)'paus':
            [[Mediator sharedMediator] pause:[self directParameter]];
            break;
        case(FourCharCode)'rsme':
            [[Mediator sharedMediator] resume:[self directParameter]];
            break;
        case(FourCharCode)'stop':
            [[Mediator sharedMediator] stop:[self directParameter]];
            break;
    }
    return nil;
}
@end


#import "iTunes.h"

@implementation ITunesListener

-(void)onPlayerInfo:(NSNotification*)userData
{
    NSString* state = [[userData userInfo] objectForKey:@"Player State"];

    if([state isEqualToString:@"Playing"]){        
        // pid may be the same as iTunes send this if the metadata is changed by
        // the user for instance
        //TODO if user restarts the track near the end we should count it is as scrobbled and start again
        //TODO if the user has a playlist that is just the track that should work too!
        int64_t const oldpid = pid;
        NSMutableDictionary* dict = [[[userData userInfo] mutableCopy] autorelease];
        pid = [[dict objectForKey:@"PersistentID"] longLongValue];
        bool const sametrack = oldpid == pid;
        
        if(sametrack){
            if(waspaused)
                [[Mediator sharedMediator] resume:@"iTunes"];
            else{
                // iTunes sends the "Playing" message if:
                //   1) a new track started
                //   2) the track was restarted
                //   3) the track metadata was altered
                // so this branch is a guess for (3)
                [[Mediator sharedMediator] changeMetadata:@"iTunes" 
                                                 forTrack:[dict objectForKey:@"Name"]
                                                   artist:[dict objectForKey:@"Artist"]
                                                    album:[dict objectForKey:@"Album"]];

                if([[dict objectForKey:@"Rating"] intValue] >= 80 && norating == true)
                {
                    NSMutableDictionary* md = [[dict mutableCopy] autorelease];
                    [md setObject:ASGrowlLoveTrackQuery forKey:@"Notification Name"];
                    [GrowlApplicationBridge notifyWithTitle:@"A+++++ Would Play Again!"
                                                description:@"Click this notification to love this track at Last.fm"
                                           notificationName:ASGrowlLoveTrackQuery
                                                   iconData:nil
                                                   priority:0
                                                   isSticky:false
                                               clickContext:md];
                }
            }
        }else{
            @try{
                // the following check saves quite some resources, the fetch
                // of album art is expensive, and seemingly the resident size of
                // our executable increases by 2MB everytime we fetch. 
                NSDictionary* oldtrack = [[Mediator sharedMediator] currentTrack];
                if([[oldtrack objectForKey:@"Album"] isEqualToString:[dict objectForKey:@"Album"]])
                    [dict setObject:[oldtrack objectForKey:@"Album Art"] forKey:@"Album Art"];
                else{                    
                    ITunesArtwork* art = (ITunesArtwork*)[itunes.currentTrack.artworks objectAtIndex:0];
                    // NSImage is more useful, but Growl needs a TIFF and this way we
                    // save on allocations, thus keeping our memory footprint down
                    [dict setObject:[[art data] TIFFRepresentation] forKey:@"Album Art"];
                }
            }@catch(id e){
                // for some reason [art exists] returns true, but it then throws :(
            }
            // computer ratings mean no rating is set, but they only occur if at
            // least one track on that album has a rating, otherwise Rating is 0
            norating = [[dict objectForKey:@"Rating"] intValue] == 0 || [[dict objectForKey:@"Rating Computed"] boolValue];
            
            uint const duration = [(NSNumber*)[dict objectForKey:@"Total Time"] longLongValue] / 1000;
            [dict setObject:[NSNumber numberWithUnsignedInt:duration] forKey:@"Total Time"];
            [dict setObject:@"iTunes" forKey:@"Player Name"];
            [[Mediator sharedMediator] start:@"iTunes" withTrack:dict];
        }
        waspaused = false;
    }else if([state isEqualToString:@"Paused"]){
        [[Mediator sharedMediator] pause:@"iTunes"];
        waspaused = true;
    }else if([state isEqualToString:@"Stopped"]){
        [[Mediator sharedMediator] stop:@"iTunes"];
        pid = 0;
        waspaused = false;
    }
}

-(id)init
{
    waspaused = false;
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(onPlayerInfo:)
                                                            name:@"com.apple.iTunes.playerInfo"
                                                          object:nil];
    itunes = [[SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"] retain];
    
#if __AS_DEBUGGING__
    if ([itunes isRunning] && itunes.playerState == ITunesEPlSPlaying)
    {
        ITunesTrack* t = itunes.currentTrack;
        NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
        [dict setObject:t.name forKey:@"Name"];
        [dict setObject:t.artist forKey:@"Artist"];
        [dict setObject:t.album forKey:@"Album"];
        [dict setObject:[NSNumber numberWithInteger:((int)(t.duration))*1000] forKey:@"Total Time"];
        [dict setObject:@"Playing" forKey:@"Player State"];
        [dict setObject:[NSNumber numberWithLongLong:1] forKey:@"PersistentID"];
        [self onPlayerInfo:[NSNotification notificationWithName:@"com.apple.iTunes.playerInfo"
                                                         object:nil
                                                       userInfo:dict]];
    }
#endif
    
    return self;
}

@end
