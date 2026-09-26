# Dared Bricks

A small brick-breaking game for iPhone OS 2.0 and later. There's one level, with a new random brick layout each game, three balls, and a timer to beat.

It was written for [iDared 32bit](https://idared32bit-emu.com/) and [touchHLE](https://touchhle.org/), and is tested in them.

Made by [apexad](https://github.com/apexad).

## How it plays

Drag anywhere to move the paddle, and tap to serve. The timer starts with your first serve.

- Clear every brick and it's YOU WIN, with bursts of colored pieces going off behind it. If that's a new fastest time, it also says NEW RECORD! and the bursts keep going.
- Lose the last ball and it's GAME OVER, with how many bricks were left.
- Either way, tap to go back to the title screen.

The ball leaves a fading trail, boops off the paddle and ticks off the walls and ceiling, and bricks shatter into flying pieces with a crunch.

## Title screen

The title screen shows your fastest winning time at the chosen speed and how many games you've played. Tap anywhere except the buttons to play. The buttons are:

- **How to Play**: a page explaining the controls and every capsule, with a **Go Back** button to return to the title screen.
- **Speed**: switches between Normal, Fast (1.5×) and Ludicrous (2.5×).
- **Sound**: turns sound on or off.

The speed, the sound setting, the fastest times (one for each speed) and the number of games played are all saved between launches.

## Capsules

Broken bricks sometimes drop a capsule. Catch it with the paddle, which flashes the capsule's color:

| Capsule | Effect |
|---|---|
| **B** | One more ball |
| **P** | A longer paddle, for 15 seconds |
| **S** | Slow balls (half speed), for 15 seconds |
| **M** | Multi-ball: two more balls in play |
| **R** | The bad one, in red: ends a **P** if you have one, otherwise a 25% shorter paddle for 15 seconds |

P and R cancel each other out, so catching a **P** while an **R** is shrinking the paddle just ends the **R**. With multi-ball, you only lose a ball when the last one in play falls. Losing a ball ends any P, S or R effect.

## Playing

Build `DaredBricks.ipa` (below) and put it in the `touchHLE_apps` folder of iDared 32bit or touchHLE; it then shows up in the app picker.

## Building

You need:

- `clang`, with ARM support. Any recent LLVM release works; clang 12 is what touchHLE uses for its own test app.
- The [common-3.0 SDK](https://github.com/touchHLE/common-3.0-sdk): download a release and extract it. It provides the linker, the startup code and stub versions of the system libraries, built only from open-source parts.

Then:

```
make SDK=/path/to/common-3.0.sdk
```

This builds `build/DaredBricks.ipa`, for armv6 and armv7. That one file is the whole app; `make clean` removes it.

### Testing capsules

Normally about one broken brick in six drops a capsule. To try them all quickly, build a version where every broken brick drops one:

```
make clean
make SDK=/path/to/common-3.0.sdk CAPSULE_CHANCE=1024
```

`CAPSULE_CHANCE` is the chance out of 1024 (the default is 171). Run `make clean` before switching between this and a normal build, so the game is rebuilt with the new setting.

### Testing without losing

To play through to the win screen without any risk of losing a ball, build a version where the paddle is as wide as the screen:

```
make clean
make SDK=/path/to/common-3.0.sdk FULL_PADDLE=true
```

The default is `FULL_PADDLE=false`. As with `CAPSULE_CHANCE`, run `make clean` when switching, and the two can be combined. Winning times from this build are saved like any others, so they'll show up as the fastest times until the app's data is cleared.

### Notes

The game doesn't use any SDK headers: the few system APIs it needs are declared in `src/System.h`.

The sound effects in `resources/` were generated for this game and are under the same license as the code. Sound plays through OpenAL.

## License

[Mozilla Public License 2.0](LICENSE). If you distribute a modified version, the source of the files you changed must be made available under the same license.
