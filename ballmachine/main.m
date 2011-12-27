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
#import <OpenGL/CGLRenderers.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>


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

#define VERSION "v0.3.0-pre"

// NB - avoid the long arm of ARC
NSWindow* window = nil;
IOPMAssertionID assertionID = kIOPMNullAssertionID;

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
- (void)performWhileLocked:(dispatch_block_t)block;
- (void)_cancel;
@end
@implementation RenderTimer
- (id)initWithInterval:(NSTimeInterval)interval do:(void (^)(void))block {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.chordedconstructions.fleshworld.ballmachine", NULL);
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
    [self _cancel];
}
- (void)cancel {
    [self performWhileLocked:^{
        [self _cancel];
    }];
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
- (void)performWhileLocked:(dispatch_block_t)block {
    dispatch_sync(_queue, block);
}
- (void)_cancel {
    dispatch_source_cancel(_timer);
    dispatch_release(_timer);
    _timer = NULL;

    dispatch_release(_queue);
    _queue = NULL;
}
@end

#define MAX_FRAMERATE_OFFLINE_DEFAULT 30.
#define CANVAS_WIDTH_OFFLINE_DEFAULT 1280.
#define CANVAS_HEIGHT_OFFLINE_DEFAULT 720.

@interface RenderSlave : NSObject
@property (nonatomic) CGFloat maximumFramerate;
@property (nonatomic) NSSize canvasSize;
@property (nonatomic, strong) QCRenderer* renderer;
@property (nonatomic, strong) RenderTimer* renderTimer;
@property (nonatomic) NSTimeInterval startTime;
@property (nonatomic, strong) NSOpenGLContext* context;
@property (nonatomic, strong) NSOpenGLPixelFormat* pixelFormat;
@property (nonatomic, getter=isRendering) BOOL rendering;
- (id)initWithContext:(NSOpenGLContext*)context pixelFormat:(NSOpenGLPixelFormat*)pixelFormat composition:(NSURL*)location maximumFramerate:(CGFloat)framerate canvasSize:(NSSize)size inputPairs:(NSDictionary*)inputs;
- (void)loadCompositionAtURL:(NSURL*)location withInputPairs:(NSDictionary*)inputs;
- (void)printCompositionAttributes;
- (void)startRendering;
- (void)stopRendering;
- (void)teardown;
- (void)_render;
- (NSString*)_portDescriptionForKey:(NSString*)key;
@end

@implementation RenderSlave

@synthesize maximumFramerate, canvasSize, renderer, renderTimer, startTime, context, pixelFormat, rendering;

- (id)initWithContext:(NSOpenGLContext*)ctx pixelFormat:(NSOpenGLPixelFormat*)format composition:(NSURL*)location maximumFramerate:(CGFloat)framerate canvasSize:(NSSize)size inputPairs:(NSDictionary*)inputs {
    self = [super init];
    if (self) {
        self.context = ctx;
        self.pixelFormat = format;
        self.maximumFramerate = framerate ? framerate : MAX_FRAMERATE_OFFLINE_DEFAULT;
        self.canvasSize = !NSEqualSizes(size, NSZeroSize) ? size : NSMakeSize(CANVAS_WIDTH_OFFLINE_DEFAULT, CANVAS_HEIGHT_OFFLINE_DEFAULT);
        [self loadCompositionAtURL:location withInputPairs:inputs];
    }
    return self;
}

- (void)dealloc {
    CCDebugLogSelector();

    [self teardown];
}

- (void)loadCompositionAtURL:(NSURL*)location withInputPairs:(NSDictionary*)inputs {
    CCDebugLogSelector();

    QCComposition* composition = [QCComposition compositionWithFile:location.path];
    if (!composition) {
        CCErrorLog(@"ERROR - failed to create composition from path '%@'", location.path);
        exit(EXIT_FAILURE);
    }

    // online render
    if (self.context) {
        // TODO - the colorspace should come from the display
        self.renderer = [[QCRenderer alloc] initWithCGLContext:[self.context CGLContextObj] pixelFormat:[self.pixelFormat CGLPixelFormatObj] colorSpace:NULL composition:composition];
        if (!self.renderer) {
            CCErrorLog(@"ERROR - failed to create online renderer for composition %@", composition);
            exit(EXIT_FAILURE);
        }
    }
    // offline render
    else {
        self.renderer = [[QCRenderer alloc] initOffScreenWithSize:self.canvasSize colorSpace:NULL composition:composition];
        if (!self.renderer) {
            CCErrorLog(@"ERROR - failed to create renderer for composition %@", composition);
            exit(EXIT_FAILURE);
        }
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

- (void)printCompositionAttributes {
    printf("INPUT KEYS\n");
    if (self.renderer.inputKeys.count > 0) {
        [self.renderer.inputKeys enumerateObjectsUsingBlock:^(NSString* key, NSUInteger idx, BOOL *stop) {
            printf("\t%s\n", [[self _portDescriptionForKey:key] UTF8String]);
        }];
    } else {
        printf("\t--NONE--\n");
    }

    printf("OUTPUT KEYS\n");
    if (self.renderer.outputKeys.count > 0) {
        [self.renderer.outputKeys enumerateObjectsUsingBlock:^(NSString* key, NSUInteger idx, BOOL *stop) {
            printf("\t%s\n", [[self _portDescriptionForKey:key] UTF8String]);
        }];
    } else {
        printf("\t--NONE--\n");
    }

//    NSLog(@"%@", self.renderer.attributes);
}

- (void)startRendering {
    CCDebugLogSelector();

    if (self.isRendering) {
        CCWarningLog(@"WARNING - already rendering");
        return;
    }

    self.rendering = YES;
    self.renderTimer = [[RenderTimer alloc] initWithInterval:(1./self.maximumFramerate) do:^{
        [self _render];
    }];
}

- (void)stopRendering {
    CCDebugLogSelector();

    if (!self.isRendering)
        return;

    self.rendering = NO;
    self.renderTimer = nil;
    self.startTime = 0;
}

- (void)teardown {
    CCDebugLogSelector();

    if (self.isRendering)
        [self stopRendering];

    [self.context clearDrawable];
    self.context = nil;
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

        if (self.context) {
            CGLLockContext([self.context CGLContextObj]);
        }

        [renderer renderAtTime:relativeTime arguments:nil];

        if (self.context) {
            [self.context flushBuffer];
            CGLUnlockContext([self.context CGLContextObj]);            
        }
    }
}

- (NSString*)_portDescriptionForKey:(NSString*)key {
    // TODO - this could be made much more rich
    //  default values
    //  min/max for numbers
    //  values for index
    NSDictionary* keyAttributes = [self.renderer.attributes objectForKey:key];
    NSString* type = [keyAttributes objectForKey:QCPortAttributeTypeKey];
    NSObject* minValue = [keyAttributes objectForKey:QCPortAttributeMinimumValueKey];
    NSObject* maxValue = [keyAttributes objectForKey:QCPortAttributeMaximumValueKey];
    NSObject* defaultValue = [keyAttributes objectForKey:QCPortAttributeDefaultValueKey];
    NSObject* value = [self.renderer valueForInputKey:key];

    NSString* description = [NSString stringWithFormat:@"%@ / %@ : %@%@%@", key, type, (minValue || maxValue ? [NSString stringWithFormat:@"[%@-%@]", (minValue ? minValue : @"?"), (maxValue ? maxValue : @"?")] : @""), (defaultValue ? [NSString stringWithFormat:@" (%@)", defaultValue] : @""), (value ? [NSString stringWithFormat:@" %@", value] : @"")];
    return description;
}

@end

#pragma mark -

void usage(const char * argv[]);
void usage(const char * argv[]) {
    NSString* name = [[NSString stringWithUTF8String:argv[0]] lastPathComponent];
    printf("usage: %s <composition> [options]\n", [name UTF8String]);
    printf("\nOPTIONS:\n");
    printf("  --version\t\tprint %s's version\n\n", [name UTF8String]);
    printf("  --print-attributes\tprint composition port details\n");
    printf("  --inputs=pairs\tdefine input key-value pairs in JSON, ESCAPE LIKE MAD!\n\n");
    printf("  --canvas-size=val\tset canvas size, E.g. '1920x1080'\n");
    printf("  --max-framerate=val\tset maximum rendering framerate\n\n");
    printf("  --plugin-path=path\tadditional directory of plug-ins to load\n\n");
    printf("  --print-displays\tprint descriptions for available displays\n");
    printf("  --display=val\t\tset display unit number composition will be drawn to\n");
    printf("  --window-server\trun with a window server connection\n");
}
void printVersion(const char * argv[]);
void printVersion(const char * argv[]) {
    printf("%s %s\n", [[[NSString stringWithUTF8String:argv[0]] lastPathComponent] UTF8String], VERSION);
}
NSString* nameForDisplayID(CGDirectDisplayID displayID);
NSString* nameForDisplayID(CGDirectDisplayID displayID) {
    NSString* screenName;
    
    NSDictionary* deviceInfo = (__bridge_transfer NSDictionary*)IODisplayCreateInfoDictionary(CGDisplayIOServicePort(displayID), kIODisplayOnlyPreferredName);
    NSDictionary* localizedNames = [deviceInfo objectForKey:[NSString stringWithUTF8String:kDisplayProductName]];
    
    if ([localizedNames count] > 0)
        screenName = [localizedNames objectForKey:[[localizedNames allKeys] objectAtIndex:0]];
    
    return screenName;
}
int printDisplays(void);
int printDisplays(void) {
    uint32_t displayCount;
    CGError error = CGGetOnlineDisplayList(0, NULL, &displayCount);
    if (error != kCGErrorSuccess) {
        CCErrorLog(@"ERROR - failed to get online display list");
        return 1;
    }
    CGDirectDisplayID* displays = (CGDirectDisplayID*)calloc(displayCount, sizeof(CGDirectDisplayID));
    error = CGGetOnlineDisplayList(displayCount, displays, &displayCount);
    if (error != kCGErrorSuccess) {
        CCErrorLog(@"ERROR - failed to get online display list");
        free(displays);
        return 1;
    }

    for (NSUInteger idx = 0; idx < displayCount; idx++) {
        CGDirectDisplayID display = displays[idx];
        CGSize displaySize = CGDisplayBounds(display).size;
        BOOL isMain = CGDisplayIsMain(display);
        BOOL isAccelerated = CGDisplayUsesOpenGLAcceleration(display);
        NSString* description = [NSString stringWithFormat:@"%u - %@ %0.fx%0.f%@%@", CGDisplayUnitNumber(display), nameForDisplayID(display), displaySize.width, displaySize.height, (isMain ? @" (MAIN)" : @""), (!isAccelerated ? @" [UNACCELERATED]" : @"")];
        printf("%s\n", [description UTF8String]);
    }
    free(displays);

//    [[NSScreen screens] enumerateObjectsUsingBlock:^(NSScreen* screen, NSUInteger idx, BOOL *stop) {
//        printf("%lu - \n", idx);
//        CCDebugLog(@"%@ - %@\n", screen, screen.deviceDescription);
//    }];

    return 0;
}
BOOL displayForUnitNumber(uint32_t unitNumber, CGDirectDisplayID* displayID);
BOOL displayForUnitNumber(uint32_t unitNumber, CGDirectDisplayID* displayID) {
    BOOL status = NO;

    uint32_t displayCount;
    CGError error = CGGetOnlineDisplayList(0, NULL, &displayCount);
    if (error != kCGErrorSuccess) {
        CCErrorLog(@"ERROR - failed to get online display list");
        return NO;
    }
    CGDirectDisplayID* displays = (CGDirectDisplayID*)calloc(displayCount, sizeof(CGDirectDisplayID));
    error = CGGetOnlineDisplayList(displayCount, displays, &displayCount);
    if (error != kCGErrorSuccess) {
        CCErrorLog(@"ERROR - failed to get online display list");
        free(displays);
        return NO;
    }

    for (NSUInteger idx = 0; idx < displayCount; idx++) {
        CGDirectDisplayID display = displays[idx];
        if (CGDisplayUnitNumber(display) != unitNumber)
            continue;

        *displayID = display;
        status = YES;
        break;
    }
    free(displays);

    return status;
}
NSScreen* screenForDisplayID(CGDirectDisplayID displayID);
NSScreen* screenForDisplayID(CGDirectDisplayID displayID) {
    __block NSScreen* screen;
    [[NSScreen screens] enumerateObjectsUsingBlock:^(NSScreen* s, NSUInteger idx, BOOL *stop) {
        CGDirectDisplayID someDisplayId = [[[s deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue];
        if (someDisplayId != displayID)
            return;
        screen = s;
        *stop = YES;
    }];
    return screen;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // arg-less switches
        BOOL shouldPrintAttributes = NO, shouldLoadGUI = NO, shouldPrintVersion = NO, shouldPrintDisplays = NO, shouldUseOfflineRenderer = YES;
        for (NSUInteger idx = 1; idx < argc; idx++) {
            NSString* arg = [NSString stringWithUTF8String:argv[idx]];
            if ([arg isEqualToString:@"--print-attributes"])
                shouldPrintAttributes = YES;
            else if ([arg isEqualToString:@"--window-server"])
                shouldLoadGUI = YES;
            else if ([arg isEqualToString:@"--version"])
                shouldPrintVersion = YES;
            else if ([arg isEqualToString:@"--print-displays"])
                shouldPrintDisplays = YES;
            else if ([arg isEqualToString:@"--display"])
                shouldUseOfflineRenderer = NO;
        }

        if (shouldPrintVersion) {
            printVersion(argv);
            return 0;
        }
        if (shouldPrintDisplays) {
            return printDisplays();
        }

        // source composition is required
        if (argc < 2) {
            usage(argv);
            return 1;
        }

        NSString* compositionFilePath = [NSString stringWithUTF8String:argv[1]];
        NSURL* compositionLocation = [[NSURL alloc] initFileURLWithPossiblyRelativePath:compositionFilePath isDirectory:NO];
        // double check
        if (![compositionLocation isFileURL]) {
            CCErrorLog(@"ERROR - filed to create URL for path '%@'", compositionFilePath);
            usage(argv);
            return 1;
        }
        NSError* error;
        if (![compositionLocation checkResourceIsReachableAndReturnError:&error]) {
            CCErrorLog(@"ERROR - bad source composition URL: %@", [error localizedDescription]);
            usage(argv);
            return 1;
        }

        // output size
        NSUserDefaults* args = [NSUserDefaults standardUserDefaults];
        NSString* sizeString = [args stringForKey:@"-canvas-size"];
        NSSize size = sizeString ? NSSizeFromString(sizeString) : NSZeroSize;

        // framerate
        CGFloat framerate = [args floatForKey:@"-max-framerate"];

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
                return 1;
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
                return 1;
            }
            if (![plugInFolderLocation checkResourceIsReachableAndReturnError:&error]) {
                CCErrorLog(@"ERROR - bad extra plug-in directory URL: %@", [error localizedDescription]);
                return 1;
            }

            NSArray* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[plugInFolderLocation path] error:&error];
            if (error) {
                CCErrorLog(@"ERROR - failed to get contents for plug-in directory - %@", [error localizedDescription]);
                return 1;
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

        // display
        CGDirectDisplayID displayID;
        NSOpenGLPixelFormat* format;
        NSOpenGLContext* context;
        if (!shouldUseOfflineRenderer) {
            NSString* displayNumberString = [args stringForKey:@"-display"];
            if (displayNumberString) {
                uint32_t displayUnitNumber = [displayNumberString intValue];
                BOOL status = displayForUnitNumber(displayUnitNumber, &displayID);
                if (!status) {
                    CCErrorLog(@"ERROR - failed to find display with unit number %u", displayUnitNumber);
                    printf("known displays:\n");
                    printDisplays();
                    return 1;
                }
            } else {
                displayID = CGMainDisplayID();
            }

            BOOL useHardwareRenderer = CGDisplayUsesOpenGLAcceleration(displayID);
            if (useHardwareRenderer) {
                NSOpenGLPixelFormatAttribute attributes[] = {
                    // NB - apparently QC and 3rd party plugins use a lot of 1.2 and 2.1 GL bits, so we cannot go 3.2
                    NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersionLegacy,
                        NSOpenGLPFAAccelerated,
                        NSOpenGLPFANoRecovery,
                    NSOpenGLPFADoubleBuffer,
                    NSOpenGLPFADepthSize, 24,
                    NSOpenGLPFAMultisample,
                    NSOpenGLPFASampleBuffers, 1,
                    NSOpenGLPFASamples, 4,
                    0
                };
                format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
                context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
                if (!context) {
                    CCErrorLog(@"ERROR - failed to create hardware rendering context with MSAA!");
                    // TODO - try again without MSAA
                    exit(EXIT_FAILURE);
                }
            } else {
                NSOpenGLPixelFormatAttribute attributes[] = {
                    NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersionLegacy,
                        NSOpenGLPFARendererID, kCGLRendererGenericFloatID,
                    NSOpenGLPFADoubleBuffer,
                    NSOpenGLPFADepthSize, 24,
                    0
                };
                format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];                
                context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
                if (!context) {
                    CCErrorLog(@"ERROR - failed to create software rendering context!");
                    exit(EXIT_FAILURE);
                }
            }

            GLint interval = 1;
            [context setValues:&interval forParameter:NSOpenGLCPSwapInterval];
        } else {
            // TODO - manually setup offline renderer format and context
        }


        __block RenderSlave* renderSlave;
        void (^renderSlaveSetup)(void) = ^(void) {
            renderSlave = [[RenderSlave alloc] initWithContext:context pixelFormat:format composition:compositionLocation maximumFramerate:framerate canvasSize:size inputPairs:inputs];
            if (shouldPrintAttributes) {
                [renderSlave printCompositionAttributes];
                exit(EXIT_SUCCESS);
            }
            [renderSlave startRendering];
        };
        void (^teardown)(void) = ^(void) {
            [window orderOut:nil];

            // revert display sleep override
            if (assertionID != kIOPMNullAssertionID) {
                IOReturn success = IOPMAssertionRelease(assertionID);
                if (success != kIOReturnSuccess) {
                    CCErrorLog(@"ERROR - failed to release dislay sleep override");
                }
            }

            [renderSlave teardown];
            renderSlave = nil;
        };


        // signal handlers
        void (^shutdown)(void) = ^(void) {
            teardown();
            exit(EXIT_SUCCESS);
        };
        dispatch_source_t interruptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_global_queue(0, 0));
        dispatch_source_set_event_handler(interruptSource, shutdown);
        dispatch_resume(interruptSource);
        sigignore(SIGINT);
        dispatch_source_t terminateSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_global_queue(0, 0));
        dispatch_source_set_event_handler(terminateSource, shutdown);
        dispatch_resume(terminateSource);
        sigignore(SIGTERM);


        // locked and loaded
        if (!shouldLoadGUI && shouldUseOfflineRenderer) {
#if 0
            // setup slave at the end of the runloop
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0 * NSEC_PER_SEC);
            dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                renderSlaveSetup();
            });
            [[NSRunLoop currentRunLoop] run];
