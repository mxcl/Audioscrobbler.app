// ctime 26/06/2010

#import <Foundation/Foundation.h>


@interface HighResolutionTimer : NSObject {
    id target;
    SEL action;
    NSTask* task;
}

-(id)initWithTarget:(id)object action:(SEL)selector;
-(void)scheduleWithTimeout:(NSTimeInterval)seconds;
-(void)pause;
-(void)resume;
-(void)stop;
@end
