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
#import "NSDictionary+Track.h"
#import <CommonCrypto/CommonDigest.h>

#define KEYCHAIN_NAME "fm.last.Audioscrobbler"


enum HTTPMethod { GET, POST };

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


@interface NSXMLElement (mxcl)
- (NSXMLElement *)firstElementForName:(id)name;
@end
@implementation NSXMLElement (mxcl)
- (NSXMLElement *)firstElementForName:(id)name {
    NSArray *elements = [self elementsForName:name];
    return elements.count ? [elements objectAtIndex:0] : nil;
}
@end



@interface Lastfm()
-(void)getSession;
-(NSString*)getToken;
-(NSXMLDocument*)readResponse:(NSMutableURLRequest*)rq;
@end



@interface LastfmError : NSObject {
    int code;
    NSString* message;
    NSString* method;
}
@property(assign) int code;
@property(assign) NSString* message;
@property(assign) NSString* method;
@end

@implementation LastfmError
@synthesize code, method, message;
+(id)badResponse:(NSString*)method {
    LastfmError* e = [[[LastfmError alloc] init] autorelease];
    e.code = -1;
    e.message = @"The response from Last.fm was invalid";
    e.method = method;
    return e;
}
+(id)unexpectedError:(NSString*)msg {
    LastfmError* e = [[[LastfmError alloc] init] autorelease];
    e.code = -2;
    e.message = msg;
    return e;
}
+(id)authenticationRequired:(NSString*)method {
    LastfmError* e = [[[LastfmError alloc] init] autorelease];
    e.code = 9;
    e.message = @"Authentication required";
    e.method = method;
    return e;
}
-(NSString*)prettyMessage {
    return method
        ? [message stringByAppendingFormat:@" for method: %@.", method]
        : message;
}
-(void)setMessage:(NSString*)s {
    message = s;
}
@end



@implementation Lastfm

@synthesize username;


+(NSString*)urlEncode:(NSString*)s
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

+(NSURL*)urlForUser:(NSString*)username
{
    //TODO localise URL, maybe auth ws gives that? otherwise OS level locale
    return [NSURL URLWithString:[@"http://www.last.fm/user/" stringByAppendingString:[Lastfm urlEncode:username]]];
}


+(NSTimeInterval)scrobblePointForTrackWithDurationInSeconds:(NSTimeInterval)duration
{
    if (duration > 240*2) return 240;
    if (duration < 30*2) return 30;
    return duration / 2;
}


#pragma mark HTTP

