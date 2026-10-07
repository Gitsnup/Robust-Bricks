/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// Robust Bricks: a small homebrew game for iPhone OS 2.x. See README.md for how
// to build it.

#include "BricksView.h"
#include "Sound.h"
#include "System.h"

@interface RobustBricksAppDelegate : NSObject {
  UIWindow *window;
  BricksView *view;
}
@end

@implementation RobustBricksAppDelegate

- (void)applicationDidFinishLaunching:(UIApplication *)application {
  [application setStatusBarHidden:YES];
  SoundInit();

  CGRect frame = [[UIScreen mainScreen] bounds];
  window = [[UIWindow alloc] initWithFrame:frame];
  view = [[BricksView alloc] initWithFrame:[window bounds]];
  [window addSubview:view];
  [window makeKeyAndVisible];

  [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                   target:self
                                 selector:@selector(onTick:)
                                 userInfo:nil
                                  repeats:YES];
}

- (void)onTick:(NSTimer *)timer {
  [view tick];
}

- (void)dealloc {
  [view release];
  [window release];
  [super dealloc];
}
@end

int main(int argc, char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int result = UIApplicationMain(
      argc, argv, nil, NSStringFromClass([RobustBricksAppDelegate class]));
  [pool drain];
  return result;
}
