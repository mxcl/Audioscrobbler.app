// Created by Max Howell on 05/06/2010.
#import <Cocoa/Cocoa.h>

@interface NSDictionary (mxcl)
@property(readonly) bool unrated;
@property(readonly) int64_t pid;
@property(readonly) int rating;
@property(readonly) NSString* artist;
@property(readonly) NSString* title;
@property(readonly) NSString* album;
@property(readonly) int playerState;
@property(readonly) NSString* prettyTitle;
@property(readonly) NSURL* url;
@property(readonly) unsigned duration;
@property(readonly) NSNumber* trackNumber;
@property(readonly) NSString* albumArtist;
@property(readonly) NSURL* lyricWikiUrl;
@end

@interface NSMutableDictionary (mxcl)
-(void)setArtist:(NSString*)artist;
-(void)setTitle:(NSString*)title;
-(void)setAlbum:(NSString*)album;
-(void)setRating:(int)newrating;
@end
