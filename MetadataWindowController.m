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
#import "Mediator.h"


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
    [bio setLinkTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSColor colorWithCalibratedRed:0 green:0.682 blue:0.937 alpha:1.0], NSForegroundColorAttributeName,
                                [NSNumber numberWithInt: NSSingleUnderlineStyle], NSUnderlineStyleAttributeName,
                                [NSCursor pointingHandCursor], NSCursorAttributeName, nil]];    

    current_artist = [[[Mediator sharedMediator] currentTrack] objectForKey:@"Artist"];
    [self update];
}

-(void)onPlayerInfo:(NSNotification*)userData
{
    NSDictionary* dict = [userData userInfo];
    
    if([[dict objectForKey:@"Player State"] isEqualToString:@"Stopped"])
        [self close];
    else{
        NSString* artist = [dict objectForKey:@"Artist"];
        if([artist isEqualToString:current_artist])return;    
        current_artist = artist;
        
        if([self window])
            [self performSelectorOnMainThread:@selector(update) withObject:nil waitUntilDone:YES];
    }
}

-(void)update
{
    if(!current_artist)return;
    
    NSString* artist = (NSString*)CFURLCreateStringByAddingPercentEscapes(nil, (CFStringRef)current_artist, NULL, CFSTR("!*';:@&=+$,/?%#[]"), kCFStringEncodingUTF8);
    
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:
                                       @"http://ws.audioscrobbler.com/2.0/?method=artist.getInfo&artist=%@&api_key="SCROBSUB_API_KEY,
                                       artist]];
    
    NSXMLDocument* xml = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:nil];
    NSError* err;
    NSString* html = [[[[xml rootElement] nodesForXPath:@"/lfm/artist/bio/content" error:&err] lastObject] stringValue];
    NSString* image_url = [[[[xml rootElement] nodesForXPath:@"/lfm/artist/image[@size='large']" error:&err] lastObject] stringValue];
    
    image_url = [image_url stringByReplacingOccurrencesOfString:@"/126/" withString:@"/252/"];
    
    NSImageRep* imgrep = [NSImageRep imageRepWithContentsOfURL:[NSURL URLWithString:image_url]];
    
/// layout
    NSRect frame = [image frame];
    int const d = frame.size.height - [imgrep pixelsHigh];
    frame.size.height = [imgrep pixelsHigh];
    frame.origin.y += d;
    [image setFrame:frame];
    int const y = [bio_view frame].origin.y;
    frame.size.height = frame.origin.y - 8 - y;
    frame.origin.y = y;
    [bio_view setFrame:frame];

    [[self window] setTitle:current_artist];
    
    NSImage* img = [[NSImage alloc] init];
    [img addRepresentation:imgrep];
    [image setImage:img];
    
/// bio
    html = [html stringByReplacingOccurrencesOfString:@"\r" withString:@"<br>"]; // Last.fm sucks
    
    NSAttributedString *attrs = [[NSAttributedString alloc] initWithHTML:[html dataUsingEncoding:NSUTF8StringEncoding] 
                                                                 options:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                          [NSNumber numberWithUnsignedInt:NSUTF8StringEncoding],
                                                                          @"CharacterEncoding", nil] 
                                                      documentAttributes:nil];
    [[bio textStorage] setAttributedString:attrs];
    
    // you have to set these everytime you change the text in a NSTextView
    // nice one Apple
    [bio setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]]];
    [bio setTextColor:[NSColor whiteColor]];
    [attrs release];
    
}

@end
