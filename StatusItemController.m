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
#import "Mediator.h"
#import "scrobsub.h"
#import "StatusItemController.h"
#import <Carbon/Carbon.h>


static void install_plugin()
{
    NSString* dst = [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/iTunes/iTunes Plug-ins/Audioscrobbler.bundle"];
    NSString* src = [[NSBundle mainBundle] pathForResource:@"iTunes Plug-in" ofType:@"bundle"];
    NSFileManager* fm = [NSFileManager defaultManager];

    if([fm fileExistsAtPath:dst])
    {
        NSString* dstv = [[NSBundle bundleWithPath:dst] objectForInfoDictionaryKey:@"CFBundleVersion"];
        NSString* srcv = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

        if([dstv isEqualToString:srcv])
            return;
        
    	NSInteger tag = 0;
        bool result = [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation
                                                                   source:[dst stringByDeletingLastPathComponent]
                                                              destination:@""
                                                                    files:[NSArray arrayWithObject:[dst lastPathComponent]]
                                                                      tag:&tag];
        if(!result){
            NSLog(@"Couldn't trash %@", dst);
            return;
        }
    }
    
    //install
	[fm copyPath:src toPath:dst handler:nil];
}

static void scrobsub_callback(int event, const char* message)
{
    switch (event)
    {
        case SCROBSUB_AUTH_REQUIRED:
        {
            char url[110];
            scrobsub_auth(url);
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithCString:url]]];
            break;
        }
            
        case SCROBSUB_ERROR_RESPONSE:
            NSLog(@"%s", message);
            break;
    }
}

static OSStatus MyHotKeyHandler(EventHandlerCallRef ref, EventRef e, void* userdata)
{
    [(StatusItemController*)userdata tag:userdata];
    return noErr;
}



@implementation StatusItemController

-(void)awakeFromNib
{   
    NSBundle* bundle = [NSBundle mainBundle];
    status_item = [[[NSStatusBar systemStatusBar] statusItemWithLength:27] retain];
    [status_item setHighlightMode:YES];
    [status_item setImage:[[NSImage alloc] initWithContentsOfFile: [bundle pathForResource:@"icon" ofType:@"png"]]];
    [status_item setAlternateImage:[[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"inverted_icon" ofType:@"png"]]];
    [status_item setEnabled:YES];
    [status_item setMenu:menu];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPlayerInfo:)
                                                 name:@"playerInfo"
                                               object:nil];
    scrobsub_init(scrobsub_callback);
    [[ITunesListener alloc] init];
    [menu setDelegate:self];
    [GrowlApplicationBridge setGrowlDelegate:self];
    install_plugin();

/// global shortcut
    EventTypeSpec type;
    type.eventClass = kEventClassKeyboard;
    type.eventKind = kEventHotKeyPressed;    
    InstallApplicationEventHandler(&MyHotKeyHandler, 1, &type, self, NULL);

    EventHotKeyID kid;
    kid.signature='htk1';
    kid.id=1;
    EventHotKeyRef kref;
    RegisterEventHotKey(kVK_ANSI_T, cmdKey+optionKey+controlKey, kid, GetApplicationEventTarget(), 0, &kref);
}

-(void)onPlayerInfo:(NSNotification*)userData
{
    NSDictionary* dict = [userData userInfo];
    NSString* state = [dict objectForKey:@"Player State"];
    NSString* name = [dict objectForKey:@"Name"];
    
    if([state isEqualToString:@"Playing"]){
        uint const duration = [(NSNumber*)[dict objectForKey:@"Total Time"] longLongValue];
        [[menu itemAtIndex:0] setTitle:[NSString stringWithFormat:@"%@ [%d:%02d]", name, duration/60, duration%60]];
        [[menu itemAtIndex:1] setEnabled:true]; //TODO can't do this on RESUME
        [[menu itemAtIndex:2] setEnabled:true];
        [[menu itemAtIndex:3] setEnabled:true];
        [[menu itemAtIndex:1] setTitle:@"Love"]; //TODO can't do this on RESUME
        
        [GrowlApplicationBridge notifyWithTitle:name
                                    description:[dict objectForKey:@"Artist"]
                               notificationName:@"Track Started"
                                       iconData:nil
                                       priority:0
                                       isSticky:false
                                   clickContext:dict];
    }
    else if([state isEqualToString:@"Paused"]){
        [[menu itemAtIndex:0] setTitle:[name stringByAppendingString:@" [paused]"]];
    }
    else if([state isEqualToString:@"Stopped"]){
        [[menu itemAtIndex:0] setTitle:@"Ready"];
        [[menu itemAtIndex:1] setEnabled:false];
        [[menu itemAtIndex:2] setEnabled:false];
        [[menu itemAtIndex:3] setEnabled:false];
        [[menu itemAtIndex:1] setTitle:@"Love"];

        [GrowlApplicationBridge notifyWithTitle:@"Playlist Ended"
                                    description:@"The playlist came to its natural conclusion, I hope you enjoyed it :)"
                               notificationName:@"Playlist Ended"
                                       iconData:nil
                                       priority:0
                                       isSticky:false
                                   clickContext:nil];        
    }
}

-(void)growlNotificationWasClicked:(id)dict
{
    [[NSWorkspace sharedWorkspace] openURL:[lastfm urlForTrack:[dict objectForKey:@"Name"] by:[dict objectForKey:@"Artist"]]];
}

-(void)love:(id)sender
{
    [lastfm love:[[Mediator sharedMediator] currentTrack]];
    scrobsub_love();
    
    [[menu itemAtIndex:1] setEnabled:false];
    [[menu itemAtIndex:1] setTitle:@"Loved"];
}

-(void)tag:(id)sender
{
    [[[NSWindowController alloc] initWithWindowNibName:@"TagWindow"] showWindow:self];
}

-(void)share:(id)sender
{
}

-(void)menuWillOpen:(NSMenu*)target
{
    if(!metadataWindow)
        metadataWindow = [[NSWindowController alloc] initWithWindowNibName:@"MetadataWindow"];
    [metadataWindow showWindow:self];
}

-(void)menuDidClose:(NSMenu*)target
{
    [[metadataWindow window] performClose:self];
    [[metadataWindow window] orderOut:self];
}

@end
