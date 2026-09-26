/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// A single level of brick breaking with a random brick layout. A title screen
// shows the fastest winning time and the number of games played, and has
// buttons for the ball speed (Normal, Fast or Ludicrous) and for sound on or
// off. All of these are saved between launches, with a separate fastest time
// for each speed. Drag anywhere to move the paddle, tap to serve. There are three balls per game,
// and a timer runs from the first serve until the game ends. Clearing every
// brick shows YOU WIN, losing the last ball shows GAME OVER, and tapping after
// either starts a new game with a new layout.
//
// Broken bricks sometimes drop a power-up capsule, which takes effect if the
// paddle catches it: B (one more ball), P (a longer paddle), S (slower balls)
// or M (multi-ball). A life is only lost when the last ball in play falls, and
// losing one ends any P or S effect and clears falling capsules.

#include "BricksView.h"
#include "Sound.h"
#include "System.h"

#define BRICK_WIDTH 36.0f
#define BRICK_HEIGHT 14.0f
#define BRICK_GAP 4.0f
#define BRICKS_TOP 70.0f

#define PADDLE_WIDTH 64.0f
#define LONG_PADDLE_WIDTH 96.0f
#define PADDLE_HEIGHT 10.0f
#define PADDLE_FROM_BOTTOM 50.0f

#define BALL_SIZE 8.0f
#define BALL_SPEED 4.0f // Along each axis, in points per tick.

#define CAPSULE_WIDTH 26.0f
#define CAPSULE_HEIGHT 14.0f
#define CAPSULE_SPEED 2.0f // Points per tick.
// Out of 1024: 171 is about 1 in 6. (No %: armv6/armv7 have no divide.)
#ifndef CAPSULE_CHANCE
#define CAPSULE_CHANCE 171
#endif

// For testing: 1 makes the paddle as wide as the screen, so no ball is lost.
#ifndef FULL_PADDLE
#define FULL_PADDLE 0
#endif

#define POWER_UP_TICKS (15 * 60) // How long P and S last.

// A broken brick splits into PIECE_COLUMNS x PIECE_ROWS pieces, which fly off
// under gravity and fade out over PIECE_TICKS.
#define PIECE_COLUMNS 4
#define PIECE_ROWS 2
#define PIECE_TICKS 30
#define PIECE_GRAVITY 0.25f // Points per tick, per tick.

// The NSUserDefaults key for the speed setting.
#define SPEED_KEY "Speed"
// The NSUserDefaults key for the number of games started.
#define GAMES_PLAYED_KEY "GamesPlayed"
// The NSUserDefaults key for turning sound off. Sound is on by default, when
// the key is missing.
#define SOUND_OFF_KEY "SoundOff"

// One color per row, top to bottom.
static const CGFloat rowColors[BRICK_ROWS][3] = {
    {0.90f, 0.20f, 0.20f}, {0.95f, 0.55f, 0.15f}, {0.95f, 0.85f, 0.20f},
    {0.30f, 0.80f, 0.30f}, {0.20f, 0.70f, 0.90f}, {0.45f, 0.35f, 0.90f},
};

// Speed names, ball speed multipliers and the NSUserDefaults keys for the
// fastest winning time (in ticks), in the order of the Speed enum. Normal
// keeps the key from before there was a speed setting.
static const char *const speedNames[SpeedCount] = {"Normal", "Fast",
                                                   "Ludicrous"};
static const CGFloat speedMultipliers[SpeedCount] = {1.0f, 1.5f, 2.5f};
static const char *const fastestTicksKeys[SpeedCount] = {
    "FastestTicks", "FastestTicksFast", "FastestTicksLudicrous"};

