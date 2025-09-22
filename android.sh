#!/bin/bash

##############################################################################
# 目标 Android 配置信息
##############################################################################
# 目标 Android API 级别
ANDROID_API_LEVEL="25"
# 需编译的架构列表（支持：armv8a, armv7a, x86, x86-64）
ARCH_LIST=("armv8a" "armv7a" "x86" "x86-64")


##############################################################################
# FFmpeg 编译模块配置
##############################################################################
# 启用的 FFmpeg 模块/功能
ENABLED_CONFIG="\
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-swscale \
  --enable-swresample \
  --enable-avfilter \
  --enable-libass \
  --enable-libdav1d
  --enable-encoder=h264 \
  --enable-encoder=aac \
  --enable-encoder=mpeg4 \
  --enable-decoder=h264 \
  --enable-decoder=mpeg4 \
  --enable-decoder=png \
  --enable-decoder=jpeg \
  --enable-decoder=aac \
  --enable-decoder=mp3 \
  --enable-demuxer=mp4,avi,png,jpeg,aac,mp3 \
  --enable-muxer=mp4,mov \
  --enable-filter=subtitles \
  --enable-protocol=file \
  --enable-parser=h264,aac,mpeg4,png,jpeg \
  --enable-bsf=h264_mp4toannexb,aac_adtstoasc \
  --enable-small \
  --enable-shared"

# 禁用的 FFmpeg 模块/功能
DISABLED_CONFIG="\
  --disable-small \
  --disable-static \
  --disable-debug \
  --disable-symver \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-doc \
  --disable-v4l2-m2m \
  --disable-cuda-llvm \
  --disable-indevs \
  --disable-avdevice \
  --disable-network \
  --disable-libxml2"


##############################################################################
# 编译工具链路径配置（请勿修改）
##############################################################################
# Android NDK 系统根路径
SYSROOT="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
# LLVM 工具链组件路径
LLVM_AR="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
LLVM_NM="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
LLVM_RANLIB="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ranlib"
LLVM_STRIP="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

# 导出汇编器 flags（Position-Independent Code）
export ASFLAGS="-fPIC"


##############################################################################
# 编译 libdav1d（AV1 视频解码库）
# 参数说明：
# $1: 目标架构（TARGET_ARCH）
# $2: 目标 CPU（TARGET_CPU）
# $3: 安装路径（PREFIX）
# $4: 交叉编译前缀（CROSS_PREFIX）
# $5: 额外 C 编译器 flags（EXTRA_CFLAGS）
# $6: 额外 C++ 编译器 flags（EXTRA_CXXFLAGS）
# $7: 额外配置参数（EXTRA_CONFIG）
##############################################################################
buildLibdav1d() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"

    # 架构名称统一（i686 对应 x86）
    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    # 克隆/更新 libdav1d 源码
    if [ ! -d "dav1d" ]; then
        echo "Cloning libdav1d..."
        git clone https://code.videolan.org/videolan/dav1d.git
    else
        echo "Updating libdav1d..."
        cd dav1d || exit 1
        git pull
        cd ..
    fi

    # 进入源码目录编译
    cd dav1d || exit 1
    # 生成 Meson 交叉编译配置文件
    local CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
    cat > "$CROSS_FILE" <<EOF
[binaries]
c = '$CLANG'
cpp = '$CLANGXX'
ar = '$LLVM_AR'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-fpic']
cpp_args = ['-fpic']
c_link_args = ['-Wl,-z,max-page-size=16384']

[host_machine]
system = 'android'
cpu_family = '$TARGET_ARCH'
cpu = '$TARGET_CPU'
endian = 'little'
EOF

    echo "Meson cross file created: $CROSS_FILE"
    # 清理旧构建目录
    rm -rf build
    # Meson 配置 + 编译 + 安装
    meson setup build \
        --default-library=static \
        --prefix=$PREFIX \
        --buildtype release \
        --cross-file=$CROSS_FILE

    ninja -C build
    ninja -C build install
}


