# Android 16KB page size support

`librnnoise.so` for Android is rebuilt from source with 16KB ELF alignment (package 1.0.1).

## Environment

| Item | Value |
| --- | --- |
| Source | [gsgou/RNNoiseSharp](https://github.com/gsgou/RNNoiseSharp) `0aeb0d345229ff77dc6851822f45c3650cc160fe` (see `native/rnnoise/UPSTREAM.md`) |
| NDK | r27c `27.2.12479018` (also bundled with Unity 6000.0 / 6000.3 Android module) |
| API level | android-24 |
| ABIs | arm64-v8a, armeabi-v7a |
| 16KB setting | `APP_SUPPORT_FLEXIBLE_PAGE_SIZES := true` in `native/rnnoise/Build/jni/Application.mk` |

Install the NDK with `sdkmanager "ndk;27.2.12479018"`, or use the one bundled with Unity
(`<Unity>/PlaybackEngines/AndroidPlayer/NDK`).

## Rebuild

```bash
ANDROID_NDK_HOME=/path/to/ndk/27.2.12479018 scripts/build-rnnoise-android.sh
```

The script checks the NDK revision, builds both ABIs into `build/rnnoise-android/` (git-ignored),
verifies them, and only then copies them to
`Assets/Adrenak.RNNoise4Unity/Plugins/Android/{arm64,armeabi-v7a}/librnnoise.so`. `.meta` files are not touched.

Verify any `.so` without building:

```bash
ANDROID_NDK_HOME=... scripts/build-rnnoise-android.sh --check path/to/librnnoise.so
```

Checks (non-zero exit on failure):

- ELF class/machine: ELF64/AArch64 for arm64-v8a, ELF32/ARM for armeabi-v7a
- arm64-v8a: every `PT_LOAD` aligned to >= 0x4000, offset and vaddr congruent mod 16KB,
  no LOAD data in the 16KB page following the end of `GNU_RELRO`
- Exported: `rnnoise_get_size`, `rnnoise_init`, `rnnoise_create`, `rnnoise_destroy`, `rnnoise_process_frame`
- `DT_NEEDED` limited to `liblog.so libc.so libm.so libdl.so`

## Results

### Binaries

| ABI | SHA-256 |
| --- | --- |
| arm64-v8a | `1fddeda0bf79cc7b4df0d826bdd76fda585f1654086e9fa167ef3114bdb945a3` |
| armeabi-v7a | `4a0ac7872f2a434db288f9920334e9cc4766667e6c4afa9ea3e3d6dfbfc827d7` |

### Static check, arm64-v8a

| | 1.0.0 | 1.0.1 |
| --- | --- | --- |
| Compiler | clang 11.0.5 (NDK r22b) | clang 18.0.3 (NDK r27c) |
| `PT_LOAD` align | 0x1000 | 0x4000 |
| `--check` | FAIL (align, offset/vaddr, RELRO) | PASS |
| Exported symbols / `DT_NEEDED` | 5 / liblog, libc, libm, libdl | same |

Build warning (not changed, upstream code): `rnn.c` uses `*(int*)0=0` as an abort on invalid model
data; clang 18 warns it may be removed. The built-in model never reaches that path.

### APK check

A minimal Unity 6000.3.24f1 project (IL2CPP, ARM64) was built twice, with the 1.0.0 and the 1.0.1
`librnnoise.so`. The `.so` inside each APK is byte-identical to the input (no stripping).

| | 1.0.0 APK | 1.0.1 APK |
| --- | --- | --- |
| `lib/arm64-v8a/librnnoise.so` `PT_LOAD` align | 0x1000 (only 4KB library in the APK) | 0x4000 |
| Other `.so` (libunity, libil2cpp, libmain, ...) | 0x4000 | 0x4000 |
| `zipalign -c -P 16 4` (build-tools 36.0.0) | OK | OK |

Native libraries are stored compressed in these APKs, so ZIP alignment is not the deciding factor;
the ELF alignment of `librnnoise.so` is.

### Device check

Device: SH-M28, Android 16 (API 36), arm64-v8a, `getconf PAGE_SIZE` = 4096.

At startup the app denoises a fixed synthetic signal (48 kHz mono, 5 s: noise, tone + noise, silence)
in 480-sample frames with `Denoiser` and writes the output.

| | 1.0.0 | 1.0.1 |
| --- | --- | --- |
| Load / create / 500 frames / destroy | OK | OK |
| NaN / Inf in output | 0 | 0 |
| Output RMS | 0.058893 | 0.058893 |
| Time per frame | 0.128 ms | 0.109 ms |

Output difference, 1.0.0 vs 1.0.1 (16-bit scale, x32767): max 0.037, RMS 0.0028,
27,670 of 240,000 samples bit-identical. Acceptance threshold was max <= 1.0 (one 16-bit step): PASS.
The small difference comes from the compiler change (clang 11 -> 18).

## Not done

- Run on a 16KB-page kernel (test device runs 4KB pages)
- armeabi-v7a runtime test (test device is arm64-only)
- Integration into the production app, AAB check, other `.so` files in the app
- Listening test with real microphone input, per-frame timing on target devices
