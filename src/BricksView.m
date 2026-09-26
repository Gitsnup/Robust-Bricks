/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// A single level of brick breaking with a random brick layout. Drag anywhere to
// move the paddle, tap to serve. There are three balls per game. Clearing every
// brick shows YOU WIN, losing the last ball shows GAME OVER, and tapping after
// either starts a new game with a new layout.

#include "BricksView.h"
#include "Sound.h"
#include "System.h"

#define BRICK_WIDTH 36.0f
#define BRICK_HEIGHT 14.0f
#define BRICK_GAP 4.0f
#define BRICKS_TOP 70.0f

#define PADDLE_WIDTH 64.0f
#define PADDLE_HEIGHT 10.0f
#define PADDLE_FROM_BOTTOM 50.0f

#define BALL_SIZE 8.0f
#define BALL_SPEED 4.0f // Along each axis, in points per tick.

// One color per row, top to bottom.
static const CGFloat rowColors[BRICK_ROWS][3] = {
    {0.90f, 0.20f, 0.20f}, {0.95f, 0.55f, 0.15f}, {0.95f, 0.85f, 0.20f},
    {0.30f, 0.80f, 0.30f}, {0.20f, 0.70f, 0.90f}, {0.45f, 0.35f, 0.90f},
};

// A small xorshift generator. The system's rand() and arc4random() start from
// the same seed every launch in touchHLE, so this is seeded from the clock.
static unsigned int randomState;

static unsigned int nextRandom(void) {
  if (randomState == 0) {
    randomState = (unsigned int)time(0) ^ (unsigned int)mach_absolute_time();
    if (randomState == 0) {
      randomState = 1;
    }
  }
  randomState ^= randomState << 13;
  randomState ^= randomState >> 17;
  randomState ^= randomState << 5;
  return randomState;
}

static CGFloat absf(CGFloat v) { return v < 0 ? -v : v; }

static BOOL overlaps(CGFloat ax, CGFloat ay, CGFloat aw, CGFloat ah, CGFloat bx,
                     CGFloat by, CGFloat bw, CGFloat bh) {
  return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah;
}

@implementation BricksView

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    [self resetGame];
  }
  return self;
}

- (CGFloat)width {
  return [self bounds].size.width;
}

- (CGFloat)height {
  return [self bounds].size.height;
}

- (CGFloat)bricksLeftEdge {
  CGFloat rowWidth =
      BRICK_COLUMNS * BRICK_WIDTH + (BRICK_COLUMNS - 1) * BRICK_GAP;
  return ([self width] - rowWidth) / 2;
}

- (CGFloat)paddleY {
  return [self height] - PADDLE_FROM_BOTTOM;
}

// A random layout, mirrored left to right so it looks deliberate. Each brick
// is present with a 70% chance, and a layout needs at least 16 bricks.
- (void)randomizeBricks {
  do {
    bricksLeft = 0;
    for (int row = 0; row < BRICK_ROWS; row++) {
      for (int column = 0; column < BRICK_COLUMNS / 2; column++) {
        // 717/1024 is about 70%. (No %: armv6/armv7 have no divide.)
        BOOL present = (nextRandom() & 1023) < 717;
        bricks[row][column] = present;
        bricks[row][BRICK_COLUMNS - 1 - column] = present;
        bricksLeft += present ? 2 : 0;
      }
    }
  } while (bricksLeft < 16);
}

- (void)resetGame {
  [self randomizeBricks];
  ballsLeft = BALLS_PER_GAME;
  paddleX = [self width] / 2;
  state = StateServing;
  [self placeBallOnPaddle];
}

- (void)placeBallOnPaddle {
  ballX = paddleX - BALL_SIZE / 2;
  ballY = [self paddleY] - BALL_SIZE;
  ballDX = 0;
  ballDY = 0;
}

- (void)movePaddleTo:(CGFloat)x {
  CGFloat half = PADDLE_WIDTH / 2;
  if (x < half) {
    x = half;
  } else if (x > [self width] - half) {
    x = [self width] - half;
  }
  paddleX = x;
}

// Called 60 times a second by the app delegate's timer.
- (void)tick {
  if (state == StateServing) {
    [self placeBallOnPaddle];
  } else if (state == StatePlaying) {
    [self moveBall];
  }
  [self setNeedsDisplay];
}

