# Compile FFMPEG shared (.so) or static (.a) files for android 

## OpenHarmony / HarmonyOS

This repo now also includes a `harmony.sh` build script for the HarmonyOS native SDK.

Required environment variables:

```bash
export FFMPEG_SOURCE_DIR=/path/to/ffmpeg
export OHOS_NATIVE_SDK_PATH=/path/to/Harmony/sdk/12/native
export FFMPEG_BUILD_DIR=/path/to/output
```

If `OHOS_NATIVE_SDK_PATH` is not set, the script will try to auto-detect it from `OHOS_SDK_NATIVE` or `DEVECO_SDK_HOME`.

Run:

```bash
bash harmony.sh
```

Or run it from PowerShell on Windows:

```powershell
.\run-harmony.ps1 -FfmpegSourceDir D:\path\to\ffmpeg
```

Optional parameters:

```powershell
.\run-harmony.ps1 `
  -FfmpegSourceDir D:\path\to\ffmpeg `
  -OhosNativeSdkPath D:\Harmony\sdk\12\native `
  -BuildDir D:\Test\ffmpegHarmony\build-ohos `
  -BashExe D:\Git\Git\bin\bash.exe
```

The current default target is `arm64-v8a`, and the output will be placed under `build-ohos/arm64-v8a` when `FFMPEG_BUILD_DIR` is not provided.

## For Step By Step tutorial Read this Article ([Compile FFMPEG For Android](https://umirtech.com/how-to-compile-build-ffmpeg-for-android-and-use-it-in-android-studio/))


## How to add it to Your Android Studio Project -:
1. Create jniLibs folder inside /main folder example  ``\<Your Project Directory>\<Your Project>\src\main\jniLibs``
2. Copy and paste these files inside jniLibs folder.
3. And after that add this in Your cmakeList.txt file

```

set(IMPORT_DIR ${CMAKE_SOURCE_DIR}/../jniLibs)

# FFmpeg include file
set(FFMPEG_INCLUDE_DIR ${IMPORT_DIR}/${ANDROID_ABI}/include)
set(FFMPEG_LIB_DIR ${IMPORT_DIR}/${ANDROID_ABI}/lib)

include_directories(${FFMPEG_INCLUDE_DIR})
# Codec library
add_library(
        avcodec
        SHARED
        IMPORTED
)
set_target_properties(
        avcodec
        PROPERTIES IMPORTED_LOCATION
        ${FFMPEG_LIB_DIR}/libavcodec.so
)
# The filter library is temporarily out of use
add_library(
        avfilter
        SHARED
        IMPORTED
)
set_target_properties(
        avfilter
        PROPERTIES IMPORTED_LOCATION
        ${FFMPEG_LIB_DIR}/libavfilter.so
)

# File format libraries are required for most operations
add_library(
        avformat
        SHARED
        IMPORTED
)

set_target_properties(
        avformat
        PROPERTIES IMPORTED_LOCATION
        ${FFMPEG_LIB_DIR}/libavformat.so
)

# Tool library
add_library(
        avutil
        SHARED
        IMPORTED
)
set_target_properties(
        avutil
        PROPERTIES IMPORTED_LOCATION
        ${FFMPEG_LIB_DIR}/libavutil.so
)

# The resampling library is mainly used for audio conversion.
add_library(
        swresample
        SHARED
        IMPORTED
)
set_target_properties(
        swresample
        PROPERTIES IMPORTED_LOCATION
        ${FFMPEG_LIB_DIR}/libswresample.so
)

# Video format conversion library is mainly used for video conversion.
add_library(
        swscale
        SHARED
        IMPORTED
)
set_target_properties(
        swscale
        PROPERTIES IMPORTED_LOCATION
        ${FFMPEG_LIB_DIR}/libswscale.so
)


# The main android library, native window, requires this library
target_link_libraries(
        <Your-Native-Library>
        ${log-lib}
        android
        avcodec
        avfilter
        avformat
        avutil
        swresample
        swscale
)
```
4. Add this in your Module build.gradle file
```
defaultConfig {
        //............//
        ndk.abiFilters  'armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'
        externalNativeBuild {
            cmake {
                cppFlags "-std=c++17 -fexceptions -frtti"
                arguments "-DANDROID_STL=c++_shared"
            }
        }

    }
```
## These Precompiled Shared FFmpeg Binaries is Non GPL Version You can configure and compile it by your self forking this repo