// Capsule letters and colors, in the order of the PowerUp enum.
static const char *const powerUpLetters[PowerUpCount] = {"B", "P", "S", "M"};
static const CGFloat powerUpColors[PowerUpCount][3] = {
    {0.85f, 0.25f, 0.25f},
    {0.25f, 0.50f, 0.95f},
    {0.20f, 0.70f, 0.35f},
    {0.95f, 0.55f, 0.10f},
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

// A random value from -amount to +amount.
static CGFloat jitter(CGFloat amount) {
  return ((CGFloat)(nextRandom() & 255) / 255.0f - 0.5f) * 2 * amount;
}

static BOOL overlaps(CGFloat ax, CGFloat ay, CGFloat aw, CGFloat ah, CGFloat bx,
                     CGFloat by, CGFloat bw, CGFloat bh) {
  return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah;
}

// Appends a non-negative number to a string, returning the new length.
static int appendNumber(char *text, int length, int number) {
  char digits[10];
  int count = 0;
  do {
    digits[count++] = (char)('0' + number % 10);
    number /= 10;
  } while (number > 0 && count < 10);
  while (count > 0) {
    text[length++] = digits[--count];
  }
  return length;
}

// Appends a string to a string, returning the new length.
static int appendString(char *text, int length, const char *string) {
  while (*string) {
    text[length++] = *string++;
  }
  text[length] = 0;
  return length;
}

// Appends a time in ticks as minutes:seconds, or minutes:seconds.tenths.
static int appendTime(char *text, int length, int ticks, BOOL tenths) {
  int seconds = ticks / 60;
  length = appendNumber(text, length, seconds / 60);
  text[length++] = ':';
  text[length++] = (char)('0' + (seconds % 60) / 10);
  text[length++] = (char)('0' + seconds % 10);
  if (tenths) {
    text[length++] = '.';
    text[length++] = (char)('0' + (ticks % 60) / 6);
  }
  text[length] = 0;
  return length;
}

static NSInteger loadInteger(const char *key) {
  return [[NSUserDefaults standardUserDefaults]
      integerForKey:[NSString stringWithUTF8String:key]];
}

static void saveInteger(const char *key, NSInteger value) {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setInteger:value forKey:[NSString stringWithUTF8String:key]];
  [defaults synchronize];
}

@implementation BricksView

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    for (int i = 0; i < SpeedCount; i++) {
      fastestTicks[i] = (int)loadInteger(fastestTicksKeys[i]);
    }
    NSInteger savedSpeed = loadInteger(SPEED_KEY);
    speed = savedSpeed >= 0 && savedSpeed < SpeedCount ? (Speed)savedSpeed
                                                       : SpeedNormal;
    gamesPlayed = (int)loadInteger(GAMES_PLAYED_KEY);
    SoundSetEnabled(!loadInteger(SOUND_OFF_KEY));
    [self resetGame];
    state = StateTitle;
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

- (CGFloat)paddleWidth {
#if FULL_PADDLE
  return [self width];
#else
  return longPaddleTicks > 0 ? LONG_PADDLE_WIDTH : PADDLE_WIDTH;
#endif
}

// A random layout, mirrored left to right so it looks deliberate. Each brick
// is present with a 70% chance, and a layout needs at least 16 bricks.
- (void)randomizeBricks {
  do {
    bricksLeft = 0;
    for (int row = 0; row < BRICK_ROWS; row++) {
      for (int column = 0; column < BRICK_COLUMNS / 2; column++) {
        // 717/1024 is about 70%.
        BOOL present = (nextRandom() & 1023) < 717;
        bricks[row][column] = present;
        bricks[row][BRICK_COLUMNS - 1 - column] = present;
        bricksLeft += present ? 2 : 0;
      }
    }
  } while (bricksLeft < 16);
}

// Ends the P and S effects and removes falling capsules and extra balls.
- (void)clearPowerUps {
  longPaddleTicks = 0;
  slowTicks = 0;
  for (int i = 0; i < MAX_CAPSULES; i++) {
    capsules[i].active = NO;
  }
  for (int i = 0; i < MAX_BALLS_IN_PLAY; i++) {
    balls[i].active = NO;
  }
}

- (void)resetGame {
  [self randomizeBricks];
  [self clearPowerUps];
  for (int i = 0; i < MAX_PIECES; i++) {
    pieces[i].active = NO;
  }
  ballsLeft = BALLS_PER_GAME;
  timerTicks = 0;
  timerRunning = NO;
  newRecord = NO;
  paddleX = [self width] / 2;
  state = StateServing;
  [self placeBallOnPaddle];
}

