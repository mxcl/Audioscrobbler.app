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
// References:
//    http://ryanhomer.com/blog/2007/05/31/detecting-when-your-cocoa-application-is-idle/
//    http://meeu.me/blog/dashboard-expose-spaces/

#import "AutoDash.h"
#define INTERVAL 240
#define MAKE_TIMER(interval) timer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(check) userInfo:nil repeats:NO]

void CoreDockSendNotification(NSString *notificationName); // not public, but prolly safe

@interface AutoDash(Private)
-(void)check;
-(uint32_t)systemIdleTime;
@end


@implementation AutoDash

-(id)init
{
    self = [super init];

	mach_port_t port;
    IOMasterPort(MACH_PORT_NULL, &port);
    io_iterator_t io_iterator;
    IOServiceGetMatchingServices(port, IOServiceMatching("IOHIDSystem"), &io_iterator);
    io_obj = IOIteratorNext(io_iterator);
    IOObjectRelease(io_iterator);

    MAKE_TIMER(INTERVAL);

    return self;
}

-(void)dealloc
{
	IOObjectRelease(io_obj);
    [timer invalidate];
	[super dealloc];
}

-(void)check
{
    uint32_t const idletime = [self systemIdleTime];
    uint32_t next_time;
    
    if (idletime >= INTERVAL){
        CoreDockSendNotification(@"com.apple.dashboard.awake");
        // until we can know when the dashboard is deactivated, we have to keep
        // making timers and activating the dashboard
        next_time = INTERVAL;
    }
    else
        next_time = INTERVAL - idletime;
    
    MAKE_TIMER(next_time);
}

-(uint32_t)systemIdleTime
{
    CFMutableDictionaryRef properties = 0;	
	if (IORegistryEntryCreateCFProperties(io_obj, &properties, kCFAllocatorDefault, 0) != KERN_SUCCESS || properties == NULL) 
        return 0;

    uint64_t t = 0;

	CFTypeRef o = CFDictionaryGetValue(properties, CFSTR("HIDIdleTime"));
    if (o == NULL)
        goto exit;
	
	CFTypeID type = CFGetTypeID(o);		
	if (type == CFDataGetTypeID())
		CFDataGetBytes((CFDataRef)o, CFRangeMake(0, sizeof(t)), (UInt8*) &t);
	else if (type == CFNumberGetTypeID())
		CFNumberGetValue((CFNumberRef)o, kCFNumberSInt64Type, &t);

	t >>= 30; // essentially divides by 10^9 (nanoseconds)

exit:
	CFRelease((CFTypeRef)properties);
	return t;
}

@end
