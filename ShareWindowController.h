// Created by Max Howell on 19/06/2010.
#import <Cocoa/Cocoa.h>
@class Lastfm;


@interface ShareWindowController:NSWindowController
{
    IBOutlet NSProgressIndicator* spinner; 
    IBOutlet NSTextField* username;
    NSDictionary* track;
    Lastfm* lastfm;
}

@property(nonatomic, retain) NSDictionary* track;
@property(nonatomic, retain) Lastfm* lastfm;

-(IBAction)submit:(id)sender;

@end
