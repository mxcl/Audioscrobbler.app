// Created by Max Howell on 05/06/2010.
#import "NSDictionary+Track.h"
#import "lastfm.h"


@implementation NSDictionary (mxcl)

-(NSString*)artist { return [self objectForKey:@"Artist"]; }
-(NSString*)title { return [self objectForKey:@"Name"]; }
-(NSString*)album { return [self objectForKey:@"Album"]; }
-(int64_t)pid { return [[self objectForKey:@"PersistentID"] longLongValue]; }
-(int)rating { return [[self objectForKey:@"Rating"] intValue]; }
-(unsigned)duration { return [[self objectForKey:@"Total Time"] longLongValue] / 1000; }
-(NSNumber*)trackNumber { return [self objectForKey:@"Track Number"]; }
-(NSString*)albumArtist { return [self objectForKey:@"Album Artist"]; }
-(int)playerState
{
    NSString* s = [self objectForKey:@"Player State"];
    if ([s isEqualToString:@"Playing"]) return StatePlaying;
    if ([s isEqualToString:@"Paused"]) return StatePaused;
    if ([s isEqualToString:@"Stopped"]) return StateStopped;
    return StateUnknown;
}

-(bool)unrated
{
    // a track with a computed rating is a track with no user rating, but at least one
    // track on the album was rated, and thus the other tracks have a "computed" rating
    return [[self objectForKey:@"Rating"] intValue] == 0 ||
           [[self objectForKey:@"Rating Computed"] boolValue];
}

-(NSString*)prettyTitle
{
    NSMutableString* s = [[self objectForKey:@"Artist"] mutableCopy];
    [s appendString:@" — "]; // this string is UTF8, neat eh?
    [s appendString:[self objectForKey:@"Name"]];
    return [s autorelease];
}

-(NSURL*)url
{
    //TODO localise URL, maybe auth ws gives that? otherwise OS level locale
    NSMutableString* path = [[@"http://www.last.fm/music/" mutableCopy] autorelease];
    [path appendString:[Lastfm urlEncode:self.artist]];
    [path appendString:@"/_/"];
    [path appendString:[Lastfm urlEncode:self.title]];
    return [NSURL URLWithString:path];
}

-(NSURL*)lyricWikiUrl
{
    NSString* artist = [self.artist stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    NSString* title = [self.title stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    artist = [artist stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    title = [title stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString* url = [NSString stringWithFormat:@"http://lyrics.wikia.com/%@:%@", artist, title];
    return [NSURL URLWithString:url];
}

@end


@implementation NSMutableDictionary (mxcl)

-(void)setArtist:(NSString*)artist { [self setObject:artist forKey:@"Artist"]; }
-(void)setTitle:(NSString*)title { [self setObject:title forKey:@"Name"]; }
-(void)setAlbum:(NSString*)album { [self setObject:album forKey:@"Album"]; }

-(void)setRating:(int)newrating
{
    [self removeObjectForKey:@"Rating Computed"];
    [self setObject:[NSNumber numberWithInt:newrating] forKey:@"Rating"];
}

@end
