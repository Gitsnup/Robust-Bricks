/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// Sound effects, played through OpenAL.

typedef enum { SoundBounce, SoundExplode, SoundCount } Sound;

// Loads the sounds. If anything fails, the game simply stays silent.
void SoundInit(void);
void SoundPlay(Sound sound);
