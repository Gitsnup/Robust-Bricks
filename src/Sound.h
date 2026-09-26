/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// Sound effects, played through OpenAL.

#include "System.h"

typedef enum {
  SoundBounce, // Off the paddle.
  SoundWall,   // Off a wall or the ceiling.
  SoundExplode,
  SoundPowerUp,
  SoundPowerDown,
  SoundCount
} Sound;

// Loads the sounds. If anything fails, the game simply stays silent.
void SoundInit(void);
void SoundPlay(Sound sound);

// Sound is on unless turned off; SoundPlay does nothing while it's off.
void SoundSetEnabled(BOOL enabled);
BOOL SoundIsEnabled(void);
