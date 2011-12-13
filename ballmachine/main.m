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

@interface NSURL(CCAdditions)
- (id)initFileURLWithPossiblyRelativePath:(NSString*)path isDirectory:(BOOL)isDir;
@end
@implementation NSURL(CCAdditions)
- (id)initFileURLWithPossiblyRelativePath:(NSString*)filePath isDirectory:(BOOL)isDir {
    if ([filePath hasPrefix:@"../"] || [filePath hasPrefix:@"./"]) {
        NSString* currentDirectoryPath = [[NSFileManager defaultManager] currentDirectoryPath];
        filePath = [currentDirectoryPath stringByAppendingPathComponent:[filePath stringByStandardizingPath]];
    }
    filePath = [filePath stringByStandardizingPath];

    self = [self initFileURLWithPath:filePath isDirectory:isDir];
    if (self) {
    }
    return self;
}
@end

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

#define MAX_FRAMERATE_DEFAULT 30.
#define CANVAS_WIDTH_DEFAULT 1280.
#define CANVAS_HEIGHT_DEFAULT 720.

@interface RenderSlave : NSObject <NSApplicationDelegate>
@property (nonatomic) CGFloat maximumFramerate;
@property (nonatomic) NSSize canvasSize;
@property (nonatomic, strong) QCRenderer* renderer;
@property (nonatomic, strong) RenderTimer* renderTimer;
@property (nonatomic) NSTimeInterval startTime;
- (id)initWithCompositionAtURL:(NSURL*)location maximumFramerate:(CGFloat)framerate canvasSize:(NSSize)size inputPairs:(NSDictionary*)inputs;
- (void)loadCompositionAtURL:(NSURL*)location withInputPairs:(NSDictionary*)inputs;
- (void)dumpAttributes;
- (void)startRendering;
- (void)stopRendering;
- (void)_render;
- (NSString*)_descriptionForKey:(NSString*)key;
@end

@implementation RenderSlave

@synthesize maximumFramerate, canvasSize, renderer, renderTimer, startTime;

- (id)initWithCompositionAtURL:(NSURL*)location maximumFramerate:(CGFloat)framerate canvasSize:(NSSize)size inputPairs:(NSDictionary*)inputs {
    self = [super init];
    if (self) {
        self.maximumFramerate = framerate ? framerate : MAX_FRAMERATE_DEFAULT;
        self.canvasSize = !NSEqualSizes(size, NSZeroSize) ? size : NSMakeSize(CANVAS_WIDTH_DEFAULT, CANVAS_HEIGHT_DEFAULT);
        [self loadCompositionAtURL:location withInputPairs:inputs];
    }
    return self;
}

- (void)dealloc {
    if (self.renderTimer) {
        [self stopRendering];
    }
}

- (void)loadCompositionAtURL:(NSURL*)location withInputPairs:(NSDictionary*)inputs {
    CCDebugLogSelector();

    QCComposition* composition = [QCComposition compositionWithFile:location.path];
    if (!composition) {
        CCErrorLog(@"ERROR - failed to create composition from path '%@'", location.path);
        exit(0);
    }

    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    self.renderer = [[QCRenderer alloc] initOffScreenWithSize:self.canvasSize colorSpace:rgbColorSpace composition:composition];
    CGColorSpaceRelease(rgbColorSpace);
    if (!self.renderer) {
        CCErrorLog(@"ERROR - failed to create renderer for composition %@", composition);
        exit(0);
    }

    // set inputs
    [inputs enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![[self.renderer inputKeys] containsObject:key]) {
            CCDebugLog(@"provided input key '%@' not found in composition and has been ignored...", key);
            return;
        }

        [self.renderer setValue:obj forInputKey:key];
    }];
}

