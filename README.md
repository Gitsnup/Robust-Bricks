# Robust Bricks

A homebrew brick-breaker game for iPhone OS 2.x and Android. The Android app is
a native Java/Canvas port of the complete iPhone game: endless progression,
four difficulty profiles, color-based scoring, saved high-level records, pause
and restart controls, all five power-ups, sound effects, particle fragments,
trail effects, and the title/help/game-over screens.

## Gameplay

Drag to move the paddle and tap to serve. On Android, the **Pause** button or
the system Back key opens the pause menu; choose Resume, Restart Run, or Return
to Title. The game starts with a generated board and four handcrafted boards,
then generates new boards without a final level. Ball speed increases by 5%
every five levels, up to a 50% increase. High scores record the highest level
reached, separately for each difficulty. Run score resets when a new run begins.

| Difficulty | Ball speed | Paddle width | Starting balls | Random-board density | Capsule chance | Score multiplier |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Casual | 0.8× | 80 | 5 | 60% | 22.5% | 1× |
| Classic | 1.0× | 64 | 3 | 70% | 16.7% | 1× |
| Tough | 1.4× | 56 | 2 | 75% | 12.5% | 2× |
| Expert | 1.8× | 48 | 1 | 80% | 8.3% | 3× |

Brick rows (top to bottom: red, orange, yellow, green, blue, purple) award
60, 50, 40, 30, 20, and 10 base points respectively, before the difficulty
multiplier. Power-ups grant an extra life, a wider paddle, a slower ball, two
additional balls in play, or a temporary smaller paddle.

## Android build

The native Android project lives in [`android/`](android/). It requires JDK 17
or later and Android SDK platform 35/build tools 35.0.0. From the repository
root:

```sh
cd android
./gradlew assembleDebug
```

The debug APK is written to
`android/app/build/outputs/apk/debug/app-debug.apk`. Install it on a connected
device with `adb install -r app/build/outputs/apk/debug/app-debug.apk`. GitHub
Actions builds and uploads the APK on pushes and pull requests.

## iPhone OS build

The existing GitHub Actions workflow builds `build/RobustBricks.ipa` on pushes
and pull requests. To build locally, download the Linux/macOS common-3.0 SDK
from the [SDK releases](https://github.com/touchHLE/common-3.0-sdk/releases),
extract it, and run:

```sh
make SDK=/path/to/common-3.0.sdk
```

The iOS build supports iPhone OS 2.0 and later (armv6 and armv7). For its
existing test configurations, use `make clean` before rebuilding with
`CAPSULE_CHANCE=1024` or `FULL_PADDLE=true`.

I am not affiliated with iDared.