##############################################################################
# 编译 FreeType（字体渲染库，FFmpeg drawtext 滤镜依赖）
# 参数说明：同 buildLibdav1d
##############################################################################
buildFreetype() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"

    # 架构名称统一（i686 对应 x86）
    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    # 克隆/更新 FreeType 源码
    if [ ! -d "freetype2" ]; then
        echo "Cloning FreeType..."
        git clone https://git.savannah.gnu.org/git/freetype/freetype2.git
    else
        echo "Updating FreeType..."
        cd freetype2 || exit 1
        git pull
        cd ..
    fi

    # 进入源码目录编译
    cd freetype2 || exit 1
    # 生成 Meson 交叉编译配置文件
    local CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
    cat > "$CROSS_FILE" <<EOF
[binaries]
c = '$CLANG'
cpp = '$CLANGXX'
ar = '$LLVM_AR'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-fpic']
cpp_args = ['-fpic']

[host_machine]
system = 'android'
cpu_family = '$TARGET_ARCH'
cpu = '$TARGET_CPU'
endian = 'little'
EOF

    echo "Meson cross file created for freetype: $CROSS_FILE"
    # 清理旧构建目录
    rm -rf build
    # Meson 配置（禁用 zlib/png 依赖） + 编译 + 安装
    meson setup build \
        --default-library=static \
        --prefix=$PREFIX \
        --buildtype release \
        --cross-file=$CROSS_FILE \
        -Dzlib=disabled \
        -Dpng=disabled

    ninja -C build
    ninja -C build install

    # 验证编译结果（检查 pkg-config 配置文件）
    if [ ! -f "$PREFIX/lib/pkgconfig/freetype2.pc" ]; then
        echo "Error: freetype2.pc not found in $PREFIX/lib/pkgconfig"
        exit 1
    fi
}


##############################################################################
# 编译 HarfBuzz（文字排版引擎，FFmpeg drawtext 滤镜依赖）
# 参数说明：同 buildLibdav1d
##############################################################################
buildHarfBuzz() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"

    # 架构名称统一（i686 对应 x86）
    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    # 克隆/更新 HarfBuzz 源码
    if [ ! -d "harfbuzz" ]; then
        echo "Cloning HarfBuzz..."
        git clone https://github.com/harfbuzz/harfbuzz.git
    else
        echo "Updating HarfBuzz..."
        cd harfbuzz || exit 1
        git pull
        cd ..
    fi

    # 进入源码目录编译
    cd harfbuzz || exit 1
    # 生成 Meson 交叉编译配置文件
    local CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
    cat > "$CROSS_FILE" <<EOF
[binaries]
c = '$CLANG'
cpp = '$CLANGXX'
ar = '$LLVM_AR'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-fpic']
cpp_args = ['-fpic']

[host_machine]
system = 'android'
cpu_family = '$TARGET_ARCH'
cpu = '$TARGET_CPU'
endian = 'little'
EOF

    echo "Meson cross file created for harfbuzz: $CROSS_FILE"
    # 清理旧构建目录
    rm -rf build
    # Meson 配置（禁用冗余依赖） + 编译 + 安装
    meson setup build \
        --default-library=static \
        --prefix=$PREFIX \
        --buildtype release \
        --cross-file=$CROSS_FILE \
        -Dicu=disabled \
        -Dgraphite2=disabled \
        -Dglib=disabled \
        -Dgobject=disabled \
        -Dcairo=disabled \
        -Dtests=disabled \
        -Dintrospection=disabled

    ninja -C build
    ninja -C build install

    # 验证编译结果（检查 pkg-config 配置文件）
    if [ ! -f "$PREFIX/lib/pkgconfig/harfbuzz.pc" ]; then
        echo "Error: harfbuzz.pc not found in $PREFIX/lib/pkgconfig"
        exit 1
    fi
}


