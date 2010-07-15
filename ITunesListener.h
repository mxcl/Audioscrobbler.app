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

#import <Cocoa/Cocoa.h>
@class ITunesApplication;
@class Lastfm;
@class HighResolutionTimer;


@protocol ITunesDelegate <NSObject>
@optional
-(void)iTunesTrackStarted:(NSDictionary*)track art:(NSData*)art;
-(void)iTunesTrackPaused:(NSDictionary*)track;
-(void)iTunesTrackResumed:(NSDictionary*)track art:(NSData*)art;
-(void)iTunesPlaybackStopped;

-(void)iTunesTrackWasRatedFourStarsOrAbove:(NSDictionary*)track;
-(void)iTunesWontScrobble:(NSDictionary*)track because:(NSString*)reason;
-(void)iTunesTrackMetadataUpdated:(NSDictionary*)track;
@end


@interface ITunesListener : NSObject {
    NSMutableDictionary* track;
    NSData* art;
    time_t start_time;
    char state;
    ITunesApplication* itunes;
    Lastfm* lastfm;
    HighResolutionTimer* timer;
    id <ITunesDelegate> delegate;
}

@property(readonly) NSDictionary* track;

-(id)initWithLastfm:(Lastfm*)lastfm delegate:(id)delegate;
-(void)onPlayerInfo:(NSNotification*)userData;

@end