- (void)placeBallOnPaddle {
  balls[0].active = YES;
  balls[0].x = paddleX - BALL_SIZE / 2;
  balls[0].y = [self paddleY] - BALL_SIZE;
  balls[0].dx = 0;
  balls[0].dy = 0;
}

- (void)movePaddleTo:(CGFloat)x {
  CGFloat half = [self paddleWidth] / 2;
  if (x < half) {
    x = half;
  } else if (x > [self width] - half) {
    x = [self width] - half;
  }
  paddleX = x;
}

// Called 60 times a second by the app delegate's timer.
- (void)tick {
  if (timerRunning) {
    timerTicks++;
  }
  if (state == StateServing) {
    [self placeBallOnPaddle];
  } else if (state == StatePlaying) {
    [self play];
  }
  // Pieces keep flying on the serve, win and game over screens too.
  [self movePieces];
  [self setNeedsDisplay];
}

- (void)play {
  if (longPaddleTicks > 0 && --longPaddleTicks == 0) {
    // Back to the normal width: keep the paddle on screen.
    [self movePaddleTo:paddleX];
  }
  if (slowTicks > 0) {
    slowTicks--;
  }
  CGFloat factor = speedMultipliers[speed] * (slowTicks > 0 ? 0.5f : 1.0f);
  // At the faster speeds each ball moves in smaller steps, so it can't pass
  // through the paddle or a corner of a brick between one step and the next.
  int steps = factor > 2 ? 3 : factor > 1 ? 2 : 1;
  CGFloat stepFactor = factor / steps;

  BOOL anyBall = NO;
  for (int i = 0; i < MAX_BALLS_IN_PLAY && state == StatePlaying; i++) {
    for (int step = 0;
         step < steps && balls[i].active && state == StatePlaying; step++) {
      [self moveBall:&balls[i] speed:stepFactor];
    }
    anyBall = anyBall || balls[i].active;
  }
  if (state != StatePlaying) {
    return;
  }
  [self moveCapsules];

  // The last ball in play is gone: that's a life lost.
  if (!anyBall) {
    ballsLeft--;
    [self clearPowerUps];
    [self movePaddleTo:paddleX];
    state = ballsLeft > 0 ? StateServing : StateLost;
    timerRunning = state != StateLost;
  }
}

- (void)moveBall:(Ball *)ball speed:(CGFloat)factor {
  ball->x += ball->dx * factor;
  ball->y += ball->dy * factor;

  // Walls and ceiling.
  if (ball->x < 0) {
    ball->x = 0;
    ball->dx = absf(ball->dx);
  } else if (ball->x + BALL_SIZE > [self width]) {
    ball->x = [self width] - BALL_SIZE;
    ball->dx = -absf(ball->dx);
  }
  if (ball->y < 0) {
    ball->y = 0;
    ball->dy = absf(ball->dy);
  }

  // Missed: this ball is gone.
  if (ball->y > [self height]) {
    ball->active = NO;
    return;
  }

  // Paddle. Where the ball lands on it decides the bounce angle.
  CGFloat paddleWidth = [self paddleWidth];
  CGFloat paddleLeft = paddleX - paddleWidth / 2;
  if (ball->dy > 0 &&
      overlaps(ball->x, ball->y, BALL_SIZE, BALL_SIZE, paddleLeft,
               [self paddleY], paddleWidth, PADDLE_HEIGHT)) {
    ball->y = [self paddleY] - BALL_SIZE;
    ball->dy = -absf(ball->dy);
    SoundPlay(SoundBounce);
    CGFloat offset = (ball->x + BALL_SIZE / 2 - paddleX) / (paddleWidth / 2);
    ball->dx = offset * BALL_SPEED;
    // Never bounce straight up, or the ball could get stuck.
    if (absf(ball->dx) < 0.75f) {
      ball->dx = ball->dx < 0 ? -0.75f : 0.75f;
    }
    return;
  }

  // Bricks: each ball breaks at most one per step.
  CGFloat left = [self bricksLeftEdge];
  for (int row = 0; row < BRICK_ROWS; row++) {
    for (int column = 0; column < BRICK_COLUMNS; column++) {
      if (!bricks[row][column]) {
        continue;
      }
      CGFloat x = left + column * (BRICK_WIDTH + BRICK_GAP);
      CGFloat y = BRICKS_TOP + row * (BRICK_HEIGHT + BRICK_GAP);
      if (!overlaps(ball->x, ball->y, BALL_SIZE, BALL_SIZE, x, y, BRICK_WIDTH,
                    BRICK_HEIGHT)) {
        continue;
      }
      bricks[row][column] = NO;
      bricksLeft--;
      SoundPlay(SoundExplode);
      [self shatterBrickAtX:x y:y row:row ball:ball];

      // Bounce off whichever side the ball went in least far.
      CGFloat overlapX =
          ball->dx > 0 ? ball->x + BALL_SIZE - x : x + BRICK_WIDTH - ball->x;
      CGFloat overlapY =
          ball->dy > 0 ? ball->y + BALL_SIZE - y : y + BRICK_HEIGHT - ball->y;
      if (overlapX < overlapY) {
        ball->dx = -ball->dx;
      } else {
        ball->dy = -ball->dy;
      }

      if (bricksLeft == 0) {
        state = StateWon;
        timerRunning = NO;
        [self clearPowerUps];
        [self recordWin];
      } else {
        [self maybeDropCapsuleAtX:x + BRICK_WIDTH / 2 y:y];
      }
      return;
    }
  }
}

