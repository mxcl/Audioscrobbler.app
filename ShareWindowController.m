// Created by Max Howell on 19/06/2010.
#import "ShareWindowController.h"
#import "lastfm.h"


@implementation ShareWindowController

@synthesize track;
@synthesize lastfm;

-(void)submit:(id)sender
{
    [spinner startAnimation:self];
    [lastfm share:track with:[username stringValue]];
    [self close];
    [spinner stopAnimation:self];
}

-(void)showWindow:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES]; //see above about:
    [super showWindow:sender];
}

@end
