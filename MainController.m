/***************************************************************************
 *   Copyright 2005-2009 Last.fm Ltd.                                      *
 *   Copyright 2010 Max Howell <max@methylblue.com>                        *
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

#import "AutoDash.h"
#import "ITunesListener.h"
#import "lastfm.h"
#import "MainController.h"
#import "NSDictionary+Track.h"
#import "ShareWindowController.h"
#import <Carbon/Carbon.h>
#import <WebKit/WebKit.h>


static bool scrobsub_fsref(FSRef* fsref)
{
    OSStatus err = LSFindApplicationForInfo(kLSUnknownCreator, CFSTR("fm.last.Audioscrobbler"), NULL, fsref, NULL);
    return err != kLSApplicationNotFoundErr;
}


static OSStatus MyHotKeyHandler(EventHandlerCallRef ref, EventRef e, void* userdata)
{
    EventHotKeyID hkid;
    GetEventParameter(e, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hkid), NULL, &hkid);
    switch(hkid.id){
        case 1:
            [(MainController*)userdata tag:userdata];
            break;
        case 2:
            [(MainController*)userdata share:userdata];
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

static NSString* downloads()
{
    NSString* path = [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];
    BOOL isdir = false;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isdir] && isdir)
        return path;
    
    return NSTemporaryDirectory();
}


@implementation MainController

+(void)initialize
{
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary
                                                             dictionaryWithObject:[NSNumber numberWithBool:false]
                                                             forKey:@"AutoDash"]];
}

-(NSDictionary*)registrationDictionaryForGrowl
{
    NSArray* all = [NSArray arrayWithObjects:
                    ASGrowlTrackStarted,
                    ASGrowlTrackPaused,
                    ASGrowlTrackResumed,
                    ASGrowlPlaylistEnded,
                    ASGrowlLoveTrackQuery,
                    ASGrowlAuthenticationRequired,
                    ASGrowlErrorCommunication,
                    ASGrowlCorrectionSuggestion,
                    ASGrowlTrackIgnored,
                    nil];
    NSArray* defaults = [NSArray arrayWithObjects:
                         ASGrowlTrackStarted,
                         ASGrowlTrackResumed,
                         ASGrowlPlaylistEnded,
                         ASGrowlLoveTrackQuery,
                         ASGrowlAuthenticationRequired,
                         ASGrowlErrorCommunication,
                         ASGrowlCorrectionSuggestion,
                         ASGrowlTrackIgnored,
                         nil];
    return [NSDictionary dictionaryWithObjectsAndKeys:
            all, GROWL_NOTIFICATIONS_ALL, 
            defaults, GROWL_NOTIFICATIONS_DEFAULT, 
            nil];
}

-(void)awakeFromNib
{
    status_item = [[[NSStatusBar systemStatusBar] statusItemWithLength:27] retain];
    [status_item setHighlightMode:YES];
    [status_item setImage:[NSImage imageNamed:@"icon.png"]];
    [status_item setAlternateImage:[NSImage imageNamed:@"inverted_icon.png"]];
    [status_item setEnabled:YES];
    [status_item setMenu:menu];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPlayerInfo:)
                                                 name:@"playerInfo"
                                               object:nil];

    [GrowlApplicationBridge setGrowlDelegate:self];

    if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"AutoDash"] boolValue] == true)
        autodash = [[AutoDash alloc] init];

    [NSApp setMainMenu:app_menu]; // so the close shortcut will work
    
/// Start at Login item
    LSSharedFileListRef login_items_ref = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if(login_items_ref){
        LSSharedFileListItemRef login_item = audioscrobbler_session_login_item(login_items_ref);
        [start_at_login setState:login_item?NSOnState:NSOffState];
        CFRelease(login_items_ref);
    }

#if __AS_DEBUGGING__
    [[menu itemAtIndex:[menu numberOfItems]-1] setTitle:@"Quit Debugscrobbler"];
#else
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
#endif

    lastfm = [[Lastfm alloc] initWithDelegate:self];
    listener = [[ITunesListener alloc] initWithLastfm:lastfm];
}

-(void)dealloc
{
    [sharewc release];
    [listener release];
    [lastfm release];
    [autodash release];
    [status_item release];
    [super dealloc];
}

-(bool)autohide
{
    return false;
}

-(void)onPlayerInfo:(NSNotification*)userData
{
    NSDictionary* track = userData.userInfo;
    uint transition = [[track objectForKey:@"Transition"] unsignedIntValue];
    NSString* notificationName = ASGrowlTrackResumed;
    
#define UPDATE_TITLE_MENU { unsigned duration = track.duration; \
    [status setTitle:[NSString stringWithFormat:@"%@ [%d:%02d]", track.title, duration/60, duration%60]]; }
    
    switch(transition){
        case TrackStarted:
            [love setEnabled:true];
            [love setTitle:@"Love"];
            [share setEnabled:true];
            [tag setEnabled:true];
            notificationName = ASGrowlTrackStarted;
            count++;
            // fall through
        case TrackResumed:{
            UPDATE_TITLE_MENU
            NSMutableString* desc = [[[track objectForKey:@"Artist"] mutableCopy] autorelease];
            [desc appendString:@"\n"];
            [desc appendString:[track objectForKey:@"Album"]];
            [GrowlApplicationBridge notifyWithTitle:track.title
                                        description:desc
                                   notificationName:notificationName
                                           iconData:[track objectForKey:@"Album Art"]
                                           priority:0
                                           isSticky:false
                                       clickContext:track
                                         identifier:ASGrowlTrackStarted];
            break;}
        
        case TrackPaused:
            [status setTitle:[track.title stringByAppendingString:@" [paused]"]];
            [GrowlApplicationBridge notifyWithTitle:@"Playback Paused"
                                        description:@"iTunes was paused"
                                   notificationName:ASGrowlTrackPaused
                                           iconData:nil
                                           priority:0
                                           isSticky:true
                                       clickContext:track
                                         identifier:ASGrowlTrackStarted];
            break;
            
        case PlaybackStopped:
            [status setTitle:@"Ready"];
            [love setEnabled:false];
            [tag setEnabled:false];
            [share setEnabled:false];
            [love setTitle:@"Love"];
            
            NSNumberFormatter* formatter = [[NSNumberFormatter alloc] init];
            NSString* info = [NSString stringWithFormat:@"You played %@ tracks this session.",
                              [formatter stringFromNumber:[NSNumber numberWithUnsignedInt:count]]];
            [formatter release];
            count = 0;

            [GrowlApplicationBridge notifyWithTitle:@"Playlist Ended"
                                        description:info
                                   notificationName:ASGrowlPlaylistEnded
                                           iconData:nil
                                           priority:0
                                           isSticky:false
                                       clickContext:nil];
            break;

        case TrackMetadataChanged:
            UPDATE_TITLE_MENU
            [GrowlApplicationBridge notifyWithTitle:@"Track Metadata Updated"
                                        description:track.prettyTitle
                                   notificationName:ASGrowlSubmissionStatus
                                           iconData:nil
                                           priority:-1
                                           isSticky:false
                                       clickContext:nil];
            break;
    }
}

-(void)lastfm:(Lastfm*)lastfm requiresAuth:(NSURL*)url
{
    if (![GrowlApplicationBridge isGrowlInstalled] || ![GrowlApplicationBridge isGrowlRunning]) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    [GrowlApplicationBridge notifyWithTitle:@"Authentication Required"
                                description:@"Before you can scrobble, Last.fm want you to approve this app at their website. Click here to open your browser at the authorisation page."
                           notificationName:ASGrowlAuthenticationRequired
                                   iconData:nil
                                   priority:1
                                   isSticky:true
                               clickContext:[url absoluteString] // for some fucked up reason, this had to be a string
                                 identifier:ASGrowlAuthenticationRequired];
}

-(void)lastfm:(Lastfm*)lastfm errorCode:(int)code errorMessage:(NSString*)message
{
    [GrowlApplicationBridge notifyWithTitle:[NSString stringWithFormat:@"Error Code %d", code]
                                description:message
                           notificationName:ASGrowlErrorCommunication
                                   iconData:nil
                                   priority:2
                                   isSticky:false
                               clickContext:nil
                                 identifier:[message stringByAppendingString:ASGrowlErrorCommunication]];
}

-(void)lastfm:(Lastfm*)lastfm metadata:(NSDictionary*)metadata betterdata:(NSDictionary*)betterdata
{
    [GrowlApplicationBridge notifyWithTitle:@"Suggested Metadata Correction"
                                description:betterdata.prettyTitle
                           notificationName:ASGrowlCorrectionSuggestion
                                   iconData:nil
                                   priority:-1
                                   isSticky:false
                               clickContext:nil];
}

-(void)lastfm:(Lastfm*)lastfm scrobbled:(NSDictionary*)track failureMessage:(NSString*)message
{
    NSMenuItem* item = [history_menu itemAtIndex:0];
    if(false == [item isEnabled])
        [history_menu removeItem:item];
    
    NSString* title = track.prettyTitle;
    if (message)
        title = [title stringByAppendingFormat:@" (Failed: %@)", message];
    else
        title = [title stringByAppendingFormat:@" (OK)"];
    
    item = [[NSMenuItem alloc] initWithTitle:title action:@selector(historyItemClicked:) keyEquivalent:@""];
    [item setTarget:self];
    [item setRepresentedObject:track.url];
    [history_menu insertItem:item atIndex:0];
    [item release];
    
    // 18 items is about an hour
    if([history_menu numberOfItems] > 18)
        [history_menu removeItemAtIndex:15];
}

-(void)historyItemClicked:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[sender representedObject]];
}

-(void)growlNotificationWasClicked:(id)dict
{
    if ([dict isKindOfClass:[NSString class]])
    {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:dict]];
    }
    else if([[dict objectForKey:@"Notification Name"] isEqualToString:ASGrowlLoveTrackQuery])
    {
        if (listener.track.pid == [dict pid])
            [self love:self];
        else
            [lastfm love:dict];
        // TODO need some kind of feedback
    }
    else
        [[NSWorkspace sharedWorkspace] openURL:[dict url]];
}

-(IBAction)love:(id)sender
{
    [lastfm love:listener.track];
    [love setEnabled:false];
    [love setTitle:@"Loved"];
}

-(IBAction)tag:(id)sender
{
    NSURL* url = listener.track.url;
    NSString* path = [[url path] stringByAppendingPathComponent:@"+tags"];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:path relativeToURL:url]];
}

-(IBAction)share:(id)sender
{
    if(!sharewc)
        sharewc = [[ShareWindowController alloc] initWithWindowNibName:@"ShareWindow"];
    [sharewc showWindow:self];
    [sharewc setTrack:listener.track];
    [sharewc setLastfm:lastfm];
    [sharewc.window makeKeyWindow];
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

-(IBAction)installDashboardWidget:(id)sender
{
    NSString* bz2 = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Last.fm.wdgt.tar.bz2"];
    
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/tar"];
    [task setCurrentDirectoryPath:downloads()];
    [task setArguments:[NSArray arrayWithObjects:@"xf", bz2, nil]];
    [task launch];
    [task waitUntilExit];
    
    [[NSWorkspace sharedWorkspace] openFile:[[task currentDirectoryPath] stringByAppendingPathComponent:@"Last.fm.wdgt"]];
    [task release];
}

-(IBAction)activateAutoDash:(id)sender
{
    if ([sender state] == NSOnState)
        autodash = [[AutoDash alloc] init];
    else
        [autodash release];
}

-(IBAction)about:(id)sender
{
    // http://www.cocoadev.com/index.pl?NSStatusItem
    // LSUIElement screws up Window ordering
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:sender];
}

-(IBAction)moreRecentHistory:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[Lastfm urlForUser:[lastfm username]]];
}

@end
