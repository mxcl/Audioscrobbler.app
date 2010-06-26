// ctime 26/06/2010
#import "HighResolutionTimer.h"


@implementation HighResolutionTimer

-(id)initWithTarget:(id)o action:(SEL)s
{
    target = o;
    action = s;
    return self;
}

-(void)stop
{
    [[NSNotificationCenter defaultCenter] removeObserver:target
                                                    name:NSTaskDidTerminateNotification
                                                  object:task];
    [task interrupt];
    [task release];
    task = nil;
}

-(void)dealloc
{
    [self stop];
    [super dealloc];
}

-(void)scheduleWithTimeout:(NSTimeInterval)seconds
{
    [self stop];

    task = [[NSTask alloc] init];
    task.launchPath = @"/bin/sleep";
    task.arguments = [NSArray arrayWithObject:[NSString stringWithFormat:@"%f", seconds]];

    [[NSNotificationCenter defaultCenter] addObserver:target
                                             selector:action
                                                 name:NSTaskDidTerminateNotification
                                               object:task];
    [task launch];
}

-(void)pause {
    [task suspend];
}

-(void)resume {
    [task resume];
}

@end
