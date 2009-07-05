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
extern bool scrobsub_fsref(FSRef*);


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

static LSSharedFileListItemRef audioscrobbler_session_login_item(LSSharedFileListRef login_items_ref)
{
    FSRef as_fsref;
    if (!scrobsub_fsref(&as_fsref))
        return NULL;
    UInt32 seed;
    NSArray *items = [(NSArray*)LSSharedFileListCopySnapshot(login_items_ref, &seed) autorelease];
    for (id id in items){
        FSRef fsref;
        LSSharedFileListItemRef item = (LSSharedFileListItemRef)id;
        if (LSSharedFileListItemResolve(item, 0, NULL, &fsref) == noErr)
            if (FSCompareFSRefs(&as_fsref, &fsref) == noErr)
                return item;
    }
    return NULL;        
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

    [GrowlApplicationBridge setGrowlDelegate:self];

/// Start at Login item
    LSSharedFileListRef login_items_ref = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if(login_items_ref){
        LSSharedFileListItemRef login_item = audioscrobbler_session_login_item(login_items_ref);
        [start_at_login setState:login_item?NSOnState:NSOffState];
        CFRelease(login_items_ref);
    }
    
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

-(IBAction)love:(id)sender
{
    [lastfm love:[[Mediator sharedMediator] currentTrack]];
    scrobsub_love();
    
    [[menu itemAtIndex:1] setEnabled:false];
    [[menu itemAtIndex:1] setTitle:@"Loved"];
}

-(IBAction)tag:(id)sender
{
    NSDictionary* t = [[Mediator sharedMediator] currentTrack];
    NSURL* url = [lastfm urlForTrack:[t objectForKey:@"Name"] by:[t objectForKey:@"Artist"]];
    NSString* path = [[url path] stringByAppendingPathComponent:@"+tags"];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:path relativeToURL:url]];
}

-(IBAction)share:(id)sender
{
    NSWindowController* share = [[ShareWindowController alloc] initWithWindowNibName:@"ShareWindow"];
    [share showWindow:self];
    [[share window] makeKeyWindow];
}

-(IBAction)startAtLogin:(id)sender
{
    FSRef fsref;
    if (!scrobsub_fsref(&fsref)) return;
    LSSharedFileListRef login_items_ref = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (login_items_ref == NULL) return;
    
    LSSharedFileListItemRef item;
    if (NSOffState == [sender state]){
        item = LSSharedFileListInsertItemFSRef(login_items_ref,
                                               kLSSharedFileListItemLast,
                                               NULL, // name
                                               NULL, // icon
                                               &fsref,
                                               NULL, NULL);
        if (item){
            [sender setState:NSOnState];
            CFRelease(item);
        }
    }
    else if (item = audioscrobbler_session_login_item(login_items_ref)){
        LSSharedFileListItemRemove(login_items_ref, item);
        [sender setState:NSOffState];
    }
    
    CFRelease(login_items_ref);
}

@end



@implementation ShareWindowController

-(void)submit:(id)sender
{
    [lastfm share:[[Mediator sharedMediator] currentTrack] with:[username stringValue]];
}

@end
