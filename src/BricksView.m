/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// An endless brick-breaking game with Casual, Classic, Tough and Expert rules.
// Each run starts with one random board and four handcrafted boards, then
// continues with random boards forever. The title screen saves the highest
// level reached for each difficulty. Tap Pause during a run to resume, restart
// or return to the title. Colored bricks award different points, increased on
// harder difficulties. The campaign starts with difficulty-specific lives;
// each life is lost only when the last ball in play falls.
//
// Broken bricks sometimes drop a capsule, which takes effect if the paddle
// catches it: B (ball added), P (paddle size increased, for 15 seconds), S
// (slower ball, for 15 seconds), M (multiple balls, 2 more) or R (reduce paddle
// size, for 15 seconds). R is the bad one, and the only red capsule. P and R
// cancel each other out, so an R caught during a P just ends the P, and a P
// caught during an R just ends the R. A life is only lost when the last ball in
// play falls, and losing one ends any P, S or R effect and clears falling
// capsules.

#include "BricksView.h"
#include "Sound.h"
#include "System.h"

#define BRICK_WIDTH 36.0f
#define BRICK_HEIGHT 14.0f
#define BRICK_GAP 4.0f
#define BRICKS_TOP 94.0f

#define PADDLE_HEIGHT 10.0f
#define PADDLE_FROM_BOTTOM 50.0f

#define BALL_SIZE 8.0f
#define BALL_SPEED 4.0f // Along each axis, in points per tick.

#define CAPSULE_WIDTH 26.0f
#define CAPSULE_HEIGHT 14.0f
#define CAPSULE_SPEED 2.0f // Points per tick.
// Capsule drops are difficulty-specific; CAPSULE_CHANCE can override them for
// testing. Random comparisons use bit masking because armv6/armv7 lack divide.

// For testing: 1 makes the paddle as wide as the screen, so no ball is lost.
#ifndef FULL_PADDLE
#define FULL_PADDLE 0
#endif

#define POWER_UP_TICKS (15 * 60) // How long P, S and R last.
// How long the paddle flashes in a capsule's color after catching it.
#define FLASH_TICKS 24

// A broken brick splits into PIECE_COLUMNS x PIECE_ROWS pieces, which fly off
// under gravity and fade out over PIECE_TICKS.
#define PIECE_COLUMNS 4
#define PIECE_ROWS 2
#define PIECE_TICKS 30
#define PIECE_GRAVITY 0.25f // Points per tick, per tick.

// The NSUserDefaults key for the selected difficulty.
#define DIFFICULTY_KEY "Difficulty"
// The NSUserDefaults key for turning sound off. Sound is on by default, when
// the key is missing.
#define SOUND_OFF_KEY "SoundOff"

// One color per row, top to bottom.
static const CGFloat rowColors[BRICK_ROWS][3] = {
    {0.90f, 0.20f, 0.20f}, {0.95f, 0.55f, 0.15f}, {0.95f, 0.85f, 0.20f},
    {0.30f, 0.80f, 0.30f}, {0.20f, 0.70f, 0.90f}, {0.45f, 0.35f, 0.90f},
};

// Levels 2–5, top to bottom. Each byte is one row, with bit 0 as the leftmost
// brick. The layouts are symmetric patterns inspired by classic block games.
static const unsigned char
    levelLayouts[HANDCRAFTED_LEVEL_COUNT - 1][BRICK_ROWS] = {
    {0x3c, 0x7e, 0xff, 0xff, 0x7e, 0x3c}, // Diamond
    {0xff, 0x00, 0xff, 0x00, 0xff, 0x00}, // Bars
    {0x81, 0xc3, 0x66, 0x3c, 0x66, 0xc3}, // Arrow
    {0xff, 0x99, 0x99, 0xff, 0x99, 0x99}, // Gate
};

// Difficulty rules, score multipliers, and per-difficulty saved records.
static const char *const difficultyNames[DifficultyCount] = {
    "Casual", "Classic", "Tough", "Expert"};
static const CGFloat difficultySpeedMultipliers[DifficultyCount] = {
    0.8f, 1.0f, 1.4f, 1.8f};
#if !FULL_PADDLE
static const CGFloat difficultyPaddleWidths[DifficultyCount] = {
    80.0f, 64.0f, 56.0f, 48.0f};
#endif
static const int difficultyStartingBalls[DifficultyCount] = {5, 3, 2, 1};
static const int difficultyBrickDensity[DifficultyCount] = {614, 717, 768, 819};
#ifndef CAPSULE_CHANCE
static const int difficultyCapsuleChances[DifficultyCount] = {230, 171, 128, 85};
#endif
static const int difficultyScoreMultipliers[DifficultyCount] = {1, 1, 2, 3};
static const char *const bestLevelKeys[DifficultyCount] = {
    "BestLevelCasual", "BestLevelClassic", "BestLevelTough", "BestLevelExpert"};
static const char *const gamesPlayedKeys[DifficultyCount] = {
    "GamesPlayedCasual", "GamesPlayedClassic", "GamesPlayedTough",
    "GamesPlayedExpert"};

// Arkanoid-style values, top (red) to bottom (purple).
static const int brickScores[BRICK_ROWS] = {60, 50, 40, 30, 20, 10};

// Capsule letters and colors, in the order of the PowerUp enum.
// Only R, the bad one, is red.
static const char *const powerUpLetters[PowerUpCount] = {"B", "P", "S", "M",
                                                         "R"};
static const CGFloat powerUpColors[PowerUpCount][3] = {
    {0.80f, 0.30f, 0.75f}, {0.25f, 0.50f, 0.95f}, {0.20f, 0.70f, 0.35f},
    {0.95f, 0.55f, 0.10f}, {0.90f, 0.10f, 0.10f},
};

// What each capsule does, for the How to Play screen.
static const char *const powerUpDescriptions[PowerUpCount] = {
    "Ball added",
    "Paddle size increased (15 seconds)",
    "Slower ball (15 seconds)",
    "Multiple balls (2 more)",
    "Reduce paddle size (15 seconds)",
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

// Appends an effect's letter and the seconds it has left, if it's active.
static int appendEffect(char *text, int length, char letter, int ticksLeft) {
  if (ticksLeft <= 0) {
    return length;
  }
  if (length > 0) {
    text[length++] = ' ';
    text[length++] = ' ';
  }
  text[length++] = letter;
  text[length++] = ' ';
  return appendNumber(text, length, (ticksLeft + 59) / 60);
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
    for (int i = 0; i < DifficultyCount; i++) {
      bestLevel[i] = (int)loadInteger(bestLevelKeys[i]);
      gamesPlayed[i] = (int)loadInteger(gamesPlayedKeys[i]);
    }
    NSInteger savedDifficulty = loadInteger(DIFFICULTY_KEY);
    difficulty = savedDifficulty >= 0 && savedDifficulty < DifficultyCount
                     ? (Difficulty)savedDifficulty
                     : DifficultyClassic;
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
  CGFloat baseWidth = difficultyPaddleWidths[difficulty];
  if (longPaddleTicks > 0) {
    return baseWidth + 24.0f;
  }
  if (shortPaddleTicks > 0) {
    CGFloat shortWidth = baseWidth * 0.75f;
    return shortWidth < 36.0f ? 36.0f : shortWidth;
  }
  return baseWidth;
#endif
}

- (int)capsuleChance {
#ifdef CAPSULE_CHANCE
  return CAPSULE_CHANCE;
#else
  return difficultyCapsuleChances[difficulty];
#endif
}

// A random layout, mirrored left to right so it looks deliberate. Density
// depends on difficulty and a layout needs at least 16 bricks.
- (void)randomizeBricks {
  do {
    bricksLeft = 0;
    for (int row = 0; row < BRICK_ROWS; row++) {
      for (int column = 0; column < BRICK_COLUMNS / 2; column++) {
        BOOL present =
            (nextRandom() & 1023) < difficultyBrickDensity[difficulty];
        bricks[row][column] = present;
        bricks[row][BRICK_COLUMNS - 1 - column] = present;
        bricksLeft += present ? 2 : 0;
      }
    }
  } while (bricksLeft < 16);
}

- (void)loadLevel:(int)newLevel {
  level = newLevel;
  if (level == 1 || level > HANDCRAFTED_LEVEL_COUNT) {
    [self randomizeBricks];
    return;
  }

  const unsigned char *layout = levelLayouts[level - 2];
  bricksLeft = 0;
  for (int row = 0; row < BRICK_ROWS; row++) {
    for (int column = 0; column < BRICK_COLUMNS; column++) {
      BOOL present = (layout[row] & (1u << column)) != 0;
      bricks[row][column] = present;
      bricksLeft += present ? 1 : 0;
    }
  }
}

// Ends the P and S effects and removes falling capsules and extra balls.
- (void)clearPowerUps {
  longPaddleTicks = 0;
  shortPaddleTicks = 0;
  slowTicks = 0;
  flashTicks = 0;
  for (int i = 0; i < MAX_CAPSULES; i++) {
    capsules[i].active = NO;
  }
  for (int i = 0; i < MAX_BALLS_IN_PLAY; i++) {
    balls[i].active = NO;
  }
}

- (void)resetGame {
  [self loadLevel:1];
  [self clearPowerUps];
  for (int i = 0; i < MAX_PIECES; i++) {
    pieces[i].active = NO;
  }
  ballsLeft = difficultyStartingBalls[difficulty];
  score = 0;
  timerTicks = 0;
  timerRunning = NO;
  newRecord = NO;
  paddleX = [self width] / 2;
  state = StateServing;
  [self placeBallOnPaddle];
}

- (void)recordLevelReached {
  if (level > bestLevel[difficulty]) {
    bestLevel[difficulty] = level;
    newRecord = YES;
    saveInteger(bestLevelKeys[difficulty], level);
  }
}

- (void)startLevel:(int)newLevel {
  [self loadLevel:newLevel];
  [self recordLevelReached];
  [self clearPowerUps];
  [self movePaddleTo:paddleX];
  timerRunning = NO;
  state = StateServing;
  [self placeBallOnPaddle];
}

- (void)placeBallOnPaddle {
  balls[0].active = YES;
  balls[0].x = paddleX - BALL_SIZE / 2;
  balls[0].y = [self paddleY] - BALL_SIZE;
  balls[0].dx = 0;
  balls[0].dy = 0;
  balls[0].trailCount = 0;
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
  // Pause freezes fragments and power-up timers as well as ball movement.
  if (state != StatePaused) {
    [self movePieces];
  }
  [self setNeedsDisplay];
}

- (void)play {
  if (flashTicks > 0) {
    flashTicks--;
  }
  if (longPaddleTicks > 0 && --longPaddleTicks == 0) {
    // Back to the normal width: keep the paddle on screen.
    [self movePaddleTo:paddleX];
  }
  if (shortPaddleTicks > 0 && --shortPaddleTicks == 0) {
    [self movePaddleTo:paddleX];
  }
  if (slowTicks > 0) {
    slowTicks--;
  }
  int speedIncrease = (level - 1) / 5;
  if (speedIncrease > 10) {
    speedIncrease = 10;
  }
  CGFloat factor = difficultySpeedMultipliers[difficulty] *
                   (1.0f + speedIncrease * 0.05f) *
                   (slowTicks > 0 ? 0.5f : 1.0f);
  // At the faster speeds each ball moves in smaller steps, so it can't pass
  // through the paddle or a corner of a brick between one step and the next.
  int steps = factor > 2 ? 3 : factor > 1 ? 2 : 1;
  CGFloat stepFactor = factor / steps;

  BOOL anyBall = NO;
  for (int i = 0; i < MAX_BALLS_IN_PLAY && state == StatePlaying; i++) {
    if (balls[i].active) {
      [self recordTrail:&balls[i]];
    }
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

- (void)recordTrail:(Ball *)ball {
  for (int i = TRAIL_LENGTH - 1; i > 0; i--) {
    ball->trailX[i] = ball->trailX[i - 1];
    ball->trailY[i] = ball->trailY[i - 1];
  }
  ball->trailX[0] = ball->x;
  ball->trailY[0] = ball->y;
  if (ball->trailCount < TRAIL_LENGTH) {
    ball->trailCount++;
  }
}

- (void)moveBall:(Ball *)ball speed:(CGFloat)factor {
  ball->x += ball->dx * factor;
  ball->y += ball->dy * factor;

  // Walls and ceiling. A corner hit plays the sound once.
  BOOL hitWall = NO;
  if (ball->x < 0) {
    ball->x = 0;
    ball->dx = absf(ball->dx);
    hitWall = YES;
  } else if (ball->x + BALL_SIZE > [self width]) {
    ball->x = [self width] - BALL_SIZE;
    ball->dx = -absf(ball->dx);
    hitWall = YES;
  }
  if (ball->y < 0) {
    ball->y = 0;
    ball->dy = absf(ball->dy);
    hitWall = YES;
  }
  if (hitWall) {
    SoundPlay(SoundWall);
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
      int points = brickScores[row] * difficultyScoreMultipliers[difficulty];
      score = score > 2147483647 - points ? 2147483647 : score + points;
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
        [self clearPowerUps];
        timerRunning = NO;
        state = StateLevelComplete;
      } else {
        [self maybeDropCapsuleAtX:x + BRICK_WIDTH / 2 y:y];
      }
      return;
    }
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
      piece->gravity = PIECE_GRAVITY;
      piece->ticksLeft = PIECE_TICKS;
      piece->lifeTicks = PIECE_TICKS;
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
    piece->dy += piece->gravity;
    if (--piece->ticksLeft == 0) {
      piece->active = NO;
    }
  }
}

- (void)maybeDropCapsuleAtX:(CGFloat)centerX y:(CGFloat)y {
  if ((nextRandom() & 1023) >= [self capsuleChance]) {
    return;
  }
  for (int i = 0; i < MAX_CAPSULES; i++) {
    if (!capsules[i].active) {
      capsules[i].active = YES;
      capsules[i].x = centerX - CAPSULE_WIDTH / 2;
      capsules[i].y = y;
      // Each type equally likely. (No %: armv6/armv7 have no divide.)
      capsules[i].type =
          (PowerUp)(((nextRandom() & 1023) * PowerUpCount) >> 10);
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
      SoundPlay(capsule->type == PowerUpShrink ? SoundPowerDown
                                               : SoundPowerUp);
      [self applyPowerUp:capsule->type];
      flashTicks = FLASH_TICKS;
      flashType = capsule->type;
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
    // P and R cancel each other out.
    if (shortPaddleTicks > 0) {
      shortPaddleTicks = 0;
    } else {
      longPaddleTicks = POWER_UP_TICKS;
    }
    [self movePaddleTo:paddleX];
    break;
  case PowerUpSlow:
    slowTicks = POWER_UP_TICKS;
    break;
  case PowerUpMulti:
    [self addBalls:2];
    break;
  case PowerUpShrink:
    if (longPaddleTicks > 0) {
      longPaddleTicks = 0;
    } else {
      shortPaddleTicks = POWER_UP_TICKS;
    }
    [self movePaddleTo:paddleX];
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
  CGPoint point = [touch locationInView:self];

  if (state == StatePaused) {
    if ([self button:[self resumeButtonFrame] contains:point]) {
      state = pausedState;
      timerRunning = state == StatePlaying;
      SoundPlay(SoundBounce);
    } else if ([self button:[self restartButtonFrame] contains:point]) {
      gamesPlayed[difficulty]++;
      saveInteger(gamesPlayedKeys[difficulty], gamesPlayed[difficulty]);
      [self resetGame];
      [self recordLevelReached];
      SoundPlay(SoundBounce);
    } else if ([self button:[self returnTitleButtonFrame] contains:point]) {
      timerRunning = NO;
      state = StateTitle;
      SoundPlay(SoundBounce);
    }
    return;
  }

  if ((state == StateServing || state == StatePlaying ||
       state == StateLevelComplete) &&
      [self button:[self pauseButtonFrame] contains:point]) {
    pausedState = state;
    timerRunning = NO;
    state = StatePaused;
    SoundPlay(SoundBounce);
    return;
  }

  if (state == StateServing || state == StatePlaying ||
      state == StateLevelComplete) {
    [self movePaddleTo:point.x];
  }

  if (state == StateServing) {
    balls[0].dx = BALL_SPEED * 0.6f;
    balls[0].dy = -BALL_SPEED;
    state = StatePlaying;
    timerRunning = YES;
  } else if (state == StateLevelComplete) {
    [self startLevel:level + 1];
    SoundPlay(SoundBounce);
  } else if (state == StateTitle &&
             [self button:[self howToPlayButtonFrame] contains:point]) {
    state = StateHowToPlay;
    SoundPlay(SoundBounce);
  } else if (state == StateHowToPlay) {
    if ([self button:[self goBackButtonFrame] contains:point]) {
      state = StateTitle;
      SoundPlay(SoundBounce);
    }
  } else if (state == StateTitle &&
             [self button:[self difficultyButtonFrame] contains:point]) {
    difficulty = difficulty + 1 < DifficultyCount
                     ? (Difficulty)(difficulty + 1)
                     : DifficultyCasual;
    saveInteger(DIFFICULTY_KEY, difficulty);
    SoundPlay(SoundBounce);
  } else if (state == StateTitle &&
             [self button:[self soundButtonFrame] contains:point]) {
    BOOL enabled = !SoundIsEnabled();
    SoundSetEnabled(enabled);
    saveInteger(SOUND_OFF_KEY, !enabled);
    SoundPlay(SoundBounce); // Only heard when turning sound on.
  } else if (state == StateTitle) {
    gamesPlayed[difficulty]++;
    saveInteger(gamesPlayedKeys[difficulty], gamesPlayed[difficulty]);
    [self resetGame];
    [self recordLevelReached];
  } else if (state == StateLost) {
    state = StateTitle;
  }
}

- (CGRect)howToPlayButtonFrame {
  return CGRectMake([self width] / 2 - 100, [self height] * 0.66f, 200, 36);
}

- (CGRect)difficultyButtonFrame {
  return CGRectMake([self width] / 2 - 100, [self height] * 0.75f, 200, 36);
}

- (CGRect)soundButtonFrame {
  return CGRectMake([self width] / 2 - 100, [self height] * 0.84f, 200, 36);
}

// On the How to Play screen.
- (CGRect)goBackButtonFrame {
  return CGRectMake([self width] / 2 - 100, [self height] * 0.86f, 200, 36);
}

- (CGRect)pauseButtonFrame {
  return CGRectMake([self width] - 70, 42, 60, 30);
}

- (CGRect)resumeButtonFrame {
  return CGRectMake([self width] / 2 - 100, [self height] * 0.47f, 200, 36);
}

- (CGRect)restartButtonFrame {
  return CGRectMake([self width] / 2 - 100, [self height] * 0.59f, 200, 36);
}

- (CGRect)returnTitleButtonFrame {
  return CGRectMake([self width] / 2 - 100, [self height] * 0.71f, 200, 36);
}

- (BOOL)button:(CGRect)frame contains:(CGPoint)point {
  return point.x >= frame.origin.x &&
         point.x < frame.origin.x + frame.size.width &&
         point.y >= frame.origin.y &&
         point.y < frame.origin.y + frame.size.height;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
  if (state == StateServing || state == StatePlaying) {
    UITouch *touch = [touches anyObject];
    [self movePaddleTo:[touch locationInView:self].x];
  }
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

  [self drawText:"ROBUST"
          inRect:CGRectMake(0, height * 0.14f, width, 50)
        fontSize:44
         context:context];
  [self drawText:"BRICKS"
          inRect:CGRectMake(0, height * 0.14f + 48, width, 50)
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
                                          height * 0.14f + 112, brickWidth,
                                          BRICK_HEIGHT));
  }

  char recordText[48];
  [self bestLevelText:recordText];
  [self drawText:recordText
          inRect:CGRectMake(0, height * 0.44f, width, 26)
        fontSize:16
         context:context];

  // Games played at the selected difficulty.
  char playedText[48];
  int playedLength = appendString(playedText, 0, "Games played (");
  playedLength = appendString(playedText, playedLength,
                              difficultyNames[difficulty]);
  playedLength = appendString(playedText, playedLength, "): ");
  playedText[appendNumber(playedText, playedLength,
                          gamesPlayed[difficulty])] = 0;
  [self drawText:playedText
          inRect:CGRectMake(0, height * 0.44f + 30, width, 24)
        fontSize:16
         context:context];

  [self drawText:"Tap to play"
          inRect:CGRectMake(0, height * 0.56f, width, 30)
        fontSize:22
         context:context];

  [self drawButton:[self howToPlayButtonFrame]
              text:"How to Play"
           context:context];
  char difficultyText[32] = "Difficulty: ";
  appendString(difficultyText, 12, difficultyNames[difficulty]);
  [self drawButton:[self difficultyButtonFrame]
              text:difficultyText
           context:context];
  [self drawButton:[self soundButtonFrame]
              text:(SoundIsEnabled() ? "Sound: On" : "Sound: Off")
           context:context];
}

- (void)drawHowToPlayWithContext:(CGContextRef)context {
  CGFloat width = [self width];

  [self drawText:"HOW TO PLAY"
          inRect:CGRectMake(0, 24, width, 36)
        fontSize:28
         context:context];
  [self drawText:"Drag to move and tap to serve. Tap Pause for the menu. "
                 "Boards continue endlessly and speed rises every five levels. "
                 "Brick rows score 60 down to 10; harder modes multiply points."
          inRect:CGRectMake(16, 74, width - 32, 80)
        fontSize:15
       alignment:UITextAlignmentLeft
         context:context];
  [self drawText:"Broken bricks sometimes drop a capsule. Catch it with the "
                 "paddle:"
          inRect:CGRectMake(16, 158, width - 32, 40)
        fontSize:15
       alignment:UITextAlignmentLeft
         context:context];

  for (int i = 0; i < PowerUpCount; i++) {
    CGFloat y = 206 + i * 30;
    [self drawCapsule:(PowerUp)i x:20 y:y context:context];
    [self drawText:powerUpDescriptions[i]
            inRect:CGRectMake(20 + CAPSULE_WIDTH + 12, y - 2,
                              width - 20 - CAPSULE_WIDTH - 12 - 8, 20)
          fontSize:14
         alignment:UITextAlignmentLeft
           context:context];
  }

  [self drawText:"P and R cancel each other out. Losing a ball ends P, S "
                 "and R."
          inRect:CGRectMake(16, 206 + PowerUpCount * 30 + 6, width - 32, 40)
        fontSize:14
       alignment:UITextAlignmentLeft
         context:context];

  [self drawButton:[self goBackButtonFrame] text:"Go Back" context:context];
}

- (void)drawCapsule:(PowerUp)type
                  x:(CGFloat)x
                  y:(CGFloat)y
            context:(CGContextRef)context {
  const CGFloat *color = powerUpColors[type];
  CGContextSetRGBFillColor(context, color[0], color[1], color[2], 1);
  CGContextFillRect(context, CGRectMake(x, y, CAPSULE_WIDTH, CAPSULE_HEIGHT));
  [self drawText:powerUpLetters[type]
          inRect:CGRectMake(x, y - 1, CAPSULE_WIDTH, CAPSULE_HEIGHT + 2)
        fontSize:11
         context:context];
}

// Shows the highest level reached in the selected difficulty.
- (void)bestLevelText:(char *)text {
  int length = appendString(text, 0, "Best level (");
  length = appendString(text, length, difficultyNames[difficulty]);
  length = appendString(text, length, "): ");
  if (bestLevel[difficulty] > 0) {
    length = appendNumber(text, length, bestLevel[difficulty]);
  } else {
    length = appendString(text, length, "none yet");
  }
  text[length] = 0;
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
  if (state == StateHowToPlay) {
    [self drawHowToPlayWithContext:context];
    return;
  }
  if (state == StatePaused) {
    [self drawText:"PAUSED"
            inRect:CGRectMake(0, height * 0.28f, width, 48)
          fontSize:36
           context:context];
    [self drawButton:[self resumeButtonFrame] text:"Resume" context:context];
    [self drawButton:[self restartButtonFrame]
                text:"Restart Run"
             context:context];
    [self drawButton:[self returnTitleButtonFrame]
                text:"Return to Title"
             context:context];
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

  // Pieces of broken bricks and bursts, fading out and shrinking towards
  // their center.
  CGFloat pieceWidth = BRICK_WIDTH / PIECE_COLUMNS;
  CGFloat pieceHeight = BRICK_HEIGHT / PIECE_ROWS;
  for (int i = 0; i < MAX_PIECES; i++) {
    if (!pieces[i].active) {
      continue;
    }
    CGFloat life = (CGFloat)pieces[i].ticksLeft / pieces[i].lifeTicks;
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

  // Active P, R and S effects, with the seconds they have left.
  // P and R never both show, as each one ends the other.
  char effectsText[24];
  int length = 0;
  length = appendEffect(effectsText, length, 'P', longPaddleTicks);
  length = appendEffect(effectsText, length, 'R', shortPaddleTicks);
  length = appendEffect(effectsText, length, 'S', slowTicks);
  effectsText[length] = 0;
  if (length > 0) {
    [self drawText:effectsText
            inRect:CGRectMake(width / 2 - 60, 68, 120, 24)
          fontSize:16
           context:context];
  }

  char levelText[24] = "Level ";
  int levelLength = appendNumber(levelText, 6, level);
  levelText[levelLength] = 0;
  [self drawText:levelText
          inRect:CGRectMake(10, 42, 90, 24)
        fontSize:16
       alignment:UITextAlignmentLeft
         context:context];

  char scoreText[32] = "Score: ";
  scoreText[appendNumber(scoreText, 7, score)] = 0;
  [self drawText:scoreText
          inRect:CGRectMake(width / 2 - 75, 42, 140, 24)
        fontSize:16
         context:context];

  if (state == StateServing || state == StatePlaying ||
      state == StateLevelComplete) {
    [self drawButton:[self pauseButtonFrame] text:"Pause" context:context];
  }

  if (state == StateLevelComplete) {
    [self drawText:"LEVEL CLEARED"
            inRect:CGRectMake(0, height / 2 - 50, width, 44)
          fontSize:32
           context:context];
    char levelCompleteText[32] = "Level ";
    int completeLength = appendNumber(levelCompleteText, 6, level);
    levelCompleteText[completeLength] = 0;
    [self drawText:levelCompleteText
            inRect:CGRectMake(0, height / 2, width, 26)
          fontSize:18
           context:context];
    if (newRecord) {
      [self drawText:"NEW BEST LEVEL!"
              inRect:CGRectMake(0, height / 2 + 30, width, 30)
            fontSize:20
             context:context];
    }
    [self drawText:"Tap for next level"
            inRect:CGRectMake(0, height / 2 + 60, width, 30)
          fontSize:18
           context:context];
    return;
  }
  if (state == StateLost) {
    [self drawText:"GAME OVER"
            inRect:CGRectMake(0, height / 2 - 60, width, 50)
          fontSize:40
           context:context];
    char finalScoreText[32] = "Score: ";
    finalScoreText[appendNumber(finalScoreText, 7, score)] = 0;
    [self drawText:finalScoreText
            inRect:CGRectMake(0, height / 2, width, 26)
          fontSize:20
           context:context];
    char bestText[32] = "Best level: ";
    bestText[appendNumber(bestText, 12, bestLevel[difficulty])] = 0;
    [self drawText:bestText
            inRect:CGRectMake(0, height / 2 + 32, width, 26)
          fontSize:18
           context:context];
    [self drawText:"Tap to return"
            inRect:CGRectMake(0, height / 2 + 90, width, 30)
          fontSize:18
           context:context];
    return;
  }

  for (int i = 0; i < MAX_CAPSULES; i++) {
    if (!capsules[i].active) {
      continue;
    }
    [self drawCapsule:capsules[i].type
                    x:capsules[i].x
                    y:capsules[i].y
              context:context];
  }

  // Ball trails, oldest first, each one fainter and smaller than the last.
  for (int i = 0; i < MAX_BALLS_IN_PLAY; i++) {
    if (!balls[i].active) {
      continue;
    }
    for (int j = balls[i].trailCount - 1; j >= 0; j--) {
      CGFloat life = (CGFloat)(TRAIL_LENGTH - j) / (TRAIL_LENGTH + 1);
      CGFloat size = BALL_SIZE * (0.4f + 0.6f * life);
      CGContextSetRGBFillColor(context, 1, 1, 1, 0.5f * life);
      CGContextFillRect(context,
                        CGRectMake(balls[i].trailX[j] + (BALL_SIZE - size) / 2,
                                   balls[i].trailY[j] + (BALL_SIZE - size) / 2,
                                   size, size));
    }
  }

  CGFloat paddleWidth = [self paddleWidth];
  // Normally light gray; after catching a capsule, it flashes the capsule's
  // color and fades back.
  CGFloat flash = (CGFloat)flashTicks / FLASH_TICKS;
  const CGFloat *flashColor = powerUpColors[flashType];
  CGContextSetRGBFillColor(context, 0.9f + (flashColor[0] - 0.9f) * flash,
                           0.9f + (flashColor[1] - 0.9f) * flash,
                           0.9f + (flashColor[2] - 0.9f) * flash, 1);
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
