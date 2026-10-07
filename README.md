# Robust Bricks

A homebrew brick-breaker game for iPhone OS 2.x. Drag to move the paddle and
tap to serve. Tap **Pause** during a run to resume, restart, or return to the
title screen.

## Endless play

Each run begins with a fresh mirrored board, followed by four handcrafted
Arkanoid-inspired layouts. After those, the game generates new mirrored boards
without a final level. Ball speed increases by 5% every five levels, up to a
50% increase. The saved high score is the **highest level reached**, tracked
separately for each difficulty. The score counter resets for each run.

## Difficulties

The title-screen difficulty selector replaces the old speed selector. Each
profile changes several rules:

| Difficulty | Ball speed | Paddle width | Starting balls | Random-board density | Capsule chance | Score multiplier |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Casual | 0.8× | 80 | 5 | 60% | 22.5% | 1× |
| Classic | 1.0× | 64 | 3 | 70% | 16.7% | 1× |
| Tough | 1.4× | 56 | 2 | 75% | 12.5% | 2× |
| Expert | 1.8× | 48 | 1 | 80% | 8.3% | 3× |

## Scoring

Each broken brick adds points according to its color, multiplied by the chosen
difficulty:

| Brick color (top to bottom) | Base points |
| --- | ---: |
| Red | 60 |
| Orange | 50 |
| Yellow | 40 |
| Green | 30 |
| Blue | 20 |
| Purple | 10 |

## Build

The GitHub Actions workflow builds `build/RobustBricks.ipa` on pushes and pull
requests. To build locally, download the Linux/macOS common-3.0 SDK from the
[SDK releases](https://github.com/touchHLE/common-3.0-sdk/releases), extract it,
and run:

```sh
make SDK=/path/to/common-3.0.sdk
```

The build supports iPhone OS 2.0 and later (armv6 and armv7). For the existing
test configurations, use `make clean` before rebuilding with
`CAPSULE_CHANCE=1024` or `FULL_PADDLE=true`.

I am not affiliated with iDared.