#else
            // WORKAROUND - Syphon requires an application, it is otherwise unhappy
            //  http://code.google.com/p/syphon-framework/issues/detail?id=18
            [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification object:[NSApplication sharedApplication] queue:nil usingBlock:^(NSNotification*notification) {
                renderSlaveSetup();
            }];

            [NSApp run];
#endif
        } else {
            // setup as minimal cocoa app, greets to http://cocoawithlove.com/2010/09/minimalist-cocoa-programming.html
            [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyRegular];

            [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification object:NSApp queue:nil usingBlock:^(NSNotification*notification) {
                renderSlaveSetup();
            }];
            [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification object:NSApp queue:nil usingBlock:^(NSNotification*notification) {
                teardown();
            }];

            // setup a minimal application menu
            NSMenu* menu = [[NSMenu alloc] init];
            NSMenuItem* applicationMenuItem = [[NSMenuItem alloc] init];
            [menu addItem:applicationMenuItem];
            [NSApp setMainMenu:menu];
            NSMenu* applicationMenu = [[NSMenu alloc] init];
            NSString* applicationName = [[NSRunningApplication currentApplication] localizedName];
            NSMenuItem* quitMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Quit %@", applicationName] action:@selector(terminate:) keyEquivalent:@"q"];
            [applicationMenu addItem:quitMenuItem];
            [applicationMenuItem setSubmenu:applicationMenu];

            // setup window for output
            if (!shouldUseOfflineRenderer) {
                // override display sleep while presenting - wish it were per display
                IOReturn success = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep, kIOPMAssertionLevelOn, CFSTR("ballmachine QC presentation"), &assertionID);
                if (success != kIOReturnSuccess) {
                    CCErrorLog(@"ERROR - failed to disable display sleep");
                    exit(EXIT_FAILURE);
                }

                NSScreen* screen = screenForDisplayID(displayID);
                if (!screen) {
                    CCErrorLog(@"ERROR - failed to fetch screen for displayID");
                    exit(EXIT_FAILURE);
                }

                // the lion way to fullscreen gl http://developer.apple.com/library/mac/#documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_fullscreen/opengl_cgl.html
                NSRect displayRect = [screen frame];
                window = [[NSWindow alloc] initWithContentRect:displayRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
                [window setLevel:CGShieldingWindowLevel()];
                [window setOpaque:YES];

                NSRect viewRect = NSMakeRect(0.0, 0.0, displayRect.size.width, displayRect.size.height);
                NSOpenGLView* view = [[NSOpenGLView alloc] initWithFrame:viewRect pixelFormat:format];
                [window setContentView:view];

                // associate once view is bound to a window
                [view setOpenGLContext:context];
                [context setView:view];

                [window makeKeyAndOrderFront:nil];
                [NSApp activateIgnoringOtherApps:YES];

                // hide the cursor when presenting
                [NSCursor hide];
            }

            [NSApp run];
        }
    }
    return 0;
}