- (void)moveBall {
  ballX += ballDX;
  ballY += ballDY;

  // Walls and ceiling.
  if (ballX < 0) {
    ballX = 0;
    ballDX = absf(ballDX);
  } else if (ballX + BALL_SIZE > [self width]) {
    ballX = [self width] - BALL_SIZE;
    ballDX = -absf(ballDX);
  }
  if (ballY < 0) {
    ballY = 0;
    ballDY = absf(ballDY);
  }

  // Missed: that ball is gone. Serve the next one, if there is one.
  if (ballY > [self height]) {
    ballsLeft--;
    state = ballsLeft > 0 ? StateServing : StateLost;
    return;
  }

  // Paddle. Where the ball lands on it decides the bounce angle.
  CGFloat paddleLeft = paddleX - PADDLE_WIDTH / 2;
  if (ballDY > 0 && overlaps(ballX, ballY, BALL_SIZE, BALL_SIZE, paddleLeft,
                             [self paddleY], PADDLE_WIDTH, PADDLE_HEIGHT)) {
    ballY = [self paddleY] - BALL_SIZE;
    ballDY = -absf(ballDY);
    SoundPlay(SoundBounce);
    CGFloat offset = (ballX + BALL_SIZE / 2 - paddleX) / (PADDLE_WIDTH / 2);
    ballDX = offset * BALL_SPEED;
    // Never bounce straight up, or the ball could get stuck.
    if (absf(ballDX) < 0.75f) {
      ballDX = ballDX < 0 ? -0.75f : 0.75f;
    }
    return;
  }

  // Bricks: break at most one per tick.
  CGFloat left = [self bricksLeftEdge];
  for (int row = 0; row < BRICK_ROWS; row++) {
    for (int column = 0; column < BRICK_COLUMNS; column++) {
      if (!bricks[row][column]) {
        continue;
      }
      CGFloat x = left + column * (BRICK_WIDTH + BRICK_GAP);
      CGFloat y = BRICKS_TOP + row * (BRICK_HEIGHT + BRICK_GAP);
      if (!overlaps(ballX, ballY, BALL_SIZE, BALL_SIZE, x, y, BRICK_WIDTH,
                    BRICK_HEIGHT)) {
        continue;
      }
      bricks[row][column] = NO;
      bricksLeft--;
      SoundPlay(SoundExplode);

      // Bounce off whichever side the ball went in least far.
      CGFloat overlapX =
          ballDX > 0 ? ballX + BALL_SIZE - x : x + BRICK_WIDTH - ballX;
      CGFloat overlapY =
          ballDY > 0 ? ballY + BALL_SIZE - y : y + BRICK_HEIGHT - ballY;
      if (overlapX < overlapY) {
        ballDX = -ballDX;
      } else {
        ballDY = -ballDY;
      }

      if (bricksLeft == 0) {
        state = StateWon;
      }
      return;
    }
  }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
  UITouch *touch = [touches anyObject];
  [self movePaddleTo:[touch locationInView:self].x];

  if (state == StateServing) {
    ballDX = BALL_SPEED * 0.6f;
    ballDY = -BALL_SPEED;
    state = StatePlaying;
  } else if (state == StateWon || state == StateLost) {
    [self resetGame];
  }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
  UITouch *touch = [touches anyObject];
  [self movePaddleTo:[touch locationInView:self].x];
}

- (void)drawText:(const char *)text
          inRect:(CGRect)rect
        fontSize:(CGFloat)size
       alignment:(UITextAlignment)alignment
         context:(CGContextRef)context {
  CGContextSetRGBFillColor(context, 1, 1, 1, 1);
  [[NSString stringWithUTF8String:text]
         drawInRect:rect
           withFont:[UIFont boldSystemFontOfSize:size]
      lineBreakMode:UILineBreakModeWordWrap
          alignment:alignment];
}

- (void)drawText:(const char *)text
          inRect:(CGRect)rect
        fontSize:(CGFloat)size
         context:(CGContextRef)context {
  [self drawText:text
          inRect:rect
        fontSize:size
       alignment:UITextAlignmentCenter
         context:context];
}

- (void)drawRect:(CGRect)rect {
  CGContextRef context = UIGraphicsGetCurrentContext();
  CGFloat width = [self width];
  CGFloat height = [self height];

  CGContextSetRGBFillColor(context, 0, 0, 0, 1);
  CGContextFillRect(context, [self bounds]);

  CGFloat left = [self bricksLeftEdge];
  for (int row = 0; row < BRICK_ROWS; row++) {
    CGContextSetRGBFillColor(context, rowColors[row][0], rowColors[row][1],
                             rowColors[row][2], 1);
    for (int column = 0; column < BRICK_COLUMNS; column++) {
      if (bricks[row][column]) {
        CGContextFillRect(
            context, CGRectMake(left + column * (BRICK_WIDTH + BRICK_GAP),
                                BRICKS_TOP + row * (BRICK_HEIGHT + BRICK_GAP),
                                BRICK_WIDTH, BRICK_HEIGHT));
      }
    }
  }

  // Balls left, in the upper right. BALLS_PER_GAME is a single digit.
  char ballsText[] = "Balls: 0";
  ballsText[sizeof(ballsText) - 2] = (char)('0' + ballsLeft);
  [self drawText:ballsText
          inRect:CGRectMake(width - 110, 20, 100, 24)
        fontSize:16
       alignment:UITextAlignmentRight
         context:context];

  if (state == StateWon || state == StateLost) {
    [self drawText:(state == StateWon ? "YOU WIN" : "GAME OVER")
            inRect:CGRectMake(0, height / 2 - 40, width, 50)
          fontSize:40
           context:context];
    [self drawText:"Tap to play again"
            inRect:CGRectMake(0, height / 2 + 20, width, 30)
          fontSize:18
           context:context];
    return;
  }

  CGContextSetRGBFillColor(context, 0.9f, 0.9f, 0.9f, 1);
  CGContextFillRect(context,
                    CGRectMake(paddleX - PADDLE_WIDTH / 2, [self paddleY],
                               PADDLE_WIDTH, PADDLE_HEIGHT));
  CGContextSetRGBFillColor(context, 1, 1, 1, 1);
  CGContextFillRect(context, CGRectMake(ballX, ballY, BALL_SIZE, BALL_SIZE));

  if (state == StateServing) {
    [self drawText:"Tap to serve"
            inRect:CGRectMake(0, height / 2 + 20, width, 30)
          fontSize:18
           context:context];
  }
}

@end
