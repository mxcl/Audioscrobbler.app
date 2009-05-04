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
#import "MetadataWindowController.h"
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
    switch(event){
        case SCROBSUB_AUTH_REQUIRED:{
            char url[110];
            scrobsub_auth(url);
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithCString:url]]];
            break;}
        case SCROBSUB_ERROR_RESPONSE:
            NSLog(@"%s", message);
            break;
    }
}

static OSStatus MyHotKeyHandler(EventHandlerCallRef ref, EventRef e, void* userdata)
{
    EventHotKeyID hkid;
    GetEventParameter(e, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hkid), NULL, &hkid);
    switch(hkid.id){
        case 1:
            [(StatusItemController*)userdata tag:userdata];
            break;
        case 2:
            [(StatusItemController*)userdata share:userdata];
            break;
    }
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

    metadataWindow = [[MetadataWindowController alloc] init];
    [(NSPanel*)[metadataWindow window] setBecomesKeyOnlyIfNeeded:false];
    
/// global shortcut
    EventTypeSpec type;
    type.eventClass = kEventClassKeyboard;
    type.eventKind = kEventHotKeyPressed;    
    InstallApplicationEventHandler(&MyHotKeyHandler, 1, &type, self, NULL);

    EventHotKeyID kid;
    EventHotKeyRef kref;
    kid.signature='htk1';
    kid.id=1;
    RegisterEventHotKey(kVK_ANSI_T, cmdKey+optionKey+controlKey, kid, GetApplicationEventTarget(), 0, &kref);
    kid.signature='htk2';
    kid.id=2;
    RegisterEventHotKey(kVK_ANSI_S, cmdKey+optionKey+controlKey, kid, GetApplicationEventTarget(), 0, &kref);
}

-(bool)autohide
{
    return false;
}

-(void)onPlayerInfo:(NSNotification*)userData
{
    static uint count = 0;
    
    NSDictionary* dict = [userData userInfo];
    uint transition = [[dict objectForKey:@"Transition"] unsignedIntValue];
    NSString* name = [dict objectForKey:@"Name"];
    uint const duration = [(NSNumber*)[dict objectForKey:@"Total Time"] longLongValue];
    NSString* notificationName = @"Track Resumed";
    
#define UPDATE_TITLE_MENU \
    [[menu itemAtIndex:0] setTitle:[NSString stringWithFormat:@"%@ [%d:%02d]", name, duration/60, duration%60]];
    
    switch(transition){
        case TrackStarted:
            [[menu itemAtIndex:1] setEnabled:true];
            [[menu itemAtIndex:2] setEnabled:true];
            [[menu itemAtIndex:3] setEnabled:true];
            [[menu itemAtIndex:1] setTitle:@"Love"];
            notificationName = @"Track Started";
            if(![self autohide]) [metadataWindow showWindow:self];
            count++;
            // fall through
        case TrackResumed:{
            UPDATE_TITLE_MENU
            NSMutableString* desc = [[dict objectForKey:@"Artist"] mutableCopy];
            [desc appendString:@"\n"];
            [desc appendString:[dict objectForKey:@"Album"]];
            [GrowlApplicationBridge notifyWithTitle:name
                                        description:desc
                                   notificationName:notificationName
                                           iconData:[[dict objectForKey:@"Album Art"] TIFFRepresentation]
                                           priority:0
                                           isSticky:false
                                       clickContext:dict
                                         identifier:@"Coalesce Me ID"];
            break;}
        
        case TrackPaused:
            [[menu itemAtIndex:0] setTitle:[name stringByAppendingString:@" [paused]"]];
            [GrowlApplicationBridge notifyWithTitle:@"Playback Paused"
                                        description:[[dict objectForKey:@"Player Name"] stringByAppendingString:@" became paused"]
                                   notificationName:@"Track Paused"
                                           iconData:nil
                                           priority:0
                                           isSticky:true
                                       clickContext:dict
                                         identifier:@"Coalesce Me ID"];
            break;
            
        case PlaybackStopped:
            [[menu itemAtIndex:0] setTitle:@"Ready"];
            [[menu itemAtIndex:1] setEnabled:false];
            [[menu itemAtIndex:2] setEnabled:false];
            [[menu itemAtIndex:3] setEnabled:false];
            [[menu itemAtIndex:1] setTitle:@"Love"];
            
            NSNumberFormatter* formatter = [[NSNumberFormatter alloc] init];
            NSString* info = [NSString stringWithFormat:@"You played %@ tracks this session.",
                              [formatter stringFromNumber:[NSNumber numberWithUnsignedInt:count]]];
            [formatter release];
            count = 0;

            [GrowlApplicationBridge notifyWithTitle:@"Playlist Ended"
                                        description:info
                                   notificationName:@"Playlist Ended"
                                           iconData:nil
                                           priority:0
                                           isSticky:false
                                       clickContext:nil];
            [metadataWindow close];
            break;

        case TrackMetadataChanged:
            UPDATE_TITLE_MENU
            [GrowlApplicationBridge notifyWithTitle:@"Track Metadata Updated"
                                        description:[lastfm titleForTrack:dict]
                                   notificationName:@"Scrobble Submission Status"
                                           iconData:nil
                                           priority:-1
                                           isSticky:false
                                       clickContext:nil];
            break;
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
    NSWindowController* share = [[ShareWindowController alloc] initWithWindowNibName:@"ShareWindow"];
    [share showWindow:self];
    [[share window] makeKeyWindow];
}

-(IBAction)toggle:(id)sender
{
}

-(void)menuWillOpen:(NSMenu*)target
{
    if([[Mediator sharedMediator] currentTrack]){
        [[metadataWindow window] orderFront:self];
        [[metadataWindow window] makeKeyWindow];
    }
}

-(void)closeMetadataWindow
{
    if([self autohide])
        [metadataWindow close];
}

-(void)menuDidClose:(NSMenu*)target
{
    [self performSelector:@selector(closeMetadataWindow) withObject:nil afterDelay:0];
}

@end



@implementation ShareWindowController

-(void)submit:(id)sender
{
    [lastfm share:[[Mediator sharedMediator] currentTrack] with:[username stringValue]];
}

@end
