#!/bin/bash

### Describe Your Target Android Api or Architectures ###
ANDROID_API_LEVEL="25"
ARCH_LIST=("armv8a" "armv7a" "x86" "x86-64")


### Supported Architectures "armv8a" "armv7a" "x86" "x86-64"  #######

### Enable FFMPEG BUILD MODULES ####
ENABLED_CONFIG="\
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-swscale \
  --enable-swresample \
  --enable-avfilter \
  --enable-libdav1d \
  --enable-libfreetype \
  --enable-libharfbuzz \
  --enable-encoder=mpeg4 \
  --enable-encoder=aac \
  --enable-encoder=h264 \
  --enable-decoder=h264 \
  --enable-decoder=mpeg4 \
  --enable-decoder=aac \
  --enable-decoder=mp3 \
  --enable-decoder=png \
  --enable-decoder=jpeg2000 \
  --enable-decoder=jpegls \
  --enable-demuxer=* \
  --enable-muxer=mov \
  --enable-muxer=3gp \
  --enable-muxer=mp4 \
  --enable-filter=drawtext \
  --enable-filters \
  --enable-protocol=file \
  --enable-parser=* \
  --enable-bsf=* \
  --enable-shared"


### Disable FFMPEG BUILD MODULES ####
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


############ Dont Change ################
SYSROOT="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
LLVM_AR="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
LLVM_NM="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
LLVM_RANLIB="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ranlib"
LLVM_STRIP="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
export ASFLAGS="-fPIC"


buildLibdav1d(){
	TARGET_ARCH=$1
    TARGET_CPU=$2
    PREFIX=$3
    CROSS_PREFIX=$4
    EXTRA_CFLAGS=$5
    EXTRA_CXXFLAGS=$6
    EXTRA_CONFIG=$7
	CLANG="${CROSS_PREFIX}clang"
    CLANGXX="${CROSS_PREFIX}clang++"

	if [ "$TARGET_ARCH" = "i686" ]; then
	    TARGET_ARCH="x86"
	fi

	if [ ! -d "dav1d" ]; then
	    echo "Cloning libdav1d..."
	    git clone https://code.videolan.org/videolan/dav1d.git
	else
	    echo "Updating libdav1d..."
	    cd dav1d || exit 1
	    git pull
	    cd ..
	fi

	cd dav1d || exit 1
	# --- Create cross file ---
 	CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
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
 	rm -rf build
	meson setup build \
 	  --default-library=static \
	  --prefix=$PREFIX \
	  --buildtype release \
	  --cross-file=$CROSS_FILE

	ninja -C build
	ninja -C build install
}

# Build freetype for Android using meson
buildFreetype(){
	TARGET_ARCH=$1
    TARGET_CPU=$2
    PREFIX=$3
    CROSS_PREFIX=$4
    EXTRA_CFLAGS=$5
    EXTRA_CXXFLAGS=$6
    EXTRA_CONFIG=$7
	CLANG="${CROSS_PREFIX}clang"
    CLANGXX="${CROSS_PREFIX}clang++"

	if [ "$TARGET_ARCH" = "i686" ]; then
	    TARGET_ARCH="x86"
	fi

	if [ ! -d "freetype2" ]; then
	    echo "Cloning FreeType..."
	    git clone https://git.savannah.gnu.org/git/freetype/freetype2.git
	else
	    echo "Updating FreeType..."
	    cd freetype2 || exit 1
	    git pull
	    cd ..
	fi

	cd freetype2 || exit 1
	# --- Create meson cross file for freetype ---
	CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
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
	rm -rf build
	meson setup build \
	  --default-library=static \
	  --prefix=$PREFIX \
	  --buildtype release \
	  --cross-file=$CROSS_FILE \
	  -Dzlib=disabled \
	  -Dpng=disabled

	ninja -C build
	ninja -C build install

	if [ ! -f "$PREFIX/lib/pkgconfig/freetype2.pc" ]; then
      echo "Error: freetype2.pc not found in $PREFIX/lib/pkgconfig"
      exit 1
  fi
}

