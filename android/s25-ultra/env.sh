# Pinned toolchain for building MLC Chat for the Galaxy S25 Ultra (SM-S938U).
# Sourced by every script in this directory. Change versions here only.
#
# Layers:
#   compiler  : TVM + mlc_llm built from this repo's own source (3rdparty/tvm
#               submodule), so the model libraries and the runtime packed into
#               the APK come from the same commit. Prebuilt nightly wheels were
#               rejected: as of Oct 2026, mlc-llm-nightly 0.26.dev6 calls
#               tirx.is_buffer_var, which mlc-ai-nightly 0.26.dev246 lacks.
#   android   : SDK platform + build-tools + NDK. NDK r28+ links .so files with
#               16 KB ELF segment alignment by default, required by Google Play
#               for targetSdk 35+ and by 16 KB page-size devices.
#   app       : compileSdk/targetSdk 37 (Android 17, what the S25 Ultra runs),
#               AGP 9.4.1, Kotlin 2.4.21, Gradle 9.8.2 (latest stable, Oct 2026).

_S25_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MLC_LLM_SOURCE_DIR="$(cd "$_S25_DIR/../.." && pwd)"
export TVM_SOURCE_DIR="$MLC_LLM_SOURCE_DIR/3rdparty/tvm"

# Everything this toolchain downloads or builds lives under one directory so
# it can be deleted in one step. Override with S25_HOME=/path.
export S25_HOME="${S25_HOME:-$HOME/.mlc-s25}"
export S25_VENV="$S25_HOME/venv"
export S25_PYTHON="${S25_PYTHON:-python3.12}"

# Android toolchain (versions verified by a full build of this branch).
export ANDROID_HOME="${ANDROID_HOME:-$S25_HOME/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
# cmdline-tools 23.0. SHA-1 e025545c... matches Google's repository2-3.xml.
export S25_CMDLINE_TOOLS_ZIP="commandlinetools-linux-16111833_latest.zip"
export S25_CMDLINE_TOOLS_SHA256="0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8"
export S25_PLATFORM="platforms;android-37.0"
export S25_BUILD_TOOLS="build-tools;37.0.0"
export S25_NDK_VERSION="30.0.16248370"   # r30 stable
export ANDROID_NDK="$ANDROID_HOME/ndk/$S25_NDK_VERSION"
export TVM_NDK_CC="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"

# Device: Snapdragon 8 Elite for Galaxy, Adreno 830, OpenCL.
export S25_MLC_DEVICE="android:adreno"

export PATH="$S25_VENV/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/.cargo/bin:$PATH"
