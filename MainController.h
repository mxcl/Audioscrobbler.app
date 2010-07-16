/***************************************************************************
 *   Copyright 2005-2009 Last.fm Ltd.                                      *
 *   Copyright 2010 Max Howell <max@methylblue.com                         *
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

#import <Growl/GrowlApplicationBridge.h>
#import <Cocoa/Cocoa.h>
#import "lastfm.h"
#import "ITunesListener.h"
@class AutoDash;
@class ShareWindowController;


@interface MainController : NSObject <GrowlApplicationBridgeDelegate, LastfmDelegate, ITunesDelegate>
{
    NSStatusItem* status_item;
    IBOutlet NSMenu* menu;
    IBOutlet NSMenu* app_menu;
    IBOutlet NSMenu* history_menu;
    IBOutlet NSMenuItem* start_at_login;
    IBOutlet NSMenuItem* status;
    IBOutlet NSMenuItem* love;
    IBOutlet NSMenuItem* share;
    IBOutlet NSMenuItem* tag;
    IBOutlet NSMenuItem *lyrics;
    AutoDash* autodash;
    ITunesListener* listener;
    Lastfm* lastfm;
    ShareWindowController* sharewc;

    unsigned count;
}

-(IBAction)love:(id)sender;
-(IBAction)tag:(id)sender;
-(IBAction)share:(id)sender;
-(IBAction)startAtLogin:(id)sender;
-(IBAction)installDashboardWidget:(id)sender;
-(IBAction)activateAutoDash:(id)sender;
-(IBAction)about:(id)sender;
-(IBAction)moreRecentHistory:(id)sender;
-(IBAction)lyrics:(id)sender;

@end
