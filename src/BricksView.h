/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "System.h"

#define BRICK_ROWS 6
#define BRICK_COLUMNS 8
#define BALLS_PER_GAME 3
#define MAX_BALLS_LEFT 9 // The counter shows a single digit.
#define MAX_BALLS_IN_PLAY 8
#define MAX_CAPSULES 6

typedef enum {
  StateTitle,
  StateServing,
  StatePlaying,
  StateWon,
  StateLost
} GameState;

// What a falling capsule does when the paddle catches it.
typedef enum {
  PowerUpBall,   // B: one more ball in the counter.
  PowerUpPaddle, // P: a longer paddle, for a while.
  PowerUpSlow,   // S: half-speed balls, for a while.
  PowerUpMulti,  // M: two more balls in play at once.
  PowerUpCount
} PowerUp;

typedef struct {
  BOOL active;
  CGFloat x, y; // Top-left corner.
  CGFloat dx, dy;
} Ball;

typedef struct {
  BOOL active;
  CGFloat x, y; // Top-left corner.
  PowerUp type;
} Capsule;

@interface BricksView : UIView {
  GameState state;
  BOOL bricks[BRICK_ROWS][BRICK_COLUMNS];
  int bricksLeft;
  int ballsLeft;  // Including the ones in play.
  int timerTicks; // Game time, in ticks of 1/60 s.
  BOOL timerRunning;
  int fastestTicks; // Fastest win, saved between launches; 0 if none yet.
  BOOL newRecord;   // The game just won set a new fastest time.
  CGFloat paddleX;  // Center of the paddle.
  Ball balls[MAX_BALLS_IN_PLAY];
  Capsule capsules[MAX_CAPSULES];
  int longPaddleTicks; // Ticks left of the P power-up.
  int slowTicks;       // Ticks left of the S power-up.
}
- (void)tick;
@end
