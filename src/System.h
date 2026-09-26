/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// The few system declarations Dared Bricks needs. They are written out here,
// rather than taken from SDK headers, so that the game builds with nothing but
// a compiler, a linker and stub libraries for the frameworks it links against.

#ifndef SYSTEM_H
#define SYSTEM_H

// Objective-C runtime and basic types

typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#define nil ((id)0)

typedef unsigned int NSUInteger;
typedef int NSInteger;
typedef double NSTimeInterval;

// Core Graphics

typedef float CGFloat;

typedef struct {
  CGFloat x;
  CGFloat y;
} CGPoint;

typedef struct {
  CGFloat width;
  CGFloat height;
} CGSize;

typedef struct {
  CGPoint origin;
  CGSize size;
} CGRect;

static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat width,
                                CGFloat height) {
  CGRect rect;
  rect.origin.x = x;
  rect.origin.y = y;
  rect.size.width = width;
  rect.size.height = height;
  return rect;
}

typedef struct CGContext *CGContextRef;

void CGContextSetRGBFillColor(CGContextRef context, CGFloat red, CGFloat green,
                              CGFloat blue, CGFloat alpha);
void CGContextFillRect(CGContextRef context, CGRect rect);

// C library

long time(long *out);
unsigned long long mach_absolute_time(void);

// Foundation

@interface NSObject {
  Class isa;
}
+ (Class)class;
+ (instancetype)alloc;
- (instancetype)init;
- (instancetype)retain;
- (void)release;
- (instancetype)autorelease;
- (void)dealloc;
@end

@interface NSAutoreleasePool : NSObject
- (void)drain;
@end

@interface NSString : NSObject
+ (NSString *)stringWithUTF8String:(const char *)string;
@end

@interface NSData : NSObject
+ (NSData *)dataWithContentsOfFile:(NSString *)path;
- (const void *)bytes;
- (NSUInteger)length;
@end

@interface NSBundle : NSObject
+ (NSBundle *)mainBundle;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)extension;
@end

@interface NSUserDefaults : NSObject
+ (NSUserDefaults *)standardUserDefaults;
- (NSInteger)integerForKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;
- (BOOL)synchronize;
@end

@interface NSSet : NSObject
- (id)anyObject;
@end

@interface NSTimer : NSObject
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval
                                     target:(id)target
                                   selector:(SEL)selector
                                   userInfo:(id)userInfo
                                    repeats:(BOOL)repeats;
@end

NSString *NSStringFromClass(Class aClass);

// UIKit

@class UIView;

@interface UIFont : NSObject
+ (UIFont *)boldSystemFontOfSize:(CGFloat)size;
@end

// UIStringDrawing
typedef enum { UILineBreakModeWordWrap = 0 } UILineBreakMode;
typedef enum {
  UITextAlignmentLeft = 0,
  UITextAlignmentCenter = 1,
  UITextAlignmentRight = 2
} UITextAlignment;

@interface NSString (UIStringDrawing)
- (CGSize)drawInRect:(CGRect)rect
            withFont:(UIFont *)font
       lineBreakMode:(UILineBreakMode)lineBreakMode
           alignment:(UITextAlignment)alignment;
@end

@interface UIResponder : NSObject
@end

@interface UIEvent : NSObject
@end

@interface UITouch : NSObject
- (CGPoint)locationInView:(UIView *)view;
@end

@interface UIView : UIResponder
- (instancetype)initWithFrame:(CGRect)frame;
- (CGRect)bounds;
- (void)addSubview:(UIView *)view;
- (void)setNeedsDisplay;
@end

@interface UIWindow : UIView
- (void)makeKeyAndVisible;
@end

@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
- (CGRect)bounds;
@end

@interface UIApplication : UIResponder
+ (UIApplication *)sharedApplication;
- (void)setStatusBarHidden:(BOOL)hidden;
@end

CGContextRef UIGraphicsGetCurrentContext(void);
int UIApplicationMain(int argc, char *argv[], NSString *principalClassName,
                      NSString *delegateClassName);

// OpenAL

typedef struct ALCdevice_struct ALCdevice;
typedef struct ALCcontext_struct ALCcontext;
typedef char ALCboolean;
typedef char ALCchar;
typedef int ALCint;
typedef unsigned int ALuint;
typedef int ALint;
typedef int ALsizei;
typedef int ALenum;

#define AL_NO_ERROR 0
#define AL_BUFFER 0x1009
#define AL_FORMAT_MONO16 0x1101

ALCdevice *alcOpenDevice(const ALCchar *deviceName);
ALCcontext *alcCreateContext(ALCdevice *device, const ALCint *attributes);
ALCboolean alcMakeContextCurrent(ALCcontext *context);
void alGenBuffers(ALsizei count, ALuint *buffers);
void alBufferData(ALuint buffer, ALenum format, const void *data, ALsizei size,
                  ALsizei frequency);
void alGenSources(ALsizei count, ALuint *sources);
void alSourcei(ALuint source, ALenum parameter, ALint value);
void alSourcePlay(ALuint source);
ALenum alGetError(void);

#endif
