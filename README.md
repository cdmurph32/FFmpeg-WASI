# FFmpeg-WASI

FFmpeg-WASI compiles FFmpeg to WASM. Unlike [ffmpeg.wasm](https://github.com/ffmpegwasm/ffmpeg.wasm) the WASM binary is standalone and requires no JavaScript glue.

## Clone

Clone the repository and its submodules.

```sh
git clone --recursive https://github.com/SebastiaanYN/FFmpeg-WASI.git
```

## Build

### Native (macOS, recommended)

Requires WASI-SDK 32 or later at `/opt/wasi-sdk` and `wasm-opt` (`brew install binaryen`).

```sh
./build-native.sh
```

### Docker

```sh
DOCKER_BUILDKIT=1 docker build -t ffmpeg-wasi --output . .
# or
./build.sh
```

On Apple Silicon set `DOCKER_DEFAULT_PLATFORM=linux/amd64`.

```sh
DOCKER_DEFAULT_PLATFORM=linux/amd64 ./build.sh
```

## Usage

Requires a WASI-compatible runtime. [wasmtime](https://wasmtime.dev/)

```sh
wasmtime run --dir . ffmpeg.wasm -i input.mp4 -c:v libx264 output.mp4
```

### Convert video to MP4 with libx264

```sh
wasmtime run --dir videos ffmpeg.wasm -i videos/video-15s.avi -c:v libx264 -an videos/out.mp4
```

### Convert MJPEG stream to MP4

```sh
wasmtime run --dir /tmp ffmpeg.wasm \
  -framerate 30 -f mjpeg -i /tmp/input.mjpeg \
  -c:v libx264 -crf 1 -an \
  /tmp/out.mp4
```

## Included components

| Type | Components |
|------|-----------|
| Decoders | h264, mjpeg |
| Encoders | libx264 |
| Demuxers | mov (MP4), mjpeg |
| Muxers | mp4 |
| Protocols | file |

## Limitations

- **No audio** — audio encoder is not included; pass `-an` to drop audio streams.
- **No threading** — WASI has no pthreads; encode runs single-threaded.
- **No networking** — disabled at compile time.
- **File I/O only** — MP4 muxer requires seekable output; piping is not supported. Use preopened directories (`--dir`).

## License

This project is licensed under MIT. Be aware that the licenses of FFmpeg and other dependencies may still apply.