// Saves the time if it's the fastest win so far at this speed.
- (void)recordWin {
  newRecord = fastestTicks[speed] == 0 || timerTicks < fastestTicks[speed];
  if (newRecord) {
    fastestTicks[speed] = timerTicks;
    saveInteger(fastestTicksKeys[speed], timerTicks);
  }
}

// Breaks a brick into pieces that fly away from its center, pushed a little
// in the direction the ball was going.
- (void)shatterBrickAtX:(CGFloat)x y:(CGFloat)y row:(int)row ball:(Ball *)ball {
  CGFloat pieceWidth = BRICK_WIDTH / PIECE_COLUMNS;
  CGFloat pieceHeight = BRICK_HEIGHT / PIECE_ROWS;
  int slot = 0;
  for (int pieceRow = 0; pieceRow < PIECE_ROWS; pieceRow++) {
    for (int pieceColumn = 0; pieceColumn < PIECE_COLUMNS; pieceColumn++) {
      while (slot < MAX_PIECES && pieces[slot].active) {
        slot++;
      }
      if (slot == MAX_PIECES) {
        return;
      }
      Piece *piece = &pieces[slot];
      piece->active = YES;
      piece->x = x + pieceColumn * pieceWidth;
      piece->y = y + pieceRow * pieceHeight;
      CGFloat fromCenter = piece->x + pieceWidth / 2 - (x + BRICK_WIDTH / 2);
      piece->dx = fromCenter * 0.12f + ball->dx * 0.3f + jitter(0.4f);
      piece->dy = -1.5f - (PIECE_ROWS - 1 - pieceRow) * 0.5f + ball->dy * 0.2f +
                  jitter(0.4f);
      piece->ticksLeft = PIECE_TICKS;
      piece->row = row;
    }
  }
}

- (void)movePieces {
  for (int i = 0; i < MAX_PIECES; i++) {
    Piece *piece = &pieces[i];
    if (!piece->active) {
      continue;
    }
    piece->x += piece->dx;
    piece->y += piece->dy;
    piece->dy += PIECE_GRAVITY;
    if (--piece->ticksLeft == 0) {
      piece->active = NO;
    }
  }
}

- (void)maybeDropCapsuleAtX:(CGFloat)centerX y:(CGFloat)y {
  if ((nextRandom() & 1023) >= CAPSULE_CHANCE) {
    return;
  }
  for (int i = 0; i < MAX_CAPSULES; i++) {
    if (!capsules[i].active) {
      capsules[i].active = YES;
      capsules[i].x = centerX - CAPSULE_WIDTH / 2;
      capsules[i].y = y;
      capsules[i].type = (PowerUp)(nextRandom() & 3);
      return;
    }
  }
}

