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

#import "MetadataWindowController.h"
#import "BGHUDScroller.h"
#import "lastfm.h"
#import "Mediator.h"

@interface GradientOverlayImageView:NSImageView
@end
@implementation GradientOverlayImageView
-(void)drawRect:(NSRect)rect
{
    [super drawRect:rect];
    if ([self image] == nil) return;
    
    NSGradient* g = [[NSGradient alloc] 
                     initWithStartingColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.11] 
                     endingColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.88]];
    [g drawInRect:rect angle:-90];
    [g release];
}
@end

@interface ButtonBackground:NSView
@end
@implementation ButtonBackground:NSView
-(void)drawRect:(NSRect)rect
{
    NSGradient* g = [[NSGradient alloc] initWithColorsAndLocations:
                     [NSColor colorWithCalibratedWhite:0.839 alpha:0.6], 0.0,
                     [NSColor colorWithCalibratedWhite:0.525 alpha:0.6], 0.01,
                     [NSColor colorWithCalibratedWhite:0.306 alpha:0.6], 0.5,
                     [NSColor colorWithCalibratedWhite:0.204 alpha:0.6], 0.51,
                     [NSColor colorWithCalibratedWhite:0.004 alpha:0.6], 1.0,
                     nil];
    [g drawInRect:rect angle:-90];
    [g release];
}
@end


@implementation MetadataWindowController

-(id)init
{
    [super initWithWindowNibName:@"MetadataWindow"];
    // do when nib loaded
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPlayerInfo:)
                                                 name:@"playerInfo"
                                               object:nil];
    return self;
}

-(void)awakeFromNib
{
    [bio_view setVerticalScroller:[[[BGHUDScroller alloc] init] autorelease]];    

    //FIXME the NSUnerlineStyleNone flag doesn't work
    [bio setLinkTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSColor colorWithCalibratedRed:0.0 green:0.678 blue:0.933 alpha:1.0], NSForegroundColorAttributeName,
                                [NSNumber numberWithInt: NSUnderlineStyleNone], NSUnderlineStyleAttributeName,
                                [NSCursor pointingHandCursor], NSCursorAttributeName, nil]];    
    
    NSDictionary* dict = [[Mediator sharedMediator] currentTrack];
    [self update:dict];
}

-(void)onPlayerInfo:(NSNotification*)userData
{
    NSDictionary* dict = [userData userInfo];
    
    if([[dict objectForKey:@"Player State"] isEqualToString:@"Stopped"])
        [self close];
    else if([self window])
        [self performSelectorOnMainThread:@selector(update:) withObject:dict waitUntilDone:YES];
}

void setTitleFrameOrigin(NSTextField* title, NSPoint pt)
{
    pt.y += 8;
    pt.x += 8;
    [title setFrameOrigin:pt];
}

-(void)updateArtist:(NSString*)artist
{    
    NSString* encoded_artist = (NSString*)CFURLCreateStringByAddingPercentEscapes(nil, (CFStringRef)artist, NULL, CFSTR("!*';:@&=+$,/?%#[]"), kCFStringEncodingUTF8);
    
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:
                                       @"http://ws.audioscrobbler.com/2.0/?method=artist.getInfo&artist=%@&api_key="SCROBSUB_API_KEY,
                                       encoded_artist]];
    
    NSXMLDocument* xml = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:nil];
    NSError* err;
#define xpath(path) [[[[xml rootElement] nodesForXPath:path error:&err] lastObject] stringValue]
    NSString* html = xpath(@"/lfm/artist/bio/content");
    NSString* image_url = xpath(@"/lfm/artist/image[@size='large']");
    NSString* artist_url = xpath(@"/lfm/artist/url");
    
    image_url = [image_url stringByReplacingOccurrencesOfString:@"/126/" withString:@"/252/"];
    
    NSImageRep* imgrep = [NSImageRep imageRepWithContentsOfURL:[NSURL URLWithString:image_url]];
    
    /// layout
    NSRect frame = [image frame];
    int const d = frame.size.height - [imgrep pixelsHigh];
    frame.size.height = [imgrep pixelsHigh];
    frame.origin.y += d;
    [image setFrame:frame];
    
    setTitleFrameOrigin( title, frame.origin );
    
    int const y = [bio_view frame].origin.y;
    int const h = frame.origin.y - y;
    frame = [bio_view frame];
    frame.size.height = h;
    frame.origin.y = y;
    [bio_view setFrame:frame];
    
    NSImage* img = [[NSImage alloc] init];
    [img addRepresentation:imgrep];   
    
    /// bio
    //TODO remove trailing margin caused by last p bottom margin, prolly some useful css to do this
    NSMutableCharacterSet* whitespace = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
    [whitespace addCharactersInString:@"\r\n"];
    
    html = [html stringByTrimmingCharactersInSet:whitespace];
    
    if([html length] == 0){
        NSString* url = [artist_url stringByAppendingString:@"/+wiki/edit"];
        html = [NSString stringWithFormat:@"We don’t have a description for this artist yet, <A href='%s'>care to help?</a>", url];
    }else{
        // this initial div adds close to the correct top margin
        html = [@"<p>" stringByAppendingString:html];
        html = [html stringByReplacingOccurrencesOfString:@"\r \r" withString:@"<p>"]; // Last.fm sucks
        html = [html stringByReplacingOccurrencesOfString:@"\r" withString:@"<p>"]; // Last.fm sucks more
        html = [html stringByAppendingString:@"</p>"];
    }
    
    NSDictionary* docattrs;
    NSMutableAttributedString *attrs = [[NSMutableAttributedString alloc]
                                        initWithHTML:[html dataUsingEncoding:NSUTF8StringEncoding] 
                                        options:[NSDictionary dictionaryWithObjectsAndKeys:
                                                 [NSNumber numberWithUnsignedInt:NSUTF8StringEncoding],
                                                 @"CharacterEncoding", nil] 
                                        documentAttributes:&docattrs];    
    [image setImage:img];
    [[bio textStorage] setAttributedString:attrs];
    
    // you have to set these everytime you change the text in a NSTextView
    // nice one Apple
    [bio setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]]];
    [bio setTextColor:[NSColor whiteColor]];
    [attrs release];
}

-(void)update:(NSDictionary*)track
{
    NSString* artist = [track objectForKey:@"Artist"];

    if(![artist isEqualToString:current_artist]){
        [self updateArtist:artist];
        current_artist = artist;
    }

    [title setStringValue:[NSString stringWithFormat:@"%@\n%@ (%@)",
                           artist,
                           [track objectForKey:@"Name"],
                           [lastfm durationString:[track objectForKey:@"Total Time"]]]];
}



@end
