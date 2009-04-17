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
#import <time.h>

static NSNumber* now()
{
    time_t t;
    time(&t);
    mktime(gmtime(&t));
    return [NSNumber numberWithUnsignedInt:t];    
}


@implementation Mediator

-(id)init
{
    stack=[[NSMutableArray alloc] initWithCapacity:1];
    tracks=[[NSMutableDictionary alloc] initWithCapacity:1];
    return self;
}

+(id)sharedMediator
{
    static Mediator*m=nil;
    if(!m)m=[[Mediator alloc]init];
    return m;
}

-(void)announce:(NSDictionary*)track
{
    NSNotification*notification=[NSNotification notificationWithName:@"playerInfo"
                                                              object:self
                                                            userInfo:track];
    [[NSNotificationQueue defaultQueue]enqueueNotification:notification
                                              postingStyle:NSPostNow
                                              coalesceMask:NSNotificationCoalescingOnName
                                                  forModes:nil];
}

-(void)scrobsub_start:(NSDictionary*)dict
{
    scrobsub_start([[dict objectForKey:@"Artist"] UTF8String],
                   [[dict objectForKey:@"Name"] UTF8String],
        [(NSNumber*)[dict objectForKey:@"Total Time"] unsignedIntValue],
        "",
//                   [[dict objectForKey:@"Album"] UTF8String],
        [(NSNumber*)[dict objectForKey:@"Track Number"] unsignedIntValue],
                   "");
//                   [[dict objectForKey:@"MusicBrainz ID"] UTF8String]);
}

-(void)jig
{
    NSEnumerator* i = [stack objectEnumerator];
    NSString* o;
    while(o = [i nextObject]){
        NSDictionary* track = [tracks objectForKey:o];
        if([[track objectForKey:@"Player State"] isEqualToString:@"Playing"]){
            active = o;
            [self announce:track];
            [self scrobsub_start:track];
            return;
        }
    }
    if(active)
        [self announce:[tracks objectForKey:active]]; // nothing to jig, so announce
}

-(void)start:(NSString*)id withTrack:(NSMutableDictionary*)track
{
    if(![stack containsObject:id])
        [stack addObject:id];
    
    [tracks setObject:track forKey:id];
    [track setObject:@"Playing" forKey:@"Player State"];
    [track setObject:id forKey:@"Client ID"];
    [track setObject:now() forKey:@"Start Time"];
    
    if(!active)
        active = id;
    if([active isEqualToString:id]){
        [self announce:track];
        [self scrobsub_start:track];
    }
}

-(void)pause:(NSString*)id
{
    if(![stack containsObject:id])
        NSLog(@"Invalid action: pausing an unknown player connection");
    else{
        [[tracks objectForKey:id] setObject:@"Paused" forKey:@"Player State"];
        NSString* old_id = id;
        [self jig];
        if(old_id == active)
            scrobsub_pause();
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
            [self announce:track];
            scrobsub_resume();
        }
        if(!active){
            active = id;
            [self announce:track];
            [self scrobsub_start:track];
        }
    }
}

-(void)stop:(NSString*)id
{
    if(![stack containsObject:id])
        NSLog(@"Invalid action: resuming an unknown player connection");
    else{
        NSMutableDictionary* track = [tracks objectForKey:id];
        [track setObject:@"Stopped" forKey:@"Player State"];
        if([id isEqualToString:active]){
            [self jig];
            if([id isEqualToString:active]){
                scrobsub_stop();
                active = nil;
            }
        }
    }
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
            [[Mediator sharedMediator] start:[self directParameter] withTrack:[[self evaluatedArguments] mutableCopy]];
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



@implementation ITunesListener

-(id)init
{
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(onPlayerInfo:)
                                                            name:@"com.apple.iTunes.playerInfo"
                                                          object:nil];
    return self;
}

-(void)onPlayerInfo:(NSNotification*)userData
{
    NSString* state = [[userData userInfo] objectForKey:@"Player State"];

    if([state isEqualToString:@"Playing"]){
        // pid may be the same as iTunes send this if the metadata is changed by
        // the user for instance
        //TODO if user restarts the track near the end we should count it is as scrobbled and start again
        //TODO if the user has a playlist that is just the track that should work too!
        int64_t const oldpid = pid;
        pid = [(NSNumber*)[[userData userInfo] objectForKey:@"PersistentID"] longLongValue];
        if(oldpid == pid)
            [[Mediator sharedMediator] resume:@"osx"];
        else{
            NSMutableDictionary* dict = [[userData userInfo] mutableCopy];
            uint const duration = [(NSNumber*)[dict objectForKey:@"Total Time"] longLongValue] / 1000;
            [dict setObject:[NSNumber numberWithUnsignedInt:duration] forKey:@"Total Time"];
            [[Mediator sharedMediator] start:@"osx" withTrack:dict];
        }}
    else if([state isEqualToString:@"Paused"])
        [[Mediator sharedMediator] pause:@"osx"];
    else if([state isEqualToString:@"Stopped"]){
        [[Mediator sharedMediator] stop:@"osx"];
        pid = 0;
    }
}

@end