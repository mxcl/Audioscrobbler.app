/***************************************************************************
 *   Copyright 2005-2009 Last.fm Ltd.                                      *
 *   Copyright 2010 Max Howell <max@methylblue.com                         *
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
@class Lastfm;


@protocol LastfmDelegate <NSObject>
@optional
-(void)lastfm:(Lastfm*)lastfm requiresAuth:(NSURL*)url; // the user needs to visit this URL to auth
-(void)lastfm:(Lastfm*)lastfm error:(NSString*)message;
-(void)lastfm:(Lastfm*)lastfm metadata:(NSDictionary*)metadata betterdata:(NSDictionary*)betterdata;
@end


@interface Lastfm : NSObject {
    NSString* sk;
    NSString* username;
    NSString* token;
    id <LastfmDelegate> delegate;
}

@property(readonly) NSString* username;

// generates lastfm URLs
+(NSURL*)urlForTrack:(NSString*)track by:(NSString*)artist;
+(NSURL*)urlForUser:(NSString*)username;

// pretty string functions
+(NSString*)durationString:(NSTimeInterval)durationInSeconds;

// lastfm API
-(void)love:(NSDictionary*)track;
-(void)share:(NSDictionary*)track with:(NSString*)username;
-(void)updateNowPlaying:(NSDictionary*)track;
-(void)scrobble:(NSDictionary*)track startTime:(time_t)start_time;

-(id)initWithDelegate:(id)delegate;

@end
