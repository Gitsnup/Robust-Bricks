# Robust Bricks

A homebrew brick-breaker game for iPhone OS 2.x. Play a five-level campaign:
level one generates a fresh mirrored layout, followed by four handcrafted,
Arkanoid-inspired stages. Keep your remaining balls as you clear each board;
you start with three and can earn more with power-ups. Finishing the campaign
records your fastest time for the selected speed.

I am not affiliated with iDared.

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
