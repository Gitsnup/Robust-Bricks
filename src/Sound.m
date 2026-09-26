/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "Sound.h"
#include "System.h"

// Bundle resource names, in the order of the Sound enum.
static const char *const soundNames[SoundCount] = {"bounce", "explode",
                                                   "powerup"};

static ALuint sources[SoundCount];
static BOOL loaded[SoundCount];
static BOOL enabled = YES;

static unsigned int readLE16(const unsigned char *p) {
  return p[0] | (p[1] << 8);
}

static unsigned int readLE32(const unsigned char *p) {
  return p[0] | (p[1] << 8) | (p[2] << 16) | ((unsigned int)p[3] << 24);
}

// Finds the samples in a WAV file. Only the format the game ships is
// accepted: uncompressed 16-bit mono.
static BOOL parseWav(const unsigned char *bytes, unsigned int length,
                     const unsigned char **samples, unsigned int *size,
                     unsigned int *rate) {
  if (length < 12 || readLE32(bytes) != 0x46464952 /* RIFF */ ||
      readLE32(bytes + 8) != 0x45564157 /* WAVE */) {
    return NO;
  }
  BOOL formatOK = NO;
  unsigned int offset = 12;
  while (offset + 8 <= length) {
    unsigned int chunkID = readLE32(bytes + offset);
    unsigned int chunkSize = readLE32(bytes + offset + 4);
    const unsigned char *chunk = bytes + offset + 8;
    if (chunkSize > length - offset - 8) {
      return NO;
    }
    if (chunkID == 0x20746d66 /* "fmt " */ && chunkSize >= 16) {
      formatOK = readLE16(chunk) == 1 /* PCM */ && readLE16(chunk + 2) == 1 &&
                 readLE16(chunk + 14) == 16;
      *rate = readLE32(chunk + 4);
    } else if (chunkID == 0x61746164 /* "data" */) {
      *samples = chunk;
      *size = chunkSize;
      return formatOK;
    }
    offset += 8 + chunkSize + (chunkSize & 1);
  }
  return NO;
}

void SoundInit(void) {
  ALCdevice *device = alcOpenDevice(0);
  if (!device) {
    return;
  }
  ALCcontext *context = alcCreateContext(device, 0);
  if (!context || !alcMakeContextCurrent(context)) {
    return;
  }

  NSString *type = [NSString stringWithUTF8String:"wav"];
  for (int i = 0; i < SoundCount; i++) {
    NSString *path = [[NSBundle mainBundle]
        pathForResource:[NSString stringWithUTF8String:soundNames[i]]
                 ofType:type];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    const unsigned char *samples;
    unsigned int size, rate;
    if (!data ||
        !parseWav([data bytes], [data length], &samples, &size, &rate)) {
      continue;
    }

    ALuint buffer;
    alGenBuffers(1, &buffer);
    alBufferData(buffer, AL_FORMAT_MONO16, samples, size, rate);
    alGenSources(1, &sources[i]);
    alSourcei(sources[i], AL_BUFFER, buffer);
    loaded[i] = alGetError() == AL_NO_ERROR;
  }
}

void SoundSetEnabled(BOOL newEnabled) { enabled = newEnabled; }

BOOL SoundIsEnabled(void) { return enabled; }

void SoundPlay(Sound sound) {
  // Playing a source that is already playing restarts it.
  if (enabled && loaded[sound]) {
    alSourcePlay(sources[sound]);
  }
}
