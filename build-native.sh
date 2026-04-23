#!/bin/bash

set -euox pipefail

WASI_SDK=/opt/wasi-sdk
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR"

# Symlink wasi-sdk so existing scripts' relative paths resolve correctly
if [ ! -e wasi-sdk ]; then
    ln -s "$WASI_SDK" wasi-sdk
fi

mkdir -p build

# --- x264 ---
if [ -f "$SCRIPT_DIR/build/lib/libx264.a" ]; then
    echo "x264 already built, skipping"
else
cd deps/x264
CC="$WASI_SDK/bin/clang" \
    AR="$WASI_SDK/bin/ar" \
    RANLIB="$WASI_SDK/bin/ranlib" \
    ./configure \
    --prefix="$SCRIPT_DIR/build" \
    --host=i686-gnu \
    --enable-static \
    --disable-cli \
    --disable-asm \
    --disable-thread \
    --extra-cflags="-D_WASI_EMULATED_SIGNAL -msimd128" \
    --extra-ldflags="-lwasi-emulated-signal"
perl -i -pe 's/#define HAVE_MALLOC_H 1/#define HAVE_MALLOC_H 0/g' config.h
make install-lib-static
cd "$SCRIPT_DIR"
fi # end x264 skip

# --- zlib ---
if [ -f "$SCRIPT_DIR/build/lib/libz.a" ] && [ "$(wc -c < "$SCRIPT_DIR/build/lib/libz.a")" -gt 10000 ]; then
    echo "zlib already built, skipping"
else
cd deps/zlib
CC="$WASI_SDK/bin/clang" \
    AR="$WASI_SDK/bin/ar" \
    RANLIB="$WASI_SDK/bin/ranlib" \
    prefix="$SCRIPT_DIR/build" \
    CFLAGS="-msimd128" \
    ./configure --static
# zlib configure on Darwin overrides AR with macOS libtool (drops WASM objects)
perl -i -pe "s|^AR=.*|AR=$WASI_SDK/bin/ar|" Makefile
perl -i -pe "s|^ARFLAGS=.*|ARFLAGS=rcs|" Makefile
perl -i -pe "s|^RANLIB=.*|RANLIB=$WASI_SDK/bin/ranlib|" Makefile
make install
git reset --hard
cd "$SCRIPT_DIR"
fi # end zlib skip

# --- FFmpeg configure ---
FFMPEG_CONFIG_FLAGS=(
  --target-os=none
  --arch=x86_32
  --enable-cross-compile
  --disable-x86asm
  --disable-inline-asm
  --disable-stripping
  --disable-doc
  --disable-debug
  --disable-runtime-cpudetect
  --disable-autodetect
  --disable-network
  --disable-pthreads
  --disable-w32threads
  --disable-os2threads
  --pkg-config-flags="--static"
  --enable-lto

  --nm="$WASI_SDK/bin/nm"
  --ar="$WASI_SDK/bin/ar"
  --ranlib="$WASI_SDK/bin/ranlib"
  --cc="$WASI_SDK/bin/clang"
  --cxx="$WASI_SDK/bin/clang++"
  --objcc="$WASI_SDK/bin/clang"
  --dep-cc="$WASI_SDK/bin/clang"

  --enable-gpl
  --enable-libx264
  --enable-zlib

  --disable-everything
  --enable-decoder=h264
  --enable-decoder=mjpeg
  --enable-demuxer=mov
  --enable-demuxer=mjpeg
  --enable-encoder=libx264
  --enable-muxer=mp4
  --enable-protocol=file

  --extra-cflags="-I$SCRIPT_DIR/build/include -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_SIGNAL -msimd128"
  --extra-ldflags="-L$SCRIPT_DIR/build/lib -lwasi-emulated-process-clocks -lwasi-emulated-signal"
)

cd FFmpeg
PKG_CONFIG_PATH="$SCRIPT_DIR/build/lib/pkgconfig" ./configure "${FFMPEG_CONFIG_FLAGS[@]}"
cd "$SCRIPT_DIR"

# --- FFmpeg build ---
cd FFmpeg
perl -i -pe 's,tempnam,NULL; //tempnam,g' ./libavutil/file_open.c
make -j$(sysctl -n hw.logicalcpu)
cp ffmpeg "$SCRIPT_DIR/ffmpeg.wasm"
cp ffprobe "$SCRIPT_DIR/ffprobe.wasm"
git reset --hard
cd "$SCRIPT_DIR"

# --- wasm-opt ---
wasm-opt -O3 -o ffmpeg.wasm ffmpeg.wasm
wasm-opt -O3 -o ffprobe.wasm ffprobe.wasm

echo "Done: $(ls -lh ffmpeg.wasm ffprobe.wasm)"
