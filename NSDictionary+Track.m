// Created by Max Howell on 05/06/2010.
#import "NSDictionary+Track.h"

@implementation NSDictionary (mxcl)

-(NSString*)artist { return [self objectForKey:@"Artist"]; }
-(NSString*)title { return [self objectForKey:@"Name"]; }
-(NSString*)album { return [self objectForKey:@"Album"]; }
-(int64_t)pid { return [[self objectForKey:@"PersistentID"] longLongValue]; }
-(int)rating { return [[self objectForKey:@"Rating"] intValue]; }

-(int)playerState
{
    NSString* s = [self objectForKey:@"Player State"];
    if ([s isEqualToString:@"Playing"]) return STATE_PLAYING;
    if ([s isEqualToString:@"Paused"]) return STATE_PAUSED;
    if ([s isEqualToString:@"Stopped"]) return STATE_STOPPED;
    return STATE_ERROR;
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

@end


@implementation NSMutableDictionary (mxcl)

-(void)setArtist:(NSString*)artist { [self setObject:artist forKey:@"Artist"]; }
-(void)setTitle:(NSString*)title { [self setObject:title forKey:@"Name"]; }
-(void)setAlbum:(NSString*)album { [self setObject:album forKey:@"Album"]; }

-(bool)isEqualToTrack:(NSDictionary*)track
{
    id o = [self objectForKey:@"Album Art"];
    @try {
        [self removeObjectForKey:@"Album Art"];
        return [self isEqualToDictionary:track];
    }
    @finally {
        if (o) [self setObject:o forKey:@"Album Art"];
    }
}

@end