##############################################################################
# 编译 FriBidi（双向文本渲染库，libass 依赖）
# 参数说明：同 buildLibdav1d
##############################################################################
buildFriBiDi() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"

    # 架构名称统一（i686 对应 x86）
    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    # 克隆/更新 FriBidi 源码
    if [ ! -d "fribidi" ]; then
        echo "Cloning FriBidi..."
        git clone https://github.com/fribidi/fribidi.git
    else
        echo "Updating FriBidi..."
        cd fribidi || exit 1
        git pull
        cd ..
    fi

    # 进入源码目录编译
    cd fribidi || exit 1
    # 生成 Meson 交叉编译配置文件
    local CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
    cat > "$CROSS_FILE" <<EOF
[binaries]
c = '$CLANG'
cpp = '$CLANGXX'
ar = '$LLVM_AR'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-fpic']
cpp_args = ['-fpic']
c_link_args = ['-Wl,-z,max-page-size=16384']

[host_machine]
system = 'android'
cpu_family = '$TARGET_ARCH'
cpu = '$TARGET_CPU'
endian = 'little'
EOF

    echo "Meson cross file created for fribidi: $CROSS_FILE"
    # 配置 pkg-config 路径（用于依赖检测）
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

    # 清理旧构建目录
    rm -rf build
    # Meson 配置（禁用文档/测试） + 编译 + 安装
    meson setup build \
        --default-library=static \
        --prefix=$PREFIX \
        --buildtype release \
        --cross-file=$CROSS_FILE \
        -Ddocs=false \
        -Dtests=false \
        -Ddeprecated=false

    ninja -C build
    ninja -C build install

    # 验证编译结果（检查 pkg-config 配置文件）
    if [ ! -f "$PREFIX/lib/pkgconfig/fribidi.pc" ]; then
        echo "Error: fribidi.pc not found in $PREFIX/lib/pkgconfig"
        exit 1
    fi
    cd ..
}


##############################################################################
# 编译 libass（字幕渲染库，FFmpeg subtitles 滤镜依赖）
# 参数说明：同 buildLibdav1d
##############################################################################
buildLibass() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"

    # 架构名称统一（i686 对应 x86）
    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    # 克隆/更新 libass 源码
    if [ ! -d "libass" ]; then
        echo "Cloning libass..."
        git clone https://github.com/libass/libass.git
    else
        echo "Updating libass..."
        cd libass || exit 1
        git pull
        cd ..
    fi

    # 进入源码目录编译
    cd libass || exit 1
    # 生成 Meson 交叉编译配置文件（包含依赖头文件路径）
    local CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
    cat > "$CROSS_FILE" <<EOF
[binaries]
c = '$CLANG'
cpp = '$CLANGXX'
ar = '$LLVM_AR'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-fpic', '-I$PREFIX/include', '-I$PREFIX/include/freetype2', '-I$PREFIX/include/harfbuzz', '-I$PREFIX/include/fribidi']
cpp_args = ['-fpic']
c_link_args = ['-Wl,-z,max-page-size=16384']

[host_machine]
system = 'android'
cpu_family = '$TARGET_ARCH'
cpu = '$TARGET_CPU'
endian = 'little'
EOF

    echo "Meson cross file created for libass: $CROSS_FILE"
    # 配置 pkg-config 路径（用于依赖检测）
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

    # 清理旧构建目录
    rm -rf build
    # Meson 配置（启用 freetype/harfbuzz 依赖） + 编译 + 安装
    meson setup build \
        --default-library=static \
        --prefix=$PREFIX \
        --buildtype release \
        --cross-file=$CROSS_FILE \
        -Dfontconfig=disabled \
        -Drequire-system-font-provider=false

    ninja -C build
    ninja -C build install

    # 验证编译结果（检查 pkg-config 配置文件）
    if [ ! -f "$PREFIX/lib/pkgconfig/libass.pc" ]; then
        echo "Error: libass.pc not found in $PREFIX/lib/pkgconfig"
        exit 1
    fi
    cd ..
}


