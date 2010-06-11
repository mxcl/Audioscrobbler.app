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

#import "lastfm.h"
#include <CommonCrypto/CommonDigest.h>

#define KEYCHAIN_NAME "fm.last.Audioscrobbler"


static NSString* encode(NSString* s)
{
    // removed () from included chars as they are legal unencoded and Last.fm seems to be OK with it
    #define escape(s, excluding) [(NSString*)CFURLCreateStringByAddingPercentEscapes(nil, (CFStringRef)s, excluding, CFSTR("!*';:@&=+$,/?%#[]"), kCFStringEncodingUTF8) autorelease];

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

static NSString* md5(NSString* s)
{
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
    if(data){
        unsigned char d[CC_MD5_DIGEST_LENGTH];
        CC_MD5(data.bytes, data.length, d);
        return [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                d[0], d[1], d[2],  d[3],  d[4],  d[5],  d[6],  d[7],
                d[8], d[9], d[10], d[11], d[12], d[13], d[14], d[15]];
    }
    return nil;
}

static int status(NSXMLDocument* xml)
{
    if ([[[[xml rootElement] attributeForName:@"status"] stringValue] isEqualToString:@"ok"])
        return 1;
    else
        return [[[[[[xml rootElement] elementsForName:@"error"] lastObject] attributeForName:@"code"] stringValue] intValue];
}


@interface Lastfm()
-(int)getSession;
-(NSURL*)getToken;
@end



@implementation Lastfm

@synthesize username;

+(NSURL*)urlForTrack:(NSString*)track by:(NSString*)artist
{
    //TODO localise URL, maybe auth ws gives that? otherwise OS level locale
    NSMutableString* path = [[@"http://www.last.fm/music/" mutableCopy] autorelease];
    [path appendString:encode(artist)];
    [path appendString:@"/_/"];
    [path appendString:encode(track)];
    return [NSURL URLWithString:path];
}

+(NSURL*)urlForUser:(NSString*)username
{
    //TODO localise URL, maybe auth ws gives that? otherwise OS level locale
    return [NSURL URLWithString:[@"http://www.last.fm/user/" stringByAppendingString:encode(username)]];
}

+(NSString*)durationString:(NSTimeInterval)ti
{
    uint const seconds = ti;
    return [NSString stringWithFormat:@"%u:%02u", seconds / 60, seconds % 60];
}


#pragma mark HTTP

static NSData* signed_post_body(NSDictionary* vars)
{
    NSArray* keys = [[vars allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableString* s = [NSMutableString stringWithCapacity:256];
    for(id key in keys){
        [s appendString:key];
        [s appendString:[vars objectForKey:key]];
    }
    [s appendString:@LASTFM_SHARED_SECRET];

    NSString* sig = md5(s);
    
    [s setString:@""];
    for(id key in vars)
        [s appendFormat:@"%@=%@&", key, [vars objectForKey:key]];
    [s appendString:@"api_sig="];
    [s appendString:sig];
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

-(NSData*)post:(NSMutableDictionary*)vars to:(NSString*)method
{
    if (token && [self getSession] == 14 || !sk) {
        [delegate lastfm:self requiresAuth:[self getToken]];
        return nil;
    }

    [vars setObject:@LASTFM_API_KEY forKey:@"api_key"];
    [vars setObject:sk forKey:@"sk"];
    [vars setObject:method forKey:@"method"];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://post.audioscrobbler.com/2.0/"]
                                                           cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:10];

    NSData* body = signed_post_body(vars);

    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:body];
    [request setValue:@"fm.last.Audioscrobbler" forHTTPHeaderField:@"User-Agent"];
    [request setValue:[[NSNumber numberWithInteger:[body length]] stringValue] forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];

    NSURLResponse* headers;
    return [NSURLConnection sendSynchronousRequest:request returningResponse:&headers error:nil];
}


#pragma mark Authentication

-(NSURL*)getToken
{
    if (!token) {
        NSURL* url = [NSURL URLWithString:@"http://ws.audioscrobbler.com/2.0/?method=auth.gettoken&api_key=" LASTFM_API_KEY];
        NSXMLDocument* xml = [[NSXMLDocument alloc] initWithContentsOfURL:url options:NSUncachedRead error:nil];
        token = [[[[xml.rootElement elementsForName:@"token"] lastObject] stringValue] retain];
        [xml release];
    }
    
    return [NSURL URLWithString:[@"http://www.last.fm/api/auth/?api_key=" LASTFM_API_KEY "&token=" stringByAppendingString:token]];
}

-(int)getSession
{
    @try {
        NSString* format = @"api_key" LASTFM_API_KEY "methodauth.getSessiontoken%@" LASTFM_SHARED_SECRET;
        NSString* sig = md5([NSString stringWithFormat:format, token]);
        NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"http://ws.audioscrobbler.com/2.0/?method=auth.getSession&api_key=" LASTFM_API_KEY "&token=%@&api_sig=%@", token, sig]];

        NSError* error;
        NSXMLDocument* xml = [[[NSXMLDocument alloc] initWithContentsOfURL:url options:NSUncachedRead error:&error] autorelease];

        if (error)
            //@throw [@"An error occurred while authenticating:\n\n" stringByAppendingString:[error localizedDescription]];
            return 14; // HACK because initWithContentsOfURL bails on the 403 we get for lastfm failure conditions

        int const code = status(xml);
        if (code > 1)
            return code;

        NSXMLElement* session = [[[xml rootElement] elementsForName:@"session"] lastObject];
        sk = [[[[session elementsForName:@"key"] lastObject] stringValue] retain];
        username = [[[[session elementsForName:@"name"] lastObject] stringValue] retain];
        [token release];
        token = nil; // consumed

        if (!username || !sk)
            @throw @"There was an error during authentication, try again later.";

        const char* cusername = [username UTF8String];
        OSStatus err = SecKeychainAddGenericPassword(NULL, //default keychain
                                                     sizeof(KEYCHAIN_NAME),
                                                     KEYCHAIN_NAME,
                                                     strlen(cusername),
                                                     cusername,
                                                     32,
                                                     [sk UTF8String],
                                                     NULL);
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:username forKey:@"Username"];
        [defaults synchronize];
        
        if (err != noErr)
            @throw [NSString stringWithFormat:@"%s", GetMacOSStatusCommentString(err)];

        return 1;
    }
    @catch (NSString* msg) {
        sk = token = username = nil;
        [delegate lastfm:self error:msg];
    }
    return 100;
}


