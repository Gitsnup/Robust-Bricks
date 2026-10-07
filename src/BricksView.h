/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "System.h"

#define BRICK_ROWS 6
#define BRICK_COLUMNS 8
#define HANDCRAFTED_LEVEL_COUNT 5
#define MAX_BALLS_LEFT 9 // The counter shows a single digit.
#define MAX_BALLS_IN_PLAY 8
#define MAX_CAPSULES 6
#define MAX_PIECES 192 // Flying pieces from broken bricks.
#define TRAIL_LENGTH 6 // Earlier ball positions drawn behind each ball.

typedef enum {
  StateTitle,
  StateHowToPlay,
  StateServing,
  StatePlaying,
  StatePaused,
  StateLevelComplete,
  StateLost
} GameState;

// What a falling capsule does when the paddle catches it.
typedef enum {
  PowerUpBall,   // B: ball added (to the counter).
  PowerUpPaddle, // P: paddle size increased, for a while.
  PowerUpSlow,   // S: slower ball (half speed), for a while.
  PowerUpMulti,  // M: multiple balls (2 more in play).
  PowerUpShrink, // R: reduce paddle size (25%), for a while. The bad one.
  PowerUpCount
} PowerUp;

// The selected ruleset, chosen on the title screen.
typedef enum {
  DifficultyCasual,
  DifficultyClassic,
  DifficultyTough,
  DifficultyExpert,
  DifficultyCount
} Difficulty;

typedef struct {
  BOOL active;
  CGFloat x, y; // Top-left corner.
  CGFloat dx, dy;
  // Where the ball was on the last few ticks, most recent first.
  CGFloat trailX[TRAIL_LENGTH], trailY[TRAIL_LENGTH];
  int trailCount;
} Ball;

typedef struct {
  BOOL active;
  CGFloat x, y; // Top-left corner.
  PowerUp type;
} Capsule;

// A piece of a broken brick flying off and fading out.
typedef struct {
  BOOL active;
  CGFloat x, y; // Top-left corner.
  CGFloat dx, dy;
  CGFloat gravity; // Added to dy every tick.
  int ticksLeft, lifeTicks;
  int row; // The brick row whose color it has.
} Piece;

@interface BricksView : UIView {
  GameState state;
  GameState pausedState;
  BOOL bricks[BRICK_ROWS][BRICK_COLUMNS];
  int bricksLeft;
  int level;
  int score;
  int ballsLeft;  // Including the ones in play.
  int timerTicks; // Game time, in ticks of 1/60 s.
  BOOL timerRunning;
  Difficulty difficulty; // Saved between launches.
  // Highest level reached in each difficulty, saved between launches.
  int bestLevel[DifficultyCount];
  BOOL newRecord; // The current run reached a new best level.
  // Games played at each difficulty, saved between launches.
  int gamesPlayed[DifficultyCount];
  CGFloat paddleX; // Center of the paddle.
  Ball balls[MAX_BALLS_IN_PLAY];
  Capsule capsules[MAX_CAPSULES];
  Piece pieces[MAX_PIECES];
  int longPaddleTicks;  // Ticks left of the P power-up.
  int shortPaddleTicks; // Ticks left of the R effect.
  int slowTicks;       // Ticks left of the S power-up.
  int flashTicks;      // Ticks left of the paddle flash from a catch.
  PowerUp flashType;   // The capsule caught, for the flash color.
}
- (void)tick;
@end