- (void)dumpAttributes {
    printf("INPUT KEYS\n");
    if (self.renderer.inputKeys.count > 0) {
        [self.renderer.inputKeys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            printf("\t%s\n", [[self _descriptionForKey:(NSString*)obj] UTF8String]);
        }];
    } else {
        printf("\t--NONE--\n");
    }

    printf("OUTPUT KEYS\n");
    if (self.renderer.outputKeys.count > 0) {
        [self.renderer.outputKeys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            printf("\t%s\n", [[self _descriptionForKey:(NSString*)obj] UTF8String]);
        }];
    } else {
        printf("\t--NONE--\n");
    }

//    NSLog(@"%@", self.renderer.attributes);
}

- (void)startRendering {
    CCDebugLogSelector();

    self.renderTimer = [[RenderTimer alloc] initWithInterval:(1./self.maximumFramerate) do:^{
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
    if (!self.startTime)
        self.startTime = now;
    NSTimeInterval relativeTime = now - startTime;
    NSTimeInterval nextRenderTime = [renderer renderingTimeForTime:relativeTime arguments:nil];
//    CCDebugLog(@"now:%f relativeTime:%f nextRenderTime:%f", now, relativeTime, nextRenderTime);
    if (relativeTime >= nextRenderTime) {
//        CCDebugLog(@"\trendering");
        [renderer renderAtTime:relativeTime arguments:nil];

        // DEBUG WRITE UGLY IMAGES TO TMP
//        NSImage* image = [renderer snapshotImage];
//        NSData* tiffData = [image TIFFRepresentation];
//        NSURL* url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"/tmp/bm-%f.tif", now]];
//        [tiffData writeToURL:url atomically:NO];
    }
}

- (NSString*)_descriptionForKey:(NSString*)key {
    // TODO - this could be made much more rich
    //  default values
    //  min/max for numbers
    //  values for index
    NSDictionary* keyAttributes = [self.renderer.attributes objectForKey:key];
    NSString* description = nil;
    NSString* type = [keyAttributes objectForKey:QCPortAttributeTypeKey];
    NSObject* minValue = [keyAttributes objectForKey:QCPortAttributeMinimumValueKey];
    NSObject* maxValue = [keyAttributes objectForKey:QCPortAttributeMaximumValueKey];
    NSObject* defaultValue = [keyAttributes objectForKey:QCPortAttributeDefaultValueKey];

    description = [NSString stringWithFormat:@"%@ (%@)", key, type];
    if (minValue || maxValue) {
        description = [NSString stringWithFormat:@"%@ : %@-%@ %@", description, (minValue ? minValue : @"?"), (maxValue ? maxValue : @"?"), (defaultValue ? [NSString stringWithFormat:@"[%@]", defaultValue] : @"")];
    } else if (defaultValue) {
        description = [NSString stringWithFormat:@"%@ : [%@]", description, defaultValue];
    }

    return description;
}

@end

#pragma mark -

void usage(const char * argv[]);
void usage(const char * argv[]) {
    printf("usage: %s <composition> [options]\n", [[[NSString stringWithUTF8String:argv[0]] lastPathComponent] UTF8String]);
    printf("\nOPTIONS:\n");
    printf("\t--canvas-size\tset offscreen canvas size, E.g. '1920x1080'\n");
    printf("\t--max-framerate\tset maximum rendering framerate\n\n");
    printf("\t--print-attributes\tprint composition input keys and quit\n");
    printf("\t--inputs\tdefine key value pairs in JSON - ESCAPE LIKE MAD!\n\n");
    printf("\t--plugin-path\tprovide additional directory of plug-ins to load\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // source composition is required
        if (argc < 2) {
            usage(argv);
            return -1;
        }

        NSString* compositionFilePath = [NSString stringWithUTF8String:argv[1]];
        NSURL* compositionLocation = [[NSURL alloc] initFileURLWithPossiblyRelativePath:compositionFilePath isDirectory:NO];
        // double check
        if (![compositionLocation isFileURL]) {
            CCErrorLog(@"ERROR - filed to create URL for path '%@'", compositionFilePath);
            return -1;
        }
        NSError* error;
        if (![compositionLocation checkResourceIsReachableAndReturnError:&error]) {
            CCErrorLog(@"ERROR - bad source composition URL: %@", [error localizedDescription]);
            return -1;
        }

        // output size
        NSUserDefaults* args = [NSUserDefaults standardUserDefaults];
        NSString* sizeString = [args stringForKey:@"-canvas-size"];
        NSSize size = sizeString ? NSSizeFromString(sizeString) : NSZeroSize;

        // framerate
        CGFloat framerate = [args floatForKey:@"-max-framerate"];

        // print inputs
        BOOL shouldDumpAttributes = NO;
        for (NSUInteger idx = 2; idx < argc; idx++) {
            NSString* arg = [NSString stringWithUTF8String:argv[idx]];
            if (![arg isEqualToString:@"--print-attributes"])
                continue;
            shouldDumpAttributes = YES;
            break;
        }

        // inputs
        NSDictionary* inputs;
        NSString* inputValuesString = [args stringForKey:@"-inputs"];
        if (inputValuesString) {
            // strip leading and ending single quotes, i may just be command-line escape daft
            if ([inputValuesString hasPrefix:@"'"] && [inputValuesString hasSuffix:@"'"])
                inputValuesString = [inputValuesString substringWithRange:NSMakeRange(1, inputValuesString.length-2)];

            NSError* error;
            inputs = [NSJSONSerialization JSONObjectWithData:[inputValuesString dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers|NSJSONReadingMutableLeaves error:&error];
            if (error) {
                CCErrorLog(@"ERROR - failed to deserialize JSON - %@", [error localizedDescription]);
                usage(argv);
                return -1;
            }
            CCDebugLog(@"inputs:%@", inputs);
        }

        // extra plug-in folder
        NSString* plugInFolderPath = [args stringForKey:@"-plugin-path"];
        if (plugInFolderPath) {
            NSURL* plugInFolderLocation = [[NSURL alloc] initFileURLWithPossiblyRelativePath:plugInFolderPath isDirectory:NO];
            // double check
            if (![plugInFolderLocation isFileURL]) {
                CCErrorLog(@"ERROR - filed to create URL for path '%@'", plugInFolderPath);
                return -1;
            }
            if (![plugInFolderLocation checkResourceIsReachableAndReturnError:&error]) {
                CCErrorLog(@"ERROR - bad extra plug-in directory URL: %@", [error localizedDescription]);
                return -1;
            }

            NSArray* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[plugInFolderLocation path] error:&error];
            if (error) {
                CCErrorLog(@"ERROR - failed to get contents for plug-in directory - %@", [error localizedDescription]);
                return -1;
            }
            [contents enumerateObjectsUsingBlock:^(NSString* fileName, NSUInteger idx, BOOL *stop) {
                if (![fileName hasSuffix:@"plugin"])
                    return;

                NSURL* bundleLocation = [plugInFolderLocation URLByAppendingPathComponent:fileName];
                BOOL status = [QCPlugIn loadPlugInAtPath:[bundleLocation path]];
                if (!status) {
                    CCErrorLog(@"ERROR - failed to load bundle for plug-in %@", bundleLocation);
                    return;
                }
            }];
        }

        RenderSlave* renderSlave = [[RenderSlave alloc] initWithCompositionAtURL:compositionLocation maximumFramerate:framerate canvasSize:size inputPairs:inputs];
        if (shouldDumpAttributes) {
            [renderSlave dumpAttributes];
            return 0;
        }
        [renderSlave startRendering];

//        [[NSRunLoop currentRunLoop] run];
        // WORKAROUND - Syphon requires an application, it is unhappy otherwise!
        //  http://code.google.com/p/syphon-framework/issues/detail?id=18
        [[NSApplication sharedApplication] run];
    }
    return 0;
}
