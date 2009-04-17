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

#import "lastfm.h"


static NSString* encode(NSString* s)
{
    // removed () from included chars as they are legal unencoded and Last.fm seems to be OK with it
    #define escape(s, excluding) (NSString*) CFURLCreateStringByAddingPercentEscapes(nil, (CFStringRef)s, excluding, CFSTR("!*';:@&=+$,/?%#[]"), kCFStringEncodingUTF8);

    // RFC 2396 encode, but also use pluses rather than %20s, it's more legible
    s = escape(s, CFSTR(" "));
    s = [s stringByReplacingOccurrencesOfString:@" " withString:@"+"];

    // Last.fm has odd double encoding rules
    NSRange range = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"&/;+#%"]];
    if(range.location != NSNotFound)
        s = escape(s, nil);

    return s;
}


@implementation lastfm

+(NSURL*)urlForTrack:(NSString*)track by:(NSString*)artist
{
    //TODO localise URL, maybe auth ws gives that? otherwise OS level locale
    NSMutableString* path = [@"http://www.last.fm/music/" mutableCopy];
    [path appendString:encode(artist)];
    [path appendString:@"/_/"];
    [path appendString:encode(track)];
    return [NSURL URLWithString:path];
}

+(NSString*)titleForTrack:(NSDictionary*)track
{
    NSMutableString* s = [[track objectForKey:@"Artist"] mutableCopy];
    [s appendString:@" – "]; // this string is UTF8, neat eh?
    [s appendString:[track objectForKey:@"Name"]];
    return s;
}

@end
