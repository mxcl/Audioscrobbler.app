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

#import "StatusItemController.h"
#include "../scrobsub.h"


static void scrobsub_callback(int event, const char* message)
{
    switch (event)
    {
        case SCROBSUB_AUTH_REQUIRED:
            //TODO some kind of dialog
            scrobsub_auth();
            break;
            
        case SCROBSUB_ERROR_RESPONSE:
            NSLog( @"%s", message );
            break;
    }
}


@implementation StatusItemController

- (void)awakeFromNib
{
    NSBundle* bundle = [NSBundle mainBundle];
    status_item = [[[NSStatusBar systemStatusBar] statusItemWithLength:27] retain];
    [status_item setHighlightMode:YES];
    [status_item setImage:[[NSImage alloc] initWithContentsOfFile: [bundle pathForResource:@"icon" ofType:@"png"]]];
    [status_item setAlternateImage:[[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"inverted_icon" ofType:@"png"]]];
    [status_item setEnabled:YES];
    [status_item setMenu:menu];

    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(onPlaybackNotification:)
                                                            name:@"com.apple.iTunes.playerInfo"
                                                          object:nil];
    
    scrobsub_init(scrobsub_callback);
}


-(void)onPlaybackNotification:(NSNotification*)userData
{
    static int64_t pid = 0; //FIXME dunno for sure if 0 is invalid

    NSDictionary *dict = [userData userInfo];
    NSString* state = [dict objectForKey:@"Player State"];
    NSString* name = [dict objectForKey:@"Name"];
    
    NSLog(@"%@ - %@", state, name);
    
    if([state isEqualToString:@"Playing"])
    {
        uint const duration = [(NSNumber*)[dict objectForKey:@"Total Time"] longLongValue] / 1000;
        [[menu itemAtIndex:0] setTitle:[NSString stringWithFormat:@"%@ [%d:%02d]", name, duration/60, duration%60]];
        
        // pid may be the same as iTunes send this if the metadata is changed by
        // the user for instance
        //TODO if user restarts the track near the end we should count it is as scrobbled and start again
        //TODO if the user has a playlist that is just the track that should work too!
        int64_t const oldpid = pid;
        pid = [(NSNumber*)[dict objectForKey:@"PersistentID"] longLongValue];
        if(oldpid == pid){
            if (scrobsub_state() == SCROBSUB_PAUSED)
                scrobsub_resume();
            return;
        }

        scrobsub_start([[dict objectForKey:@"Artist"] UTF8String],
                       [name UTF8String],
                       [[dict objectForKey:@"Album"] UTF8String],
                       "", // mbid
                       duration,
                       [(NSNumber*)[dict objectForKey:@"Track Number"] intValue]);
    }
    else if([state isEqualToString:@"Paused"])
    {
        scrobsub_pause();
        [[menu itemAtIndex:0] setTitle:[name stringByAppendingString:@" [paused]"]];
    }
    else if([state isEqualToString:@"Stopped"])
    {
        scrobsub_stop();
        [[menu itemAtIndex:0] setTitle:@"Ready"];
        pid = 0;
    }
}

@end
