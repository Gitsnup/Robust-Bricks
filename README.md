# Dared Bricks

A small brick-breaking game for iPhone OS 2.0 and later: one level, a random brick layout each game, three balls, and a timer to beat. Drag anywhere to move the paddle and tap to serve. Clear every brick to see YOU WIN; lose the last ball and it's GAME OVER. Either way, tap to play again with a new layout. The ball boops off the paddle and bricks break with a crunch.

Broken bricks sometimes drop a power-up. Catch it with the paddle:

| Capsule | Power-up |
|---|---|
| **B** | One more ball |
| **P** | A longer paddle, for 15 seconds |
| **S** | Slow balls (half speed), for 15 seconds |
| **M** | Multi-ball: two more balls in play |

With multi-ball, you only lose a ball when the last one in play falls. Losing a ball ends any P or S power-up.

It was written for [iDared 32bit](https://idared32bit-emu.com/) and [touchHLE](https://touchhle.org/), and is tested in them.

Made by [apexad](https://github.com/apexad).

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

### Testing power-ups

Normally about one broken brick in six drops a power-up. To try them all quickly, build a version where every broken brick drops one:

```
make clean
make SDK=/path/to/common-3.0.sdk CAPSULE_CHANCE=1024
```

`CAPSULE_CHANCE` is the chance out of 1024 (the default is 171). Run `make clean` before switching between this and a normal build, so the game is rebuilt with the new setting.

### Notes

The game doesn't use any SDK headers: the few system APIs it needs are declared in `src/System.h`.

The sound effects in `resources/` were generated for this game and are under the same license as the code. Sound plays through OpenAL.

## License

[Mozilla Public License 2.0](LICENSE). If you distribute a modified version, the source of the files you changed must be made available under the same license.
