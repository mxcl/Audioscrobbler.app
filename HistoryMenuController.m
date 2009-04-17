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

#import "HistoryMenuController.h"
#import "lastfm.h"
#import "scrobsub.h"


@implementation HistoryMenuController

-(void)awakeFromNib
{
    tracks = [NSMutableArray arrayWithCapacity:5];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPlayerInfo:)
                                                 name:@"playerInfo"
                                               object:nil];
}

-(void)insert:(NSDictionary*)track
{
    NSMenuItem* item = [menu itemAtIndex:0];
    if([item isEnabled] == false)
        [menu removeItem:item];
    
    NSURL* url = [lastfm urlForTrack:[track objectForKey:@"Name"] by:[track objectForKey:@"Artist"]];
    
    item = [[NSMenuItem alloc] initWithTitle:[lastfm titleForTrack:track] action:@selector(clicked:) keyEquivalent:@""];
    [item setTarget:self];
    [item setRepresentedObject:url];
    [menu insertItem:item atIndex:0];
}

-(void)onPlayerInfo:(NSNotification*)not
{
    NSDictionary* track = [not userInfo];
    NSString* state = [track objectForKey:@"Player State"];
    
    if([state isEqualToString:@"Playing"]){
        if(currentTrack)
            [self insert:currentTrack];
        currentTrack = track;
    }
}

-(void)clicked:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[sender representedObject]];
}

-(void)moreRecentHistory:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[lastfm urlForUser:[NSString stringWithUTF8String:scrobsub_username]]];
}

@end
