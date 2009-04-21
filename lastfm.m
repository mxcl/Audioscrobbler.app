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
#import "scrobsub.h"


static NSString* encode(NSString* s)
{
    // removed () from included chars as they are legal unencoded and Last.fm seems to be OK with it
    #define escape(s, excluding) (NSString*) CFURLCreateStringByAddingPercentEscapes(nil, (CFStringRef)s, excluding, CFSTR("!*';:@&=+$,/?%#[]"), kCFStringEncodingUTF8);

    bool double_escape = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"&/;+#%"]].location != NSNotFound;
    
    // RFC 2396 encode, but also use pluses rather than %20s, it's more legible
    s = escape(s, CFSTR(" "));
    s = [s stringByReplacingOccurrencesOfString:@" " withString:@"+"];

    // Last.fm has odd double encoding rules
    if(double_escape)
        s = escape(s, nil);

    return s;
    #undef escape
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

+(NSURL*)urlForUser:(NSString*)username
{
    //TODO localise URL, maybe auth ws gives that? otherwise OS level locale
    return [NSURL URLWithString:[@"http://www.last.fm/user/" stringByAppendingString:encode(username)]];
}


static NSData* signed_post_body(NSDictionary* vars)
{
    NSArray* keys = [[vars allKeys] sortedArrayUsingSelector:@selector(caseSensitiveCompare:)];
    NSMutableString* s = [NSMutableString stringWithCapacity:256];
    for(id key in keys){
        [s appendString:key];
        [s appendString:[vars objectForKey:key]];
    }
    [s appendString:@SCROBSUB_SHARED_SECRET];
    char out[33];
    scrobsub_md5(out, [s UTF8String]);
    NSString* sig = [NSString stringWithUTF8String:out];
    
    [s setString:@""];
    for(id key in vars)
        [s appendFormat:@"%@=%@&", key, [vars objectForKey:key]];
    [s appendString:@"api_sig="];
    [s appendString:sig];
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

+(void)post:(NSMutableDictionary*)vars to:(NSString*)method
{
    [vars setObject:@SCROBSUB_API_KEY forKey:@"api_key"];
    [vars setObject:[NSString stringWithUTF8String:scrobsub_session_key] forKey:@"sk"];
    [vars setObject:method forKey:@"method"];
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://ws.audioscrobbler.com/2.0/"]
                                                           cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:10];
    
    NSData* body = signed_post_body(vars);
    
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:body];
    [request setValue:@"fm.last.Audioscrobbler" forHTTPHeaderField:@"User-Agent"];
    [request setValue:[[NSNumber numberWithInteger:[body length]] stringValue] forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    NSURLResponse* headers;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&headers error:nil];
}


+(void)love:(NSDictionary*)track
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:5];
    [dict setObject:[track valueForKey:@"Name"] forKey:@"track"];
    [dict setObject:[track valueForKey:@"Artist"] forKey:@"artist"];
    
    [lastfm post:dict to:@"track.love"];
}

@end
