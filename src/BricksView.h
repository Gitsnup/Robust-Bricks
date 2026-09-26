/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "System.h"

#define BRICK_ROWS 6
#define BRICK_COLUMNS 8
#define BALLS_PER_GAME 3

typedef enum { StateServing, StatePlaying, StateWon, StateLost } GameState;

@interface BricksView : UIView {
  GameState state;
  BOOL bricks[BRICK_ROWS][BRICK_COLUMNS];
  int bricksLeft;
  int ballsLeft;        // Including the one in play.
  CGFloat paddleX;      // Center of the paddle.
  CGFloat ballX, ballY; // Top-left corner of the ball.
  CGFloat ballDX, ballDY;
}
- (void)tick;
@end