# Build HarfBuzz for Android (required by FFmpeg drawtext)
buildHarfBuzz(){
    TARGET_ARCH=$1
    TARGET_CPU=$2
    PREFIX=$3
    CROSS_PREFIX=$4
    EXTRA_CFLAGS=$5
    EXTRA_CXXFLAGS=$6
    EXTRA_CONFIG=$7
    CLANG="${CROSS_PREFIX}clang"
    CLANGXX="${CROSS_PREFIX}clang++"

    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    if [ ! -d "harfbuzz" ]; then
        echo "Cloning HarfBuzz..."
        git clone https://github.com/harfbuzz/harfbuzz.git
    else
        echo "Updating HarfBuzz..."
        cd harfbuzz || exit 1
        git pull
        cd ..
    fi

    cd harfbuzz || exit 1
    CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
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
    rm -rf build
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

    if [ ! -f "$PREFIX/lib/pkgconfig/harfbuzz.pc" ]; then
      echo "Error: harfbuzz.pc not found in $PREFIX/lib/pkgconfig"
      exit 1
    fi
}

configure_ffmpeg(){
   TARGET_ARCH=$1
   TARGET_CPU=$2
   PREFIX=$3
   CROSS_PREFIX=$4
   EXTRA_CFLAGS=$5
   EXTRA_CXXFLAGS=$6
   EXTRA_CONFIG=$7

   export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
   CLANG="${CROSS_PREFIX}clang"
   CLANGXX="${CROSS_PREFIX}clang++"

   # Show detected freetype/harfbuzz to help ensure drawtext can be enabled
   echo "freetype2 version: $(pkg-config --modversion freetype2 2>/dev/null || echo not found)"
   echo "harfbuzz version: $(pkg-config --modversion harfbuzz 2>/dev/null || echo not found)"

   cd "$FFMPEG_SOURCE_DIR" || exit 1
   # Capture configure output for robust verification
   CONFIG_SUMMARY_FILE="configure.summary.$TARGET_ARCH.txt"
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
   --extra-cflags="-fpic -DANDROID -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -D__BIONIC_NO_PAGE_SIZE_MACRO -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security $EXTRA_CFLAGS -I$PREFIX/include -I$PREFIX/include/freetype2 " \
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

   # Verify drawtext got enabled in configure step.
   # 1) config.h define, 2) config.mak variable, 3) presence in the multi-line Enabled filters section.
   if ! (
        grep -Eq '#define[[:space:]]+CONFIG_DRAWTEXT_FILTER[[:space:]]+1' config.h 2>/dev/null || \
        grep -Eq '(^|[[:space:]])CONFIG_DRAWTEXT_FILTER[[:space:]]*=[[:space:]]*yes([[:space:]]|$)' config.mak 2>/dev/null || \
        awk '/^Enabled filters:/{inlist=1;next} /^Enabled /{inlist=0} inlist && $0 ~ /(^|[ ,])drawtext([ ,]|$)/{found=1} END{exit !found}' "$CONFIG_SUMMARY_FILE" 2>/dev/null
      ); then
     echo "Error: drawtext filter is NOT enabled. Check freetype2/harfbuzz detection and flags. See config.log for details."
     echo "Diagnostics:"
     echo "- freetype2: $(pkg-config --modversion freetype2 2>/dev/null || echo not found)"
     echo "- harfbuzz:  $(pkg-config --modversion harfbuzz 2>/dev/null || echo not found)"
     echo "- Snippet from $CONFIG_SUMMARY_FILE:" && \
       awk 'p&&!--n; /^Enabled filters:/{p=1;n=60;print;next} p{print}' "$CONFIG_SUMMARY_FILE" 2>/dev/null | sed -n '1,80p' || true
     echo "- Snippet from config.h:" && grep -E 'CONFIG_(DRAWTEXT_FILTER|LIBFREETYPE|LIBHARFBUZZ)' -n config.h 2>/dev/null || true
     echo "- Snippet from config.mak:" && grep -E 'CONFIG_(DRAWTEXT_FILTER|LIBFREETYPE|LIBHARFBUZZ)=' -n config.mak 2>/dev/null || true
     exit 1
   fi

   make clean
   make -j"$(nproc)"  # 使用所有可用CPU核心加速编译
   make install -j"$(nproc)"
}