#pragma mark WS

static void correct_empty(NSMutableDictionary* d, NSString* key)
{
    NSString* o = (NSString*)[d objectForKey:key];
    if(!o || [o length] == 0)
        [d setObject:@"[unknown]" forKey:key];
}

#define PACK(dict, track) \
    [dict setObject:[track valueForKey:@"Name"] forKey:@"track"]; \
    [dict setObject:[track valueForKey:@"Artist"] forKey:@"artist"]; \
    correct_empty(dict, @"track"); \
    correct_empty(dict, @"artist");

#define PACK_MOAR(dict, track) \
    PACK(dict, track); \
    [dict setObject:[track valueForKey:@"Album"] forKey:@"album"];

-(void)love:(NSDictionary*)track
{
    if (!track) return;

    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:5];
    PACK(dict, track);
    
    [self post:dict to:@"track.love"];
}

-(void)share:(NSDictionary*)track with:(NSString*)user
{
    if (!track || !user) return;

    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:6];
    PACK(dict, track);
    [dict setObject:user forKey:@"recipient"];
    
    [self post:dict to:@"track.share"];
}

-(void)scrobble:(NSDictionary*)track startTime:(time_t)start_time
{
    if (!track) return;
    
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:7];
    PACK_MOAR(dict, track);
    [dict setObject:[[NSNumber numberWithUnsignedInt:start_time] stringValue] forKey:@"timestamp"];
    
    //TODO rest of optional parameters including albumArtist
    
    [self post:dict to:@"track.scrobble"];
}

-(void)updateNowPlaying:(NSDictionary*)track
{
    if (!track) return;

    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:6];
    PACK_MOAR(dict, track);

    //TODO rest of optional parameters including albumArtist
    
    NSData* data = [self post:dict to:@"user.updateNowPlaying"];
    
    NSXMLDocument* xml = [[[NSXMLDocument alloc] initWithData:data options:0 error:nil] autorelease];
    
    NSLog(@"%@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
    
    #define NODE(x) [[[[xml rootElement] elementsForName:x] lastObject] stringValue]
    NSString* Artist = NODE(@"artist");
    NSString* Album = NODE(@"album");
    NSString* Name = NODE(@"track");
    #undef NODE
    
    #define NEQ(x) ![x isEqualToString:[track objectForKey:@#x]]
    if (NEQ(Artist) || NEQ(Album) || NEQ(Name)) {
        NSMutableDictionary* dict = [[track mutableCopy] autorelease];
        [dict setObject:Artist forKey:@"Artist"];
        [dict setObject:Name forKey:@"Name"];
        [dict setObject:Album forKey:@"Album"];
        [delegate lastfm:self metadata:track betterdata:dict];
    }
    #undef NEQ
}

-(id)initWithDelegate:(id)d
{
    delegate = d;

#ifdef __AS_DEBUGGING__
    username = @"testuser";
    sk = @"d20e0c83aa4252d8bcb945fbaa4aec2a";
    return self;
#endif

    username = [[NSUserDefaults standardUserDefaults] stringForKey:@"Username"];
    if (!username)
        return self;
    if (username.length == 0) {
        username = nil;
        return self;
    }
    [username retain];

    const char* cusername = [username UTF8String];
    void* key;
    UInt32 n;
    OSStatus err = SecKeychainFindGenericPassword(NULL, //default keychain
                                                  sizeof(KEYCHAIN_NAME),
                                                  KEYCHAIN_NAME,
                                                  strlen(cusername),
                                                  cusername,
                                                  &n,
                                                  &key,
                                                  NULL);

    if (err == noErr) {
        sk = [[NSString alloc] initWithBytes:key length:32 encoding:NSUTF8StringEncoding];
        SecKeychainItemFreeContent(NULL, key);
        return self;
    }
    else
        return self;
}

-(void)dealloc
{
    [sk release];
    [username release];
    [token release];
    [super dealloc];
}

@end