- (void)moveCapsules {
  CGFloat paddleWidth = [self paddleWidth];
  for (int i = 0; i < MAX_CAPSULES; i++) {
    Capsule *capsule = &capsules[i];
    if (!capsule->active) {
      continue;
    }
    capsule->y += CAPSULE_SPEED;
    if (overlaps(capsule->x, capsule->y, CAPSULE_WIDTH, CAPSULE_HEIGHT,
                 paddleX - paddleWidth / 2, [self paddleY], paddleWidth,
                 PADDLE_HEIGHT)) {
      capsule->active = NO;
      SoundPlay(SoundPowerUp);
      [self applyPowerUp:capsule->type];
    } else if (capsule->y > [self height]) {
      capsule->active = NO;
    }
  }
}

- (void)applyPowerUp:(PowerUp)powerUp {
  switch (powerUp) {
  case PowerUpBall:
    if (ballsLeft < MAX_BALLS_LEFT) {
      ballsLeft++;
    }
    break;
  case PowerUpPaddle:
    longPaddleTicks = POWER_UP_TICKS;
    [self movePaddleTo:paddleX];
    break;
  case PowerUpSlow:
    slowTicks = POWER_UP_TICKS;
    break;
  case PowerUpMulti:
    [self addBalls:2];
    break;
  default:
    break;
  }
}

// Splits new balls off the first ball in play, heading up and outwards.
- (void)addBalls:(int)count {
  Ball *source = 0;
  for (int i = 0; i < MAX_BALLS_IN_PLAY; i++) {
    if (balls[i].active) {
      source = &balls[i];
      break;
    }
  }
  if (!source) {
    return;
  }
  CGFloat directions[2] = {-BALL_SPEED * 0.8f, BALL_SPEED * 0.8f};
  for (int i = 0; i < MAX_BALLS_IN_PLAY && count > 0; i++) {
    if (!balls[i].active) {
      balls[i] = *source;
      balls[i].dx = directions[count & 1];
      balls[i].dy = -BALL_SPEED;
      count--;
    }
  }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
  UITouch *touch = [touches anyObject];
  [self movePaddleTo:[touch locationInView:self].x];

  if (state == StateServing) {
    balls[0].dx = BALL_SPEED * 0.6f;
    balls[0].dy = -BALL_SPEED;
    state = StatePlaying;
    timerRunning = YES;
  } else if (state == StateTitle &&
             [self button:[self speedButtonFrame]
                 contains:[touch locationInView:self]]) {
    speed = speed + 1 < SpeedCount ? (Speed)(speed + 1) : SpeedNormal;
    saveInteger(SPEED_KEY, speed);
    SoundPlay(SoundBounce);
  } else if (state == StateTitle &&
             [self button:[self soundButtonFrame]
                 contains:[touch locationInView:self]]) {
    BOOL enabled = !SoundIsEnabled();
    SoundSetEnabled(enabled);
    saveInteger(SOUND_OFF_KEY, !enabled);
    SoundPlay(SoundBounce); // Only heard when turning sound on.
  } else if (state == StateTitle) {
    gamesPlayed++;
    saveInteger(GAMES_PLAYED_KEY, gamesPlayed);
    [self resetGame];
  } else if (state == StateWon || state == StateLost) {
    state = StateTitle;
  }
}

- (CGRect)speedButtonFrame {
  return CGRectMake([self width] / 2 - 100, [self height] * 0.76f, 200, 36);
}

- (CGRect)soundButtonFrame {
  return CGRectMake([self width] / 2 - 100, [self height] * 0.86f, 200, 36);
}

