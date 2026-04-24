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
  # LTO disabled: LTO strips ffmpeg's OptionDef tables via dead-code elimination,
  # causing all command-line flags to be treated as output filenames at runtime.

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
  --enable-ffmpeg
  --enable-avcodec
  --enable-avformat
  --enable-swscale
  --enable-swresample
  --enable-decoder=h264
  --enable-decoder=mjpeg
  --enable-demuxer=mov
  --enable-demuxer=mjpeg
  --enable-parser=h264
  --enable-parser=mjpeg
  --enable-encoder=libx264
  --enable-encoder=mjpeg
  --enable-muxer=mp4
  --enable-muxer=mjpeg
  --enable-muxer=image2
  --enable-filter=format
  --enable-filter=scale
  --enable-protocol=file
  --enable-bsf=h264_mp4toannexb

  --extra-cflags="-I$SCRIPT_DIR/build/include -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_SIGNAL"
  # Stack size: ff_mjpegenc_huffman_compute_bits allocates two PackageMergerList
  # structs (~41 KB total) on the shadow stack. The default WASM shadow stack is
  # 64 KB (__stack_pointer = 65536), which is insufficient — the call chain
  # leading here consumes another ~10-15 KB, causing stack underflow past
  # address 0 and a wasm trap: out of bounds memory access.
  # 512 KB provides enough headroom for the full MJPEG encoder call chain.
  --extra-ldflags="-L$SCRIPT_DIR/build/lib -lwasi-emulated-process-clocks -lwasi-emulated-signal -Wl,-z,stack-size=524288"
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