-(NSXMLDocument*)get:(NSMutableDictionary*)params to:(NSString*)method
{
    NSMutableString* url = [NSMutableString stringWithCapacity:256];
    [url appendString:@"http://ws.audioscrobbler.com/2.0/?"];
    for (id key in params) {
        [url appendString:key];
        [url appendString:@"="];
        [url appendString:[[params objectForKey:key] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        [url appendString:@"&"];
    }
    [url appendString:@"api_key=" LASTFM_API_KEY "&"];
    [url appendString:@"method="];
    [url appendString:method];
    
    NSMutableURLRequest* rq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
                                                      cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                  timeoutInterval:10];
    [rq setHTTPMethod:@"GET"];
    
    return [self readResponse:rq];
}

static NSString* signature(NSMutableDictionary* params)
{
    NSArray* keys = [[params allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableString* s = [NSMutableString stringWithCapacity:256];
    for (id key in keys) {
        [s appendString:key];
        [s appendString:[params objectForKey:key]];
    }
    [s appendString:@LASTFM_SHARED_SECRET];
    return md5(s);
}

static NSString* utf8_post_escape(NSString* s)
{
    unsigned const N = s.length;
    unsigned ii[N];
    unsigned x = 0;

    for (int i = 0; i < N; ++i) {
        const unichar uc = [s characterAtIndex:i];
        if (uc > 127) {
            continue;
        }
        const char c = ((char*)&uc)[0];
        switch (c) {
        case '&':
        case '%':
        case '=':
            ii[x++] = i;
        }
    }
    
    if (x == 0) return s;

    const char hexnumbers[] = "0123456789ABCDEF"; 
    #define toHexHelper(c) hexnumbers[(c) & 0xf]

    NSMutableString* ms = [s mutableCopy];
    for (int i = x - 1; i >= 0; --i) {
        const unsigned iii = ii[i];
        const unichar uc = [s characterAtIndex:iii];
        const char c = ((char*)&uc)[0];
        NSString* triplet = [NSString stringWithFormat:@"%%%c%c", 
                             toHexHelper((c & 0xf0) >> 4),
                             toHexHelper(c & 0xf)];
        [ms replaceCharactersInRange:NSMakeRange(iii, 1) withString:triplet];
    }
    return ms;
}

static NSMutableString* signed_post_body(NSMutableDictionary* params)
{
    NSMutableString* s = [NSMutableString stringWithCapacity:256];
    for(id key in params) {
        [s appendString:key];
        [s appendString:@"="];
        [s appendString:utf8_post_escape([params objectForKey:key])];
        [s appendString:@"&"];
    }
    [s appendString:@"api_sig="];
    [s appendString:signature(params)];
    return s;
}

-(NSXMLDocument*)post:(NSMutableDictionary*)params to:(NSString*)method
{
    if (!sk && !token) { @throw [LastfmError authenticationRequired:method]; }
    if (!sk && token) [self getSession];
    
    [params setObject:sk forKey:@"sk"];
    [params setObject:@LASTFM_API_KEY forKey:@"api_key"];
    [params setObject:method forKey:@"method"];
    NSMutableString* bodystr = signed_post_body(params);
    NSData* body = [bodystr dataUsingEncoding:NSUTF8StringEncoding];
    
    [bodystr replaceOccurrencesOfString:sk withString:@"****" options:0 range:NSMakeRange(0, bodystr.length)];
    [bodystr replaceOccurrencesOfString:@LASTFM_API_KEY withString:@"****" options:0 range:NSMakeRange(0, bodystr.length)];
    NSLog(@"POST for `%@':\n%@", method, bodystr);
    
    NSMutableURLRequest* rq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://ws.audioscrobbler.com/2.0/"]
                                                      cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                  timeoutInterval:10];
    [rq setHTTPMethod:@"POST"];
    [rq setHTTPBody:body];
    [rq setValue:[[NSNumber numberWithInteger:[body length]] stringValue] forHTTPHeaderField:@"Content-Length"];
    [rq setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    return [self readResponse:rq];
}

-(void)handleError:(LastfmError*)e
{
    switch (e.code) {
        case 15:             // This token has expired
            [token release];
            token = nil;
        case 9:              // Invalid session key - Please re-authenticate
            [sk release];
            sk = nil;
        case 14:
            @try {           // This token has not been authorized
                if (!token) token = [[self getToken] retain];
                NSString* url = [NSString stringWithFormat:@"http://www.last.fm/api/auth/?api_key=" LASTFM_API_KEY "&token=%@", token];
                [delegate lastfm:self requiresAuth:[NSURL URLWithString:url]];
                break;
            }
            @catch (LastfmError* ee) {
                e = ee; // fall through to default case
            }
        default:
            [delegate lastfm:self errorCode:e.code errorMessage:e.prettyMessage];
            break;
    }
}

-(NSXMLDocument*)request:(enum HTTPMethod)http_method params:(NSMutableDictionary*)params to:(NSString*)lastfm_method
{
    @try {
        switch (http_method) {
        case GET:
            return [self get:params to:lastfm_method];
        case POST:
            return [self post:params to:lastfm_method];
        }
    }
    @catch (LastfmError* e) {
        [self handleError:e];
    }
    return nil;
}

static NSString* extract_method(NSURLRequest* rq) 
{
    NSString* query = [rq.HTTPMethod isEqualToString:@"GET"]
            ? [rq.URL query]
            : [[[NSString alloc] initWithData:[rq HTTPBody] encoding:NSUTF8StringEncoding] autorelease];
    
    for (NSString* part in [query componentsSeparatedByString:@"&"])
        if ([[part substringToIndex:7] isEqualToString:@"method="])
            return [part substringFromIndex:7];

    return @"method.unknown";
}


-(NSXMLDocument*)readResponse:(NSMutableURLRequest*)rq
{
    [rq setValue:@"com.methylblue.Audioscrobbler" forHTTPHeaderField:@"User-Agent"];

    NSURLResponse* headers;
    NSError* error = nil;
    NSData* data = [NSURLConnection sendSynchronousRequest:rq returningResponse:&headers error:&error];
    
    if (error)
        @throw [LastfmError unexpectedError:[error localizedDescription]];
    
    NSXMLDocument* xml = [[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeOptionsNone error:nil] autorelease];
    bool ok = [[xml.rootElement attributeForName:@"status"].stringValue isEqualToString:@"ok"];

    if (!ok) {
        NSString* method = extract_method(rq);
        NSLog(@"Response from `%@':\n%@", method, [xml.rootElement XMLStringWithOptions:NSXMLNodePrettyPrint]);
        
        NSXMLElement* ee = [xml.rootElement elementsForName:@"error"].lastObject;
        if (!ee)
            @throw [LastfmError badResponse:method];

        const int code = [ee attributeForName:@"code"].stringValue.intValue;
        
        LastfmError* e = [[[LastfmError alloc] init] autorelease];
        e.code = code;
        e.message = [ee stringValue];
        e.method = method;
        @throw e;
    }

    return xml;
}

#pragma mark Authentication

-(NSString*)getToken
{
    NSXMLDocument* xml = [self get:[NSMutableDictionary dictionary] to:@"auth.gettoken"];
    return [[xml.rootElement elementsForName:@"token"].lastObject stringValue];
}

static void inline save(NSString* username, NSString* sk)
{
    const char* cstr = [username UTF8String];
    SecKeychainAddGenericPassword(NULL, //default keychain
                                  sizeof(KEYCHAIN_NAME),
                                  KEYCHAIN_NAME,
                                  strlen(cstr),
                                  cstr,
                                  32,
                                  [sk UTF8String],
                                  NULL);
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:username forKey:@"Username"];
    [defaults synchronize];
}

-(void)getSession
{
    #define DICT NSMutableDictionary dictionaryWithObjectsAndKeys:token, @"token",
    NSMutableDictionary* params;
    params = [DICT @"auth.getsession", @"method", @LASTFM_API_KEY, @"api_key", nil];
    params = [DICT signature(params), @"api_sig", nil];
    #undef DICT

    NSXMLDocument* xml = [self get:params to:@"auth.getsession"];

    [token release]; // consumed
    token = nil;

    NSXMLElement* session = [xml.rootElement elementsForName:@"session"].lastObject;
    sk = [[[session elementsForName:@"key"].lastObject stringValue] retain];
    username = [[[session elementsForName:@"name"].lastObject stringValue] retain];

    if (!username || !sk)
        @throw [LastfmError badResponse:@"auth.getsession"];

    save(username, sk);
}


#pragma mark WS

static inline NSString* nonil(NSString* s) { return s ? s : @""; }

#define PACK(dict, track) \
    [dict setObject:nonil(track.title) forKey:@"track"]; \
    [dict setObject:nonil(track.artist) forKey:@"artist"]; \
    { NSNumber* n = track.trackNumber; if (n) [dict setObject:n.stringValue forKey:@"trackNumber"]; }

#define PACK_MOAR(dict, track) \
    PACK(dict, track); \
    [dict setObject:[NSString stringWithFormat:@"%d", track.duration] forKey:@"duration"]; \
    { NSString* s = track.album; if (s) [dict setObject:s forKey:@"album"]; } \
//    { NSString* s = track.albumArtist; if (s) [dict setObject:s forKey:@"albumArtist"]; }

-(bool)love:(NSDictionary*)track
{
    if (!track) return false;

    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:5];
    PACK(dict, track);

    return [self request:POST params:dict to:@"track.love"];
}

-(void)share:(NSDictionary*)track with:(NSString*)user
{
    if (!track || !user || user.length == 0) return;

    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:6];
    PACK(dict, track);
    [dict setObject:user forKey:@"recipient"];
    
    [self request:POST params:dict to:@"track.share"];
}