- (BOOL)button:(CGRect)frame contains:(CGPoint)point {
  return point.x >= frame.origin.x &&
         point.x < frame.origin.x + frame.size.width &&
         point.y >= frame.origin.y &&
         point.y < frame.origin.y + frame.size.height;
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

- (void)drawTitleWithContext:(CGContextRef)context {
  CGFloat width = [self width];
  CGFloat height = [self height];

  [self drawText:"DARED"
          inRect:CGRectMake(0, height * 0.22f, width, 50)
        fontSize:44
         context:context];
  [self drawText:"BRICKS"
          inRect:CGRectMake(0, height * 0.22f + 48, width, 50)
        fontSize:44
         context:context];

  // A strip of bricks in the row colors.
  CGFloat brickWidth = 36, gap = 6;
  CGFloat stripLeft =
      (width - BRICK_ROWS * brickWidth - (BRICK_ROWS - 1) * gap) / 2;
  for (int i = 0; i < BRICK_ROWS; i++) {
    CGContextSetRGBFillColor(context, rowColors[i][0], rowColors[i][1],
                             rowColors[i][2], 1);
    CGContextFillRect(context, CGRectMake(stripLeft + i * (brickWidth + gap),
                                          height * 0.22f + 112, brickWidth,
                                          BRICK_HEIGHT));
  }

  // The fastest time at the chosen speed.
  char text[48];
  [self fastestText:text];
  [self drawText:text
          inRect:CGRectMake(0, height * 0.52f, width, 26)
        fontSize:18
         context:context];

  char playedText[32] = "Games played: ";
  playedText[appendNumber(playedText, 14, gamesPlayed)] = 0;
  [self drawText:playedText
          inRect:CGRectMake(0, height * 0.52f + 30, width, 24)
        fontSize:16
         context:context];

  [self drawText:"Tap to play"
          inRect:CGRectMake(0, height * 0.65f, width, 30)
        fontSize:22
         context:context];

  char speedText[32] = "Speed: ";
  appendString(speedText, 7, speedNames[speed]);
  [self drawButton:[self speedButtonFrame] text:speedText context:context];
  [self drawButton:[self soundButtonFrame]
              text:(SoundIsEnabled() ? "Sound: On" : "Sound: Off")
           context:context];
}

// "Fastest (speed): time", or "none yet" in place of the time.
- (void)fastestText:(char *)text {
  int length = appendString(text, 0, "Fastest (");
  length = appendString(text, length, speedNames[speed]);
  length = appendString(text, length, "): ");
  if (fastestTicks[speed] > 0) {
    appendTime(text, length, fastestTicks[speed], YES);
  } else {
    appendString(text, length, "none yet");
  }
}

- (void)drawButton:(CGRect)frame
              text:(const char *)text
           context:(CGContextRef)context {
  CGContextSetRGBFillColor(context, 0.25f, 0.25f, 0.3f, 1);
  CGContextFillRect(context, frame);
  [self drawText:text
          inRect:CGRectMake(frame.origin.x, frame.origin.y + 7,
                            frame.size.width, frame.size.height - 7)
        fontSize:18
         context:context];
}

- (void)drawRect:(CGRect)rect {
  CGContextRef context = UIGraphicsGetCurrentContext();
  CGFloat width = [self width];
  CGFloat height = [self height];

  CGContextSetRGBFillColor(context, 0, 0, 0, 1);
  CGContextFillRect(context, [self bounds]);

  if (state == StateTitle) {
    [self drawTitleWithContext:context];
    return;
  }

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

  // Pieces of broken bricks, fading out and shrinking towards their center.
  CGFloat pieceWidth = BRICK_WIDTH / PIECE_COLUMNS;
  CGFloat pieceHeight = BRICK_HEIGHT / PIECE_ROWS;
  for (int i = 0; i < MAX_PIECES; i++) {
    if (!pieces[i].active) {
      continue;
    }
    CGFloat life = (CGFloat)pieces[i].ticksLeft / PIECE_TICKS;
    CGFloat scale = 0.5f + 0.5f * life;
    const CGFloat *color = rowColors[pieces[i].row];
    CGContextSetRGBFillColor(context, color[0], color[1], color[2], life);
    CGContextFillRect(context,
                      CGRectMake(pieces[i].x + pieceWidth * (1 - scale) / 2,
                                 pieces[i].y + pieceHeight * (1 - scale) / 2,
                                 pieceWidth * scale, pieceHeight * scale));
  }

  // Game time, in the upper left, as minutes:seconds.
  char timeText[24] = "Time: ";
  appendTime(timeText, 6, timerTicks, NO);
  [self drawText:timeText
          inRect:CGRectMake(10, 20, 150, 24)
        fontSize:16
       alignment:UITextAlignmentLeft
         context:context];

  // Balls left, in the upper right. MAX_BALLS_LEFT is a single digit.
  char ballsText[] = "Balls: 0";
  ballsText[sizeof(ballsText) - 2] = (char)('0' + ballsLeft);
  [self drawText:ballsText
          inRect:CGRectMake(width - 110, 20, 100, 24)
        fontSize:16
       alignment:UITextAlignmentRight
         context:context];

  // Active P and S effects, with the seconds they have left, in between.
  char effectsText[24];
  int length = 0;
  if (longPaddleTicks > 0) {
    effectsText[length++] = 'P';
    effectsText[length++] = ' ';
    length = appendNumber(effectsText, length, (longPaddleTicks + 59) / 60);
  }
  if (slowTicks > 0) {
    if (length > 0) {
      effectsText[length++] = ' ';
      effectsText[length++] = ' ';
    }
    effectsText[length++] = 'S';
    effectsText[length++] = ' ';
    length = appendNumber(effectsText, length, (slowTicks + 59) / 60);
  }
  effectsText[length] = 0;
  if (length > 0) {
    [self drawText:effectsText
            inRect:CGRectMake(width / 2 - 60, 20, 120, 24)
          fontSize:16
           context:context];
  }

  if (state == StateWon) {
    [self drawText:"YOU WIN"
            inRect:CGRectMake(0, height / 2 - 60, width, 50)
          fontSize:40
           context:context];
    char text[48];
    int timeLength = appendString(text, 0, "Your time (");
    timeLength = appendString(text, timeLength, speedNames[speed]);
    timeLength = appendString(text, timeLength, "): ");
    appendTime(text, timeLength, timerTicks, YES);
    [self drawText:text
            inRect:CGRectMake(0, height / 2, width, 26)
          fontSize:18
           context:context];
    if (newRecord) {
      [self drawText:"NEW RECORD!"
              inRect:CGRectMake(0, height / 2 + 30, width, 30)
            fontSize:24
             context:context];
    } else {
      char fastest[48];
      [self fastestText:fastest];
      [self drawText:fastest
              inRect:CGRectMake(0, height / 2 + 32, width, 26)
            fontSize:18
             context:context];
    }
    [self drawText:"Tap to continue"
            inRect:CGRectMake(0, height / 2 + 90, width, 30)
          fontSize:18
           context:context];
    return;
  }
  if (state == StateLost) {
    [self drawText:"GAME OVER"
            inRect:CGRectMake(0, height / 2 - 40, width, 50)
          fontSize:40
           context:context];
    [self drawText:"Tap to continue"
            inRect:CGRectMake(0, height / 2 + 20, width, 30)
          fontSize:18
           context:context];
    return;
  }

  for (int i = 0; i < MAX_CAPSULES; i++) {
    if (!capsules[i].active) {
      continue;
    }
    const CGFloat *color = powerUpColors[capsules[i].type];
    CGContextSetRGBFillColor(context, color[0], color[1], color[2], 1);
    CGRect frame =
        CGRectMake(capsules[i].x, capsules[i].y, CAPSULE_WIDTH, CAPSULE_HEIGHT);
    CGContextFillRect(context, frame);
    [self drawText:powerUpLetters[capsules[i].type]
            inRect:CGRectMake(frame.origin.x, frame.origin.y - 1, CAPSULE_WIDTH,
                              CAPSULE_HEIGHT + 2)
          fontSize:11
           context:context];
  }

  CGFloat paddleWidth = [self paddleWidth];
  CGContextSetRGBFillColor(context, 0.9f, 0.9f, 0.9f, 1);
  CGContextFillRect(context,
                    CGRectMake(paddleX - paddleWidth / 2, [self paddleY],
                               paddleWidth, PADDLE_HEIGHT));
  CGContextSetRGBFillColor(context, 1, 1, 1, 1);
  for (int i = 0; i < MAX_BALLS_IN_PLAY; i++) {
    if (balls[i].active) {
      CGContextFillRect(
          context, CGRectMake(balls[i].x, balls[i].y, BALL_SIZE, BALL_SIZE));
    }
  }

  if (state == StateServing) {
    [self drawText:"Tap to serve"
            inRect:CGRectMake(0, height / 2 + 20, width, 30)
          fontSize:18
           context:context];
  }
}

@end