##############################################################################
# 配置并编译 FFmpeg（核心逻辑）
# 参数说明：同 buildLibdav1d
##############################################################################
configure_ffmpeg() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7

    # 配置 pkg-config 路径（用于依赖检测）
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"

    # 打印依赖库版本（辅助调试）
    echo "freetype2 version: $(pkg-config --modversion freetype2 2>/dev/null || echo not found)"
    echo "harfbuzz version: $(pkg-config --modversion harfbuzz 2>/dev/null || echo not found)"
    echo "fribidi version: $(pkg-config --modversion fribidi 2>/dev/null || echo not found)"
    echo "libass version: $(pkg-config --modversion libass 2>/dev/null || echo not found)"

    # 进入 FFmpeg 源码目录
    cd "$FFMPEG_SOURCE_DIR" || exit 1
    # 生成配置摘要文件（用于调试）
    local CONFIG_SUMMARY_FILE="configure.summary.$TARGET_ARCH.txt"
    # FFmpeg 配置（核心参数）
    ./configure \
        --disable-everything \
        --target-os=android \
        --arch=$TARGET_ARCH \
        --cpu=$TARGET_CPU \
        --pkg-config=pkg-config \
        --enable-cross-compile \
        --cross-prefix="$CROSS_PREFIX" \
        --cc="$CLANG" \
        --cxx="$CLANGXX" \
        --sysroot="$SYSROOT" \
        --prefix="$PREFIX" \
        --extra-cflags="-fpic -DANDROID -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -D__BIONIC_NO_PAGE_SIZE_MACRO -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security $EXTRA_CFLAGS -I$PREFIX/include -I$PREFIX/include/freetype2 -I$PREFIX/include/harfbuzz -I$PREFIX/include/fribidi -I$PREFIX/include/libass " \
        --extra-cxxflags="-fpic -DANDROID -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -D__BIONIC_NO_PAGE_SIZE_MACRO -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -std=c++17 -fexceptions -frtti $EXTRA_CXXFLAGS -I$PREFIX/include " \
        --extra-ldflags=" -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1 -Wl,--no-rosegment -Wl,--no-undefined-version -Wl,--fatal-warnings -Wl,--no-undefined -Qunused-arguments -L$SYSROOT/usr/lib/$TARGET_ARCH-linux-android/$ANDROID_API_LEVEL -L$PREFIX/lib" \
        --enable-pic \
        ${ENABLED_CONFIG} \
        ${DISABLED_CONFIG} \
        --ar="$LLVM_AR" \
        --nm="$LLVM_NM" \
        --ranlib="$LLVM_RANLIB" \
        --strip="$LLVM_STRIP" \
        ${EXTRA_CONFIG} 2>&1 | tee "$CONFIG_SUMMARY_FILE"

    # 验证 libass 是否成功启用（关键依赖检查）
    if ! (
        grep -Eq '#define[[:space:]]+CONFIG_LIBASS[[:space:]]+1' config.h 2>/dev/null || \
        grep -Eq '(^|[[:space:]])CONFIG_LIBASS[[:space:]]*=[[:space:]]*yes([[:space:]]|$)' config.mak 2>/dev/null
    ); then
        echo "Error: libass is NOT enabled. Check libass/fribidi detection and flags. See config.log for details."
        echo "Diagnostics:"
        echo "- fribidi: $(pkg-config --modversion fribidi 2>/dev/null || echo not found)"
        echo "- libass:  $(pkg-config --modversion libass 2>/dev/null || echo not found)"
        echo "- Snippet from config.h:" && grep -E 'CONFIG_(LIBASS|LIBFRIBIDI)' -n config.h 2>/dev/null || true
        echo "- Snippet from config.mak:" && grep -E 'CONFIG_(LIBASS|LIBFRIBIDI)=' -n config.mak 2>/dev/null || true
        exit 1
    fi

    # 编译并安装 FFmpeg（使用所有 CPU 核心加速）
    make clean
    make -j"$(nproc)"
    make install -j"$(nproc)"
}


