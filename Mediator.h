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

//TODO DistributedNotificationCenter

#import <Cocoa/Cocoa.h>

@interface Mediator:NSObject{
    NSMutableArray* stack;
    NSMutableDictionary* tracks;
    NSString* active;
    time_t previous_start;
}
+(id)sharedMediator;

-(void)start:(NSString*)clientId withTrack:(NSMutableDictionary*)track;
-(void)pause:(NSString*)clientId;
-(void)resume:(NSString*)clientId;
-(void)stop:(NSString*)clientId;

-(IBAction)onScrobblingEnabledChanged:(id)sender;

@end

@interface ITunesListener:NSObject{
    int64_t pid;
}
-(id)init;
@end