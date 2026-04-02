#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# FFmpeg OpenHarmony / HarmonyOS cross build script
# Default target: arm64-v8a
# Output type: shared libraries (.so)
##############################################################################

OHOS_ARCH_LIST=("arm64-v8a")

ENABLED_CONFIG="\
  --enable-gpl \
  --enable-version3 \
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-swscale \
  --enable-swresample \
  --enable-avfilter \
  --enable-libass \
  --enable-libdav1d \
  --enable-libfreetype \
  --enable-libmp3lame \
  --enable-libx264 \
  --enable-shared \
  --enable-pic \
  --enable-protocol=file \
  --enable-muxer=mp4 \
  --enable-muxer=mp3 \
  --enable-muxer=matroska \
  --enable-muxer=wav \
  --enable-muxer=adts \
  --enable-muxer=ipod \
  --enable-demuxer=mov \
  --enable-demuxer=mp3 \
  --enable-demuxer=matroska \
  --enable-demuxer=wav \
  --enable-demuxer=aac \
  --enable-demuxer=flac \
  --enable-demuxer=ogg \
  --enable-demuxer=image2 \
  --enable-demuxer=image2pipe \
  --enable-demuxer=png_pipe \
  --enable-demuxer=mjpeg \
  --enable-decoder=aac \
  --enable-decoder=mp3 \
  --enable-decoder=flac \
  --enable-decoder=opus \
  --enable-decoder=vorbis \
  --enable-decoder=pcm_s16le \
  --enable-decoder=pcm_s24le \
  --enable-decoder=pcm_f32le \
  --enable-decoder=h264 \
  --enable-decoder=hevc \
  --enable-decoder=av1 \
  --enable-decoder=libdav1d \
  --enable-decoder=png \
  --enable-decoder=mjpeg \
  --enable-encoder=aac \
  --enable-encoder=libmp3lame \
  --enable-encoder=libx264 \
  --enable-encoder=pcm_s16le \
  --enable-filter=setpts \
  --enable-filter=atempo \
  --enable-filter=aresample \
  --enable-filter=volume \
  --enable-filter=afade \
  --enable-filter=amix \
  --enable-filter=aformat \
  --enable-filter=anull \
  --enable-filter=subtitles \
  --enable-filter=ass \
  --enable-filter=overlay \
  --enable-filter=scale \
  --enable-filter=pad \
  --enable-filter=rotate \
  --enable-filter=crop \
  --enable-filter=color \
  --enable-filter=nullsink \
  --enable-parser=aac \
  --enable-parser=h264 \
  --enable-parser=hevc \
  --enable-parser=mpegaudio \
  --enable-parser=png \
  --enable-parser=mjpeg \
  --enable-bsf=aac_adtstoasc \
  --enable-bsf=h264_mp4toannexb \
  --enable-bsf=hevc_mp4toannexb \
  --enable-bsf=extract_extradata \
  --enable-bsf=h264_metadata \
  --enable-bsf=hevc_metadata"

DISABLED_CONFIG="\
  --disable-small \
  --disable-static \
  --disable-debug \
  --disable-symver \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-doc \
  --disable-indevs \
  --disable-avdevice \
  --disable-network \
  --disable-libxml2"

normalize_path() {
    local RAW_PATH=${1:-}
    if [ -z "$RAW_PATH" ]; then
        return 0
    fi

    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$RAW_PATH"
    else
        printf '%s\n' "${RAW_PATH//\\//}"
    fi
}

find_latest_ohos_native_sdk() {
    local BASE_DIR=${1:-}
    local CANDIDATE=""
    local DIR=""

    if [ -z "$BASE_DIR" ] || [ ! -d "$BASE_DIR" ]; then
        return 1
    fi

    while IFS= read -r DIR; do
        if [ -d "$DIR/native" ]; then
            CANDIDATE="$DIR"
        fi
    done < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sort -V)

    if [ -n "$CANDIDATE" ] && [ -d "$CANDIDATE/native" ]; then
        printf '%s\n' "$CANDIDATE/native"
        return 0
    fi

    return 1
}

resolve_ohos_native_sdk() {
    if [ -n "${OHOS_NATIVE_SDK_PATH:-}" ] && [ -d "${OHOS_NATIVE_SDK_PATH:-}" ]; then
        normalize_path "$OHOS_NATIVE_SDK_PATH"
        return 0
    fi

    if [ -n "${OHOS_SDK_NATIVE:-}" ] && [ -d "${OHOS_SDK_NATIVE:-}" ]; then
        normalize_path "$OHOS_SDK_NATIVE"
        return 0
    fi

    if [ -n "${DEVECO_SDK_HOME:-}" ]; then
        local DEVECO_ROOT
        DEVECO_ROOT=$(normalize_path "$DEVECO_SDK_HOME")
        if [ -d "$DEVECO_ROOT/native" ]; then
            printf '%s\n' "$DEVECO_ROOT/native"
            return 0
        fi

        if find_latest_ohos_native_sdk "$DEVECO_ROOT" >/dev/null 2>&1; then
            find_latest_ohos_native_sdk "$DEVECO_ROOT"
            return 0
        fi
    fi

    return 1
}

generate_meson_cross_file() {
    local OUTPUT_FILE=$1
    local CC_PATH=$2
    local CXX_PATH=$3
    local CPU_FAMILY=$4
    local CPU=$5
    local EXTRA_C_ARGS=${6:-}
    local EXTRA_CPP_ARGS=${7:-}
    local EXTRA_C_LINK_ARGS=${8:-}
    local SYSTEM_NAME=${9:-linux}

    local C_ARGS="'-fPIC'"
    local CPP_ARGS="'-fPIC'"
    if [ -n "$EXTRA_C_ARGS" ]; then
        C_ARGS="'-fPIC', $EXTRA_C_ARGS"
    fi
    if [ -n "$EXTRA_CPP_ARGS" ]; then
        CPP_ARGS="'-fPIC', $EXTRA_CPP_ARGS"
    fi

    local C_LINK_ARGS=""
    local CPP_LINK_ARGS=""
    if [ -n "$EXTRA_C_LINK_ARGS" ]; then
        C_LINK_ARGS="c_link_args = [$EXTRA_C_LINK_ARGS]"
        CPP_LINK_ARGS="cpp_link_args = [$EXTRA_C_LINK_ARGS]"
    fi

    cat > "$OUTPUT_FILE" <<EOF
[binaries]
c = '$CC_PATH'
cpp = '$CXX_PATH'
ar = '$LLVM_AR'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = [$C_ARGS]
cpp_args = [$CPP_ARGS]
${C_LINK_ARGS}
${CPP_LINK_ARGS}

[host_machine]
system = '$SYSTEM_NAME'
cpu_family = '$CPU_FAMILY'
cpu = '$CPU'
endian = 'little'
EOF
}

buildLibdav1d() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CLANG_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local TARGET_TRIPLE=$8
    local CLANG="${CLANG_PREFIX}clang"
    local CLANGXX="${CLANG_PREFIX}clang++"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building libdav1d for $TARGET_ARCH ..."

    if [ ! -d "dav1d" ]; then
        git clone https://code.videolan.org/videolan/dav1d.git
    else
        cd dav1d || exit 1
        git pull
        cd ..
    fi

    cd dav1d || exit 1
    rm -rf build

    local MESON_ARCH="$TARGET_ARCH"
    [ "$MESON_ARCH" = "i686" ] && MESON_ARCH="x86"

    local CROSS_FILE="ohos-$MESON_ARCH-cross.meson"
    generate_meson_cross_file \
        "$CROSS_FILE" \
        "$CLANG" \
        "$CLANGXX" \
        "$MESON_ARCH" \
        "$TARGET_CPU" \
        "" \
        "" \
        "'-fuse-ld=lld', '--rtlib=compiler-rt', '-Wl,--gc-sections', '-Wl,-z,noexecstack'"

    meson setup build \
        --default-library=static \
        --prefix="$PREFIX" \
        --buildtype=release \
        --cross-file="$CROSS_FILE"
    ninja -C build
    ninja -C build install

    cd "$ORIG_PWD" || exit 1
    echo ">>> libdav1d build completed."
}

buildFreetype() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CLANG_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local TARGET_TRIPLE=$8
    local CLANG="${CLANG_PREFIX}clang"
    local CLANGXX="${CLANG_PREFIX}clang++"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building FreeType for $TARGET_ARCH ..."

    if [ ! -d "freetype2" ]; then
        git clone https://git.savannah.gnu.org/git/freetype/freetype2.git
    else
        cd freetype2 || exit 1
        git pull
        cd ..
    fi

    cd freetype2 || exit 1
    rm -rf build

    local MESON_ARCH="$TARGET_ARCH"
    [ "$MESON_ARCH" = "i686" ] && MESON_ARCH="x86"

    local CROSS_FILE="ohos-$MESON_ARCH-cross.meson"
    generate_meson_cross_file \
        "$CROSS_FILE" \
        "$CLANG" \
        "$CLANGXX" \
        "$MESON_ARCH" \
        "$TARGET_CPU" \
        "" \
        "" \
        "'-fuse-ld=lld', '--rtlib=compiler-rt', '-Wl,--gc-sections', '-Wl,-z,noexecstack'"

    meson setup build \
        --default-library=static \
        --prefix="$PREFIX" \
        --buildtype=release \
        --cross-file="$CROSS_FILE" \
        -Dzlib=disabled \
        -Dpng=disabled
    ninja -C build
    ninja -C build install

    cd "$ORIG_PWD" || exit 1
    echo ">>> FreeType build completed."
}

buildHarfBuzz() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CLANG_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local TARGET_TRIPLE=$8
    local CLANG="${CLANG_PREFIX}clang"
    local CLANGXX="${CLANG_PREFIX}clang++"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building HarfBuzz for $TARGET_ARCH ..."

    if [ ! -d "harfbuzz" ]; then
        git clone https://github.com/harfbuzz/harfbuzz.git
    else
        cd harfbuzz || exit 1
        git pull
        cd ..
    fi

    cd harfbuzz || exit 1
    rm -rf build

    local MESON_ARCH="$TARGET_ARCH"
    [ "$MESON_ARCH" = "i686" ] && MESON_ARCH="x86"

    local CROSS_FILE="ohos-$MESON_ARCH-cross.meson"
    generate_meson_cross_file \
        "$CROSS_FILE" \
        "$CLANG" \
        "$CLANGXX" \
        "$MESON_ARCH" \
        "$TARGET_CPU" \
        "" \
        "" \
        "'-fuse-ld=lld', '--rtlib=compiler-rt', '-Wl,--gc-sections', '-Wl,-z,noexecstack'"

    meson setup build \
        --default-library=static \
        --prefix="$PREFIX" \
        --buildtype=release \
        --cross-file="$CROSS_FILE" \
        -Dicu=disabled \
        -Dgraphite2=disabled \
        -Dglib=disabled \
        -Dgobject=disabled \
        -Dcairo=disabled \
        -Dtests=disabled \
        -Dintrospection=disabled
    ninja -C build
    ninja -C build install

    cd "$ORIG_PWD" || exit 1
    echo ">>> HarfBuzz build completed."
}

buildFriBiDi() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CLANG_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local TARGET_TRIPLE=$8
    local CLANG="${CLANG_PREFIX}clang"
    local CLANGXX="${CLANG_PREFIX}clang++"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building FriBiDi for $TARGET_ARCH ..."

    if [ ! -d "fribidi" ]; then
        git clone https://github.com/fribidi/fribidi.git
    else
        cd fribidi || exit 1
        git pull
        cd ..
    fi

    cd fribidi || exit 1
    rm -rf build

    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

    local MESON_ARCH="$TARGET_ARCH"
    [ "$MESON_ARCH" = "i686" ] && MESON_ARCH="x86"

    local CROSS_FILE="ohos-$MESON_ARCH-cross.meson"
    generate_meson_cross_file \
        "$CROSS_FILE" \
        "$CLANG" \
        "$CLANGXX" \
        "$MESON_ARCH" \
        "$TARGET_CPU" \
        "" \
        "" \
        "'-fuse-ld=lld', '--rtlib=compiler-rt', '-Wl,--gc-sections', '-Wl,-z,noexecstack'"

    meson setup build \
        --default-library=static \
        --prefix="$PREFIX" \
        --buildtype=release \
        --cross-file="$CROSS_FILE" \
        -Ddocs=false \
        -Dtests=false \
        -Ddeprecated=false
    ninja -C build
    ninja -C build install

    cd "$ORIG_PWD" || exit 1
    echo ">>> FriBiDi build completed."
}

buildLibmp3lame() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CLANG_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local TARGET_TRIPLE=$8
    local CLANG="${CLANG_PREFIX}clang"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building libmp3lame for $TARGET_ARCH ..."

    if [ ! -d "lame" ]; then
        git clone https://github.com/rbrito/lame.git lame
    else
        cd lame || exit 1
        git pull
        cd ..
    fi

    cd lame || exit 1

    export CC="$CLANG"
    export AR="$LLVM_AR"
    export RANLIB="$LLVM_RANLIB"
    export STRIP="$LLVM_STRIP"
    export CFLAGS="-fPIC -DOHOS -D__OHOS__ -D__MUSL__ $EXTRA_CFLAGS"
    export LDFLAGS="-fPIC -fuse-ld=lld --rtlib=compiler-rt -Wl,--gc-sections -Wl,-z,noexecstack -L$PREFIX/lib"

    make distclean >/dev/null 2>&1 || true

    ./configure \
        --host="$TARGET_TRIPLE" \
        --disable-frontend \
        --enable-nasm=no \
        --enable-static \
        --disable-shared \
        --prefix="$PREFIX"
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
    make install -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

    mkdir -p "$PREFIX/lib/pkgconfig"
    cat > "$PREFIX/lib/pkgconfig/lame.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: lame
Description: LAME MP3 encoder library
Version: 3.100
Libs: -L\${libdir} -lmp3lame
Cflags: -I\${includedir}
EOF

    cd "$ORIG_PWD" || exit 1
    echo ">>> libmp3lame build completed."
}

buildLibx264() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CLANG_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local TARGET_TRIPLE=$8
    local CLANG="${CLANG_PREFIX}clang"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building libx264 for $TARGET_ARCH ..."

    if [ ! -d "x264" ]; then
        git clone https://code.videolan.org/videolan/x264.git
    else
        cd x264 || exit 1
        git pull
        cd ..
    fi

    cd x264 || exit 1

    export CC="$CLANG"
    export AR="$LLVM_AR"
    export RANLIB="$LLVM_RANLIB"
    export STRIP="$LLVM_STRIP"
    export STRINGS="$LLVM_STRINGS"
    export CFLAGS="-fPIC -DOHOS -D__OHOS__ -D__MUSL__ $EXTRA_CFLAGS"
    export LDFLAGS="-fPIC -fuse-ld=lld --rtlib=compiler-rt -Wl,--gc-sections -Wl,-z,noexecstack -L$PREFIX/lib"

    ./configure \
        --host="$TARGET_TRIPLE" \
        --prefix="$PREFIX" \
        --enable-static \
        --disable-shared \
        --disable-cli \
        --disable-opencl \
        --enable-pic
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
    make install -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

    cd "$ORIG_PWD" || exit 1
    echo ">>> libx264 build completed."
}

buildLibass() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CLANG_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local TARGET_TRIPLE=$8
    local CLANG="${CLANG_PREFIX}clang"
    local CLANGXX="${CLANG_PREFIX}clang++"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building libass for $TARGET_ARCH ..."

    if [ ! -d "libass" ]; then
        git clone https://github.com/libass/libass.git
    else
        cd libass || exit 1
        git pull
        cd ..
    fi

    cd libass || exit 1
    rm -rf build

    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

    local MESON_ARCH="$TARGET_ARCH"
    [ "$MESON_ARCH" = "i686" ] && MESON_ARCH="x86"

    local CROSS_FILE="ohos-$MESON_ARCH-cross.meson"
    generate_meson_cross_file \
        "$CROSS_FILE" \
        "$CLANG" \
        "$CLANGXX" \
        "$MESON_ARCH" \
        "$TARGET_CPU" \
        "'-I$PREFIX/include', '-I$PREFIX/include/freetype2', '-I$PREFIX/include/harfbuzz', '-I$PREFIX/include/fribidi'" \
        "'-I$PREFIX/include', '-I$PREFIX/include/freetype2', '-I$PREFIX/include/harfbuzz', '-I$PREFIX/include/fribidi'" \
        "'-fuse-ld=lld', '--rtlib=compiler-rt', '-Wl,--gc-sections', '-Wl,-z,noexecstack', '-L$PREFIX/lib'"

    meson setup build \
        --default-library=static \
        --prefix="$PREFIX" \
        --buildtype=release \
        --cross-file="$CROSS_FILE" \
        -Dfontconfig=disabled \
        -Drequire-system-font-provider=false
    ninja -C build
    ninja -C build install

    cd "$ORIG_PWD" || exit 1
    echo ">>> libass build completed."
}

configure_ffmpeg() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CLANG_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local TARGET_TRIPLE=$8
    local CLANG="${CLANG_PREFIX}clang"
    local CLANGXX="${CLANG_PREFIX}clang++"

    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

    cd "$FFMPEG_SOURCE_DIR" || exit 1

    ./configure \
        --disable-everything \
        --target-os=linux \
        --arch="$TARGET_ARCH" \
        --cpu="$TARGET_CPU" \
        --pkg-config=pkg-config \
        --enable-cross-compile \
        --cc="$CLANG" \
        --cxx="$CLANGXX" \
        --ar="$LLVM_AR" \
        --nm="$LLVM_NM" \
        --ranlib="$LLVM_RANLIB" \
        --strip="$LLVM_STRIP" \
        --sysroot="$SYSROOT" \
        --prefix="$PREFIX" \
        --extra-cflags="-fPIC -DOHOS -D__OHOS__ -D__MUSL__ -fdata-sections -ffunction-sections -fstack-protector-strong -Wformat -Werror=format-security $EXTRA_CFLAGS -I$PREFIX/include -I$PREFIX/include/freetype2 -I$PREFIX/include/harfbuzz -I$PREFIX/include/fribidi -I$PREFIX/include/libass" \
        --extra-cxxflags="-fPIC -DOHOS -D__OHOS__ -D__MUSL__ -fdata-sections -ffunction-sections -fstack-protector-strong -Wformat -Werror=format-security -std=c++17 -fexceptions -frtti $EXTRA_CXXFLAGS -I$PREFIX/include" \
        --extra-ldflags="-fuse-ld=lld --rtlib=compiler-rt -Wl,--gc-sections -Wl,--no-undefined -Wl,-z,noexecstack -Qunused-arguments -L$SYSROOT_LIB_DIR -L$PREFIX/lib" \
        --enable-pic \
        ${ENABLED_CONFIG} \
        ${DISABLED_CONFIG} \
        ${EXTRA_CONFIG}

    make clean
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
    make install -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

    echo ">>> FFmpeg build completed for $TARGET_ARCH."
}

echo "Compiling FFmpeg for OpenHarmony / HarmonyOS..."

if [ -z "${FFMPEG_SOURCE_DIR:-}" ]; then
    echo "Error: FFMPEG_SOURCE_DIR is not set"
    exit 1
fi

FFMPEG_SOURCE_DIR=$(normalize_path "$FFMPEG_SOURCE_DIR")
if [ ! -d "$FFMPEG_SOURCE_DIR" ]; then
    echo "Error: FFMPEG_SOURCE_DIR does not exist: $FFMPEG_SOURCE_DIR"
    exit 1
fi

OHOS_NATIVE_SDK_PATH=$(resolve_ohos_native_sdk || true)
if [ -z "${OHOS_NATIVE_SDK_PATH:-}" ] || [ ! -d "$OHOS_NATIVE_SDK_PATH" ]; then
    echo "Error: cannot resolve OHOS native SDK path."
    echo "Set OHOS_NATIVE_SDK_PATH or OHOS_SDK_NATIVE explicitly."
    exit 1
fi

SYSROOT="$OHOS_NATIVE_SDK_PATH/sysroot"
LLVM_BIN_DIR="$OHOS_NATIVE_SDK_PATH/llvm/bin"
LLVM_AR="$LLVM_BIN_DIR/llvm-ar"
LLVM_NM="$LLVM_BIN_DIR/llvm-nm"
LLVM_RANLIB="$LLVM_BIN_DIR/llvm-ranlib"
LLVM_STRIP="$LLVM_BIN_DIR/llvm-strip"
LLVM_STRINGS="$LLVM_BIN_DIR/llvm-strings"

export ASFLAGS="-fPIC"

if [ -z "${FFMPEG_BUILD_DIR:-}" ]; then
    FFMPEG_BUILD_DIR="$(pwd)/build-ohos"
    export FFMPEG_BUILD_DIR
fi

FFMPEG_BUILD_DIR=$(normalize_path "$FFMPEG_BUILD_DIR")
mkdir -p "$FFMPEG_BUILD_DIR"

for ARCH in "${OHOS_ARCH_LIST[@]}"; do
    case "$ARCH" in
        "arm64-v8a"|"arm64"|"aarch64")
            TARGET_ARCH="aarch64"
            TARGET_CPU="armv8-a"
            TARGET_TRIPLE="aarch64-linux-ohos"
            CLANG_PREFIX="$LLVM_BIN_DIR/aarch64-unknown-linux-ohos-"
            SYSROOT_LIB_DIR="$SYSROOT/usr/lib/aarch64-linux-ohos"
            PREFIX="$FFMPEG_BUILD_DIR/arm64-v8a"
            EXTRA_CFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CXXFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CONFIG="--enable-asm --enable-neon"
            ;;
        "armeabi-v7a"|"armv7")
            TARGET_ARCH="arm"
            TARGET_CPU="armv7-a"
            TARGET_TRIPLE="arm-linux-ohos"
            CLANG_PREFIX="$LLVM_BIN_DIR/armv7-unknown-linux-ohos-"
            SYSROOT_LIB_DIR="$SYSROOT/usr/lib/arm-linux-ohos"
            PREFIX="$FFMPEG_BUILD_DIR/armeabi-v7a"
            EXTRA_CFLAGS="-O2 -march=armv7-a -mfpu=neon -mfloat-abi=softfp -fomit-frame-pointer"
            EXTRA_CXXFLAGS="-O2 -march=armv7-a -mfpu=neon -mfloat-abi=softfp -fomit-frame-pointer"
            EXTRA_CONFIG="--enable-asm --enable-neon"
            ;;
        "x86_64")
            TARGET_ARCH="x86_64"
            TARGET_CPU="x86-64"
            TARGET_TRIPLE="x86_64-linux-ohos"
            CLANG_PREFIX="$LLVM_BIN_DIR/x86_64-unknown-linux-ohos-"
            SYSROOT_LIB_DIR="$SYSROOT/usr/lib/x86_64-linux-ohos"
            PREFIX="$FFMPEG_BUILD_DIR/x86_64"
            EXTRA_CFLAGS="-O2 -fomit-frame-pointer"
            EXTRA_CXXFLAGS="-O2 -fomit-frame-pointer"
            EXTRA_CONFIG="--disable-asm"
            ;;
        *)
            echo "Error: unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    mkdir -p "$PREFIX"

    buildLibdav1d "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CLANG_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG" "$TARGET_TRIPLE"
    buildFreetype "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CLANG_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG" "$TARGET_TRIPLE"
    buildHarfBuzz "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CLANG_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG" "$TARGET_TRIPLE"
    buildFriBiDi "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CLANG_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG" "$TARGET_TRIPLE"
    buildLibass "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CLANG_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG" "$TARGET_TRIPLE"
    buildLibmp3lame "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CLANG_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG" "$TARGET_TRIPLE"
    buildLibx264 "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CLANG_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG" "$TARGET_TRIPLE"
    configure_ffmpeg "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CLANG_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG" "$TARGET_TRIPLE"
done

echo "FFmpeg build for OpenHarmony / HarmonyOS completed successfully."