##############################################################################
# 主执行逻辑
##############################################################################
echo -e "\e[1;32mCompiling FFMPEG for Android...\e[0m"

# 检查必要环境变量
if [ -z "$FFMPEG_SOURCE_DIR" ]; then
    echo "Error: FFMPEG_SOURCE_DIR is not set"
    exit 1
fi

if [ -z "$ANDROID_NDK_PATH" ]; then
    echo "Error: ANDROID_NDK_PATH is not set"
    exit 1
fi

# 设置默认编译输出目录
if [ -z "$FFMPEG_BUILD_DIR" ]; then
    FFMPEG_BUILD_DIR="$(pwd)"
    export FFMPEG_BUILD_DIR
    echo "FFMPEG_BUILD_DIR not set; defaulting to $(pwd)"
fi

# 遍历架构列表，逐架构编译依赖库 + FFmpeg
for ARCH in "${ARCH_LIST[@]}"; do
    case "$ARCH" in
        # 64位 ARM 架构（armv8a/arm64-v8a）
        "armv8-a"|"aarch64"|"arm64-v8a"|"armv8a")
            echo -e "\e[1;32m=== Building for $ARCH ===\e[0m"
            TARGET_ARCH="aarch64"
            TARGET_CPU="armv8-a"
            TARGET_ABI="aarch64"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/arm64-v8a"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-android${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CXXFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CONFIG="--enable-asm --enable-neon"
            ;;

        # 32位 ARM 架构（armv7a/armeabi-v7a）
        "armv7-a"|"armeabi-v7a"|"armv7a")
            echo -e "\e[1;32m=== Building for $ARCH ===\e[0m"
            TARGET_ARCH="arm"
            TARGET_CPU="armv7-a"
            TARGET_ABI="armv7a"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/armeabi-v7a"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-androideabi${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O2 -march=$TARGET_CPU -mfpu=neon -fomit-frame-pointer"
            EXTRA_CXXFLAGS="-O2 -march=$TARGET_CPU -mfpu=neon -fomit-frame-pointer"
            EXTRA_CONFIG="--disable-armv5te --disable-armv6 --disable-armv6t2 --enable-asm --enable-neon"
            ;;

        # 64位 x86 架构（x86-64/x86_64）
        "x86-64"|"x86_64")
            echo -e "\e[1;32m=== Building for $ARCH ===\e[0m"
            TARGET_ARCH="x86_64"
            TARGET_CPU="x86-64"
            TARGET_ABI="x86_64"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/x86_64"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-android${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CXXFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CONFIG="--enable-asm"
            ;;

        # 32位 x86 架构（x86/i686）
        "x86"|"i686")
            echo -e "\e[1;32m=== Building for $ARCH ===\e[0m"
            TARGET_ARCH="i686"
            TARGET_CPU="i686"
            TARGET_ABI="i686"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/x86"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-android${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CXXFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CONFIG="--disable-asm"
            ;;

        # 未知架构处理
        *)
            echo "Error: Unknown architecture: $ARCH"
            exit 1
            ;;
    esac

    # 按依赖顺序编译库 + FFmpeg
    buildLibdav1d "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling libdav1d for $ARCH"; exit 1; fi

    buildFreetype "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling freetype for $ARCH"; exit 1; fi

    buildHarfBuzz "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling harfbuzz for $ARCH"; exit 1; fi

    buildFriBiDi "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling fribidi for $ARCH"; exit 1; fi

    buildLibass "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling libass for $ARCH"; exit 1; fi

    configure_ffmpeg "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling ffmpeg for $ARCH"; exit 1; fi

done

echo -e "\e[1;32mFFmpeg build for all architectures completed successfully!\e[0m"