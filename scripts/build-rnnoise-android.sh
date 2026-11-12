#!/usr/bin/env bash
# Rebuild librnnoise.so for Android (arm64-v8a, armeabi-v7a) with 16KB page
# alignment, verify the ELF files, and only then replace the package binaries.
#
# Usage: ANDROID_NDK_HOME=/path/to/ndk/27.2.12479018 scripts/build-rnnoise-android.sh
#        scripts/build-rnnoise-android.sh --check path/to/arm64/librnnoise.so ...
set -euo pipefail

NDK_REVISION="27.2.12479018"
API_LEVEL="android-24"
ABIS="armeabi-v7a arm64-v8a"
REQUIRED_SYMBOLS="rnnoise_get_size rnnoise_init rnnoise_create rnnoise_destroy rnnoise_process_frame"
ALLOWED_NEEDED="liblog.so libc.so libm.so libdl.so"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/native/rnnoise"
OUT="$ROOT/build/rnnoise-android"
PLUGINS="$ROOT/Assets/Adrenak.RNNoise4Unity/Plugins/Android"

die() { echo "ERROR: $*" >&2; exit 1; }

: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to NDK $NDK_REVISION}"
actual="$(sed -n 's/^Pkg.Revision *= *//p' "$ANDROID_NDK_HOME/source.properties")"
[[ "$actual" == "$NDK_REVISION" ]] || die "NDK $NDK_REVISION required, got '$actual' ($ANDROID_NDK_HOME)"
LLVM_BIN="$(echo "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin)"
[[ -x "$LLVM_BIN/llvm-readelf" ]] || die "llvm-readelf not found in $LLVM_BIN"

# check_so <abi> <file>: exit non-zero on any failed condition.
check_so() {
  local abi="$1" so="$2" fail=0
  echo "== check $abi $so"
  local hdr; hdr="$("$LLVM_BIN/llvm-readelf" -hW "$so")"
  local class machine
  class="$(awk '/Class:/{print $2}' <<<"$hdr")"
  machine="$(awk -F': *' '/Machine:/{print $2}' <<<"$hdr")"
  case "$abi" in
    arm64-v8a)   [[ "$class" == ELF64 && "$machine" == AArch64 ]] || { echo "  NG ELF $class/$machine"; fail=1; } ;;
    armeabi-v7a) [[ "$class" == ELF32 && "$machine" == ARM ]]     || { echo "  NG ELF $class/$machine"; fail=1; } ;;
  esac
  echo "  ELF $class/$machine"

  # PT_LOAD alignment and RELRO (16KB is required for 64-bit only).
  if [[ "$abi" == arm64-v8a ]]; then
    local page=$((0x4000)) loads=() relro_end=0
    while read -r type off vaddr _ _ memsz rest; do
      local align="${rest##* }"
      if [[ "$type" == LOAD ]]; then
        echo "  LOAD off=$off vaddr=$vaddr align=$align"
        (( align >= page )) || { echo "  NG LOAD align $align < 0x4000"; fail=1; }
        (( off % page == vaddr % page )) || { echo "  NG LOAD offset/vaddr not congruent mod 16KB"; fail=1; }
        loads+=("$vaddr $memsz")
      elif [[ "$type" == GNU_RELRO ]]; then
        relro_end=$(( vaddr + memsz ))
      fi
    done < <("$LLVM_BIN/llvm-readelf" -lW "$so" | awk '$1=="LOAD"||$1=="GNU_RELRO"')
    if (( relro_end )); then
      # The loader mprotects RELRO up to the next page boundary; no LOAD data
      # may live in [relro_end, roundup(relro_end, 16KB)).
      local pe=$(( (relro_end + page - 1) / page * page )) l
      for l in "${loads[@]}"; do
        set -- $l
        if (( $1 < pe && $1 + $2 > relro_end )); then
          echo "  NG data after RELRO end $(printf 0x%x $relro_end) shares a 16KB page"; fail=1
        fi
      done
      echo "  GNU_RELRO end=$(printf 0x%x $relro_end)"
    fi
  fi

  local syms; syms="$("$LLVM_BIN/llvm-nm" -D --defined-only "$so" | awk '{print $3}')"
  local s; for s in $REQUIRED_SYMBOLS; do
    grep -qx "$s" <<<"$syms" || { echo "  NG missing symbol $s"; fail=1; }
  done
  echo "  symbols OK: $REQUIRED_SYMBOLS"

  local n; for n in $("$LLVM_BIN/llvm-readelf" -dW "$so" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
    [[ " $ALLOWED_NEEDED " == *" $n "* ]] || { echo "  NG unexpected DT_NEEDED $n"; fail=1; }
  done
  echo "  DT_NEEDED: $("$LLVM_BIN/llvm-readelf" -dW "$so" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | tr '\n' ' ')"
  return $fail
}

if [[ "${1:-}" == --check ]]; then
  shift; rc=0
  for so in "$@"; do
    abi=arm64-v8a; [[ "$("$LLVM_BIN/llvm-readelf" -hW "$so")" == *ELF32* ]] && abi=armeabi-v7a
    check_so "$abi" "$so" || rc=1
  done
  exit $rc
fi

rm -rf "$OUT"
mkdir -p "$OUT"
"$ANDROID_NDK_HOME/ndk-build" \
  -C "$SRC/Build" \
  NDK_PROJECT_PATH=. \
  APP_BUILD_SCRIPT=jni/Android.mk \
  NDK_APPLICATION_MK=jni/Application.mk \
  NDK_OUT="$OUT/obj" \
  NDK_LIBS_OUT="$OUT/libs" \
  APP_ABI="$ABIS" \
  APP_PLATFORM="$API_LEVEL"

for abi in $ABIS; do check_so "$abi" "$OUT/libs/$abi/librnnoise.so"; done

# Unity folder names differ from ABI names (arm64-v8a -> arm64). .meta untouched.
cp "$OUT/libs/arm64-v8a/librnnoise.so"   "$PLUGINS/arm64/librnnoise.so"
cp "$OUT/libs/armeabi-v7a/librnnoise.so" "$PLUGINS/armeabi-v7a/librnnoise.so"

{
  echo "source: $(sed -n 's/^Commit: *//p' "$SRC/UPSTREAM.md")"
  echo "ndk: $NDK_REVISION"
  echo "api: $API_LEVEL"
  echo "abis: $ABIS"
  echo "flags: APP_SUPPORT_FLEXIBLE_PAGE_SIZES=true (-Wl,-z,max-page-size=16384)"
  for abi in $ABIS; do echo "sha256 $abi: $(shasum -a 256 "$OUT/libs/$abi/librnnoise.so" | cut -d' ' -f1)"; done
} | tee "$OUT/build-info.txt"
echo "replaced: $PLUGINS/{arm64,armeabi-v7a}/librnnoise.so"