echo -e "\e[1;32mCompiling FFMPEG for Android...\e[0m"

# 确保FFMPEG_SOURCE_DIR已设置
if [ -z "$FFMPEG_SOURCE_DIR" ]; then
    echo "Error: FFMPEG_SOURCE_DIR is not set"
    exit 1
fi

# 确保ANDROID_NDK_PATH已设置
if [ -z "$ANDROID_NDK_PATH" ]; then
    echo "Error: ANDROID_NDK_PATH is not set"
    exit 1
fi

# Provide a safe default build directory
if [ -z "$FFMPEG_BUILD_DIR" ]; then
    FFMPEG_BUILD_DIR="$(pwd)"
    export FFMPEG_BUILD_DIR
    echo "FFMPEG_BUILD_DIR not set; defaulting to $(pwd)"
fi

for ARCH in "${ARCH_LIST[@]}"; do
    case "$ARCH" in
        "armv8-a"|"aarch64"|"arm64-v8a"|"armv8a")
            echo -e "\e[1;32m$ARCH Libraries\e[0m"
            TARGET_ARCH="aarch64"
            TARGET_CPU="armv8-a"
            TARGET_ABI="aarch64"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/arm64-v8a"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-android${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
	        EXTRA_CXXFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"

            EXTRA_CONFIG="\
					      	--enable-asm \
            		--enable-neon "
            ;;
        "armv7-a"|"armeabi-v7a"|"armv7a")
            echo -e "\e[1;32m$ARCH Libraries\e[0m"
            TARGET_ARCH="arm"
            TARGET_CPU="armv7-a"
            TARGET_ABI="armv7a"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/armeabi-v7a"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-androideabi${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O2 -march=$TARGET_CPU -mfpu=neon -fomit-frame-pointer"
	        EXTRA_CXXFLAGS="-O2 -march=$TARGET_CPU -mfpu=neon -fomit-frame-pointer"

            EXTRA_CONFIG="\
            		--disable-armv5te \
            		--disable-armv6 \
            		--disable-armv6t2 \
			      	--enable-asm \
            		--enable-neon "
            ;;
        "x86-64"|"x86_64")
            echo -e "\e[1;32m$ARCH Libraries\e[0m"
            TARGET_ARCH="x86_64"
            TARGET_CPU="x86-64"
            TARGET_ABI="x86_64"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/x86_64"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-android${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
	        EXTRA_CXXFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"

            EXTRA_CONFIG="\
					      	--enable-asm "
            ;;
        "x86"|"i686")
            echo -e "\e[1;32m$ARCH Libraries\e[0m"
            TARGET_ARCH="i686"
            TARGET_CPU="i686"
            TARGET_ABI="i686"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/x86"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-android${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
	        EXTRA_CXXFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CONFIG="\
            			 --disable-asm "
            ;;
           * )
            echo "Unknown architecture: $ARCH"
            exit 1
            ;;
    esac
	buildLibdav1d "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
	if [ $? -ne 0 ]; then
		echo "Error compiling libdav1d for $ARCH"
  		exit 1
	fi
	# Build FreeType so ffmpeg's libfreetype and drawtext can link
	buildFreetype "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
	if [ $? -ne 0 ]; then
		echo "Error compiling freetype for $ARCH"
  	 exit 1
	fi
    # Build HarfBuzz so drawtext can be enabled
    buildHarfBuzz "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then
        echo "Error compiling harfbuzz for $ARCH"
        exit 1
    fi
    configure_ffmpeg "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
	if [ $? -ne 0 ]; then
		echo "Error compiling ffmpeg for $ARCH"
  		exit 1
	fi

done
