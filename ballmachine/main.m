//
//  main.m
//  ballmachine
//
//  Created by Jean-Pierre Mouilleseaux on 28 Oct 2011.
//  Copyright (c) 2011 Chorded Constructions. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Quartz/Quartz.h>
#import <mach/mach_time.h>

#ifdef DEBUG
    #define CCDebugLogSelector() NSLog(@"-[%@ %@]", /*NSStringFromClass([self class])*/self, NSStringFromSelector(_cmd))
    #define CCDebugLog(a...) NSLog(a)
    #define CCWarningLog(a...) NSLog(a)
    #define CCErrorLog(a...) NSLog(a)
#else
    #define CCDebugLogSelector()
    #define CCDebugLog(a...)
    #define CCWarningLog(a...) NSLog(a)
    #define CCErrorLog(a...) NSLog(a)
#endif

// based on a combo of watchdog timer and MABGTimer
//  http://www.fieryrobot.com/blog/2010/07/10/a-watchdog-timer-in-gcd/
//  http://www.mikeash.com/pyblog/friday-qa-2010-07-02-background-timers.html
@interface RenderTimer : NSObject {
    dispatch_source_t _timer;
    dispatch_queue_t _queue;
}
- (id)initWithInterval:(NSTimeInterval)interval do:(void (^)(void))block;
- (void)cancel;
+ (NSTimeInterval)now;
@end;
@implementation RenderTimer
- (id)initWithInterval:(NSTimeInterval)interval do:(void (^)(void))block {
    self = [super init];
    if (self) {
        // run on main queue for runloop love
        _queue = dispatch_get_main_queue();
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
        // NB - this fires after interval, not immediately
        dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval * NSEC_PER_SEC, 0);
        dispatch_source_set_event_handler(_timer, ^{
            @autoreleasepool {
                block();
            }
        });
        dispatch_resume(_timer);
    }
    return self;
}
- (void)dealloc {
    [self cancel];
}
- (void)cancel {
    dispatch_sync(_queue, ^{
        dispatch_source_cancel(_timer);
        dispatch_release(_timer);
        _timer = NULL;
    });
}
// in nanoseconds
+ (NSTimeInterval)now {
    static mach_timebase_info_data_t info;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        mach_timebase_info(&info);
    });

    NSTimeInterval t = mach_absolute_time();
    t *= info.numer;
    t /= info.denom;
    return t;
}
@end


@interface RenderSlave : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) QCRenderer* renderer;
@property (nonatomic, strong) RenderTimer* renderTimer;
@property (nonatomic) NSTimeInterval startTime;
- (void)loadCompositionAtURL:(NSURL*)location;
- (void)startRendering;
- (void)stopRendering;
- (void)_render;
@end

@implementation RenderSlave

@synthesize renderer, renderTimer, startTime;

- (void)dealloc {
    [self stopRendering];
}

- (void)loadCompositionAtURL:(NSURL*)location {
    CCDebugLogSelector();

    QCComposition* composition = [QCComposition compositionWithFile:location.path];
    if (!composition) {
        CCErrorLog(@"ERROR - failed to create composition from path '%@'", location.path);
        exit(0);
    }

    // TODO - make size a settable value
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    self.renderer = [[QCRenderer alloc] initOffScreenWithSize:NSMakeSize(1280, 720) colorSpace:rgbColorSpace composition:composition];
    CGColorSpaceRelease(rgbColorSpace);
    if (!self.renderer) {
        CCErrorLog(@"ERROR - failed to create renderer for composition %@", composition);
        exit(0);
    }
}

- (void)startRendering {
    CCDebugLogSelector();

    // TODO - make framerate settable
    self.renderTimer = [[RenderTimer alloc] initWithInterval:(1./60.) do:^{
        [self _render];
    }];
}

- (void)stopRendering {
    CCDebugLogSelector();

    self.renderTimer = nil;
    self.startTime = 0;
}

- (void)_render {
//    CCDebugLogSelector();

    NSTimeInterval now = [RenderTimer now] / NSEC_PER_SEC;
    if (!self.startTime) {
        CCDebugLog(@"setting startTime");
        self.startTime = now;
    }
    NSTimeInterval relativeTime = now - startTime;
    NSTimeInterval nextRenderTime = [renderer renderingTimeForTime:relativeTime arguments:nil];
    CCDebugLog(@"now:%f relativeTime:%f nextRenderTime:%f", now, relativeTime, nextRenderTime);
    if (relativeTime >= nextRenderTime) {
        CCDebugLog(@"\trendering");
        [renderer renderAtTime:relativeTime arguments:nil];

        // DEBUG WRITE UGLY IMAGES TO TMP
//        NSImage* image = [renderer snapshotImage];
//        NSData* tiffData = [image TIFFRepresentation];
//        NSURL* url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"/tmp/bm-%f.tif", now]];
//        [tiffData writeToURL:url atomically:NO];
    }
}

@end

#pragma mark -

int main (int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            CCErrorLog(@"usage: %@ <composition>", [[NSString stringWithUTF8String:argv[0]] lastPathComponent]);
            return -1;
        }

        NSString* filePath = [[NSString stringWithUTF8String:argv[1]] stringByExpandingTildeInPath];
        NSURL* url = [NSURL URLWithString:filePath];
        if (![url isFileURL]) {
            NSString* path = [filePath stringByStandardizingPath];
            if ([path isAbsolutePath]) {
                url = [NSURL fileURLWithPath:path isDirectory:NO];
            } else {
                // relative path
                NSString* currentDirectoryPath = [[NSFileManager defaultManager] currentDirectoryPath];
                NSString* resolvedFilePath = [currentDirectoryPath stringByAppendingPathComponent:[filePath stringByStandardizingPath]];
                url = [NSURL fileURLWithPath:resolvedFilePath isDirectory:NO];
            }
        }
        // double check
        if (![url isFileURL]) {
            CCErrorLog(@"ERROR - filed to create URL for path '%@'", filePath);
            return -1;
        }

        NSError* error;
        if (![url checkResourceIsReachableAndReturnError:&error]) {
            CCErrorLog(@"ERROR - bad source composition URL: %@", [error localizedDescription]);
            return -1;
        }

        RenderSlave* renderSlave = [[RenderSlave alloc] init];
        [renderSlave loadCompositionAtURL:url];
        [renderSlave startRendering];

//        [[NSRunLoop currentRunLoop] run];
        CFRunLoopRun();
    }
    return 0;
}
