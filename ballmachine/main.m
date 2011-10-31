//
//  main.m
//  ballmachine
//
//  Created by Jean-Pierre Mouilleseaux on 28 Oct 2011.
//  Copyright (c) 2011 Chorded Constructions. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Quartz/Quartz.h>

@interface RenderSlave : NSObject <NSApplicationDelegate> {}
- (void)loadCompositionAtURL:(NSURL*)location;
@end

@implementation RenderSlave
- (void)loadCompositionAtURL:(NSURL*)location {
    NSLog(@"setup");
}
@end

#pragma mark -

int main (int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            NSLog(@"usage: %@ <source-composition> <additional-plugin-directory>", [[NSString stringWithUTF8String:argv[0]] lastPathComponent]);
            return -1;
        }

        NSString* filePath = [[NSString stringWithUTF8String:argv[1]] stringByExpandingTildeInPath];
        NSURL* url = [NSURL URLWithString:filePath];
        if (![url isFileURL]) {
            NSString* path = [filePath stringByStandardizingPath];
            if ([path isAbsolutePath]) {
                url = [NSURL fileURLWithPath:path isDirectory:NO];
            } else {
//                NSURL* baseDirectoryURL = [[context compositionURL] URLByDeletingLastPathComponent];
//                url = [baseDirectoryURL URLByAppendingPathComponent:path];
            }
        }
        // double check
        if (![url isFileURL]) {
            NSLog(@"ERROR - filed to create URL for path '%@'", filePath);
            return -1;
        }

        NSError* error;
        if (![url checkResourceIsReachableAndReturnError:&error]) {
            NSLog(@"ERROR - bad source composition URL: %@", [error localizedDescription]);
            return -1;
        }

        RenderSlave* renderSlave = [[RenderSlave alloc] init];
        [renderSlave loadCompositionAtURL:url];

        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
