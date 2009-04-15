//
//  ASTrack.m
//  Audioscrobbler
//
//  Created by Max Howell on 15/04/2009.
//  Copyright 2009 Last.fm. All rights reserved.
//

#import "ASTrack.h"

@implementation ASTrack

-(NSScriptObjectSpecifier*)objectSpecifier
{
    static NSScriptObjectSpecifier *spec = nil;
    if(!spec)
        spec = [[NSPropertySpecifier alloc] initWithContainerClassDescription:(NSScriptClassDescription*)[NSApp classDescription]
                                                           containerSpecifier:nil
                                                                          key:@"Track"];
    return spec;
}

-(id)start:(NSScriptCommand*)cmd
{
    ASTrack* t = [cmd directParameter];
    @try {
        //TODO
    }
    @catch(id e){
        return errAEWrongDataType;
    }
    return nil;
    
}

#define KEY_VAL_PAIR(x, X, type) \
    -(void) set##X:(type)x##p { \
        x = x##p; \
        [x retain]; \
    } \
    -(type)x { \
        return x; \
    }

KEY_VAL_PAIR(title, Title, NSString*)
KEY_VAL_PAIR(artist, Artist, NSString*)
KEY_VAL_PAIR(album, Album, NSString*)
KEY_VAL_PAIR(mbid, Mbid, NSString*)
KEY_VAL_PAIR(duration, Duration, NSNumber*)
KEY_VAL_PAIR(trackNumber, TrackNumber, NSNumber*)

@end