-(void)scrobble:(NSDictionary*)track startTime:(time_t)start_time
{
    if (!track)
        return;
    @try {
        NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:7];
        PACK_MOAR(dict, track);
        [dict setObject:[[NSNumber numberWithUnsignedInt:start_time] stringValue] forKey:@"timestamp"];
        [self post:dict to:@"track.scrobble"];
        [delegate lastfm:self scrobbled:track failureMessage:nil];
    }
    @catch (LastfmError* e) {
        [delegate lastfm:self scrobbled:track failureMessage:e.message];
        [self handleError:e];
    }
}

-(void)updateNowPlaying:(NSDictionary*)track
{
    if (!track) return;

    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:6];
    PACK_MOAR(dict, track);

    NSXMLDocument* xml = [self request:POST params:dict to:@"track.updateNowPlaying"];
    NSXMLElement* nowplayingNode = [xml.rootElement firstElementForName:@"nowplaying"];
    NSXMLElement* artist = [nowplayingNode firstElementForName:@"artist"];
    NSXMLElement* album = [nowplayingNode firstElementForName:@"album"];
    NSXMLElement* title = [nowplayingNode firstElementForName:@"track"];
    
    #define isCorrected(x) [[[x attributeForName:@"corrected"] stringValue] isEqualToString:@"1"]
    
    if (isCorrected(artist) || isCorrected(album) || isCorrected(title)) {
        NSMutableDictionary* dict = [[track mutableCopy] autorelease];
        if (artist) dict.artist = artist.stringValue;
        if (title) dict.title = title.stringValue;
        if (album) dict.album = album.stringValue;
        [delegate lastfm:self metadata:track betterdata:dict];
    }
}

-(id)initWithDelegate:(id)d
{
    token = nil;
    delegate = d;

#ifdef __AS_DEBUGGING__
    username = @"testuser";
    sk = @"d20e0c83aa4252d8bcb945fbaa4aec2a";
    return self;
#endif

    username = [[NSUserDefaults standardUserDefaults] stringForKey:@"Username"];
    if (!username || username.length == 0) {
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
