# Upstream

Repository: https://github.com/gsgou/RNNoiseSharp
Commit: 0aeb0d345229ff77dc6851822f45c3650cc160fe
License: BSD-3-Clause (RNNoiseSharp README). Per-file copyright notices are kept in the sources.

The C sources and the previously shipped `librnnoise.so` were both added in the
initial commit `54fd0ea` (2022-11-17); later commits only changed the README.

## Copied files

| Here | Upstream |
| --- | --- |
| `Source/` | `RNNoiseLib/Source/` |
| `Include/` | `RNNoiseLib/Include/` |
| `Build/jni/Android.mk`, `Application.mk`, `Makefile.srcs` | `RNNoiseLib/Build/jni/` |

`RNNoiseLib/Build/RNNoiseLib.sh` is not copied; `scripts/build-rnnoise-android.sh` replaces it for Android.

## Local changes

- `Build/jni/Application.mk`: added `APP_SUPPORT_FLEXIBLE_PAGE_SIZES := true` (16KB page alignment).
