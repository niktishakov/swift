#!/bin/bash
# Builds Runtimes/Core, Overlay, Supplemental/Runtime and Supplemental/StackWalker
# for Android x86_64 with the CMake settings that utils/build.ps1 uses for
# Android (Build-CMakeProject, Build-SDK), so the build.ps1 path is exercised
# without Windows. Differences: Linux host, the NDK's clang for C and C++
# (build.ps1 builds compiler-rt for its own clang), Core without Concurrency (that
# needs a dispatch build), StackWalker is not built by build.ps1 for Android.
set -euxo pipefail
NDK=$1; OUT=$2
ROOT=$PWD
TC=$(dirname $(which swiftc))
PRE=$NDK/toolchains/llvm/prebuilt/linux-x86_64
SYS=$PRE/sysroot
CLANGV=$(ls $PRE/lib/clang | head -1)
T=x86_64-unknown-linux-android28
pip install --user -q cmake==4.4.1 || pip install --user -q 'cmake>=4,<4.5'
export PATH=$HOME/.local/bin:$PATH
cmake --version
(cd Runtimes && cmake -P Resync.cmake)
LF="-Xlinker --build-id=sha1 -Xlinker --no-rosegment -Xlinker --no-undefined-version -Xlinker --fatal-warnings -Xlinker --gc-sections -Xlinker --no-undefined"
COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_SYSTEM_NAME=Android -DCMAKE_ANDROID_API=28 -DCMAKE_ANDROID_ARCH_ABI=x86_64
  -DCMAKE_ANDROID_NDK=$NDK -DCMAKE_SYSROOT=$SYS
  -DCMAKE_C_COMPILER=$PRE/bin/clang -DCMAKE_CXX_COMPILER=$PRE/bin/clang++
  -DCMAKE_C_COMPILER_TARGET=$T -DCMAKE_CXX_COMPILER_TARGET=$T
  -DCMAKE_Swift_COMPILER=$TC/swiftc -DCMAKE_Swift_COMPILER_TARGET=$T -DCMAKE_Swift_COMPILER_ID=Apple -DCMAKE_Swift_COMPILER_WORKS=YES
  "-DCMAKE_Swift_FLAGS=-gnone -use-ld=lld -Xclang-linker -target -Xclang-linker $T -Xclang-linker --sysroot -Xclang-linker $SYS -Xclang-linker -resource-dir -Xclang-linker $PRE/lib/clang/$CLANGV"
  "-DCMAKE_SHARED_LINKER_FLAGS=$LF" "-DCMAKE_EXE_LINKER_FLAGS=$LF -Xlinker --gc-sections" "-DCMAKE_MODULE_LINKER_FLAGS=$LF"
  -DSWIFT_ANDROID_LD_PATH=$PRE/bin/ld.lld -DCMAKE_PROJECT_INCLUDE=$ROOT/utils/android-overrides.cmake
  -DSWIFT_ANDROID_NDK_PATH=$NDK -DCMAKE_EXECUTABLE_FORMAT=ELF -DCMAKE_POLICY_DEFAULT_CMP0181=NEW -DCMAKE_POLICY_DEFAULT_CMP0214=NEW -DCMAKE_POLICY_DEFAULT_CMP0195=NEW
  -DBUILD_SHARED_LIBS=YES -DCMAKE_STATIC_LIBRARY_PREFIX_Swift=lib -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=YES
  -DCMAKE_INSTALL_PREFIX=$OUT/install)
cmake "${COMMON[@]}" -S Runtimes/Core -B $OUT/core -DCMAKE_NINJA_FORCE_RESPONSE_FILE=YES \
  -DSwiftCore_ENABLE_ENVIRONMENT=YES -DSwiftCore_ENABLE_BACKTRACING=YES -DSwiftCore_ENABLE_CONCURRENCY=NO \
  -DSwiftCore_ENABLE_REMOTE_MIRROR=YES -DSwiftCore_ENABLE_LIBRARY_EVOLUTION=NO
ninja -C $OUT/core
cmake "${COMMON[@]}" -S Runtimes/Overlay -B $OUT/overlay -DSwiftCore_DIR=$OUT/core/cmake/SwiftCore \
  -DSwiftOverlay_ENABLE_CXX_INTEROP=YES -DSwiftOverlay_ENABLE_LIBRARY_EVOLUTION=NO
ninja -C $OUT/overlay
cmake "${COMMON[@]}" -S Runtimes/Supplemental/Runtime -B $OUT/runtime -DSwiftCore_DIR=$OUT/core/cmake/SwiftCore \
  -DSwiftOverlay_DIR=$OUT/overlay/cmake/SwiftOverlay -DSwiftCxxOverlay_DIR=$OUT/overlay/Cxx/cmake/SwiftCxxOverlay \
  -DSwiftRuntime_ENABLE_LIBRARY_EVOLUTION=NO -DSwiftRuntime_ENABLE_BACKTRACING=YES
ninja -C $OUT/runtime
# What build.ps1 installs into the SDK: the dynamic and the static Runtime module, and Synchronization to compare.
cmake --install $OUT/runtime --prefix $OUT/inst-dynamic
cmake "${COMMON[@]}" -S Runtimes/Supplemental/Runtime -B $OUT/runtime-static -DSwiftCore_DIR=$OUT/core/cmake/SwiftCore \
  -DSwiftOverlay_DIR=$OUT/overlay/cmake/SwiftOverlay -DSwiftCxxOverlay_DIR=$OUT/overlay/Cxx/cmake/SwiftCxxOverlay \
  -DSwiftRuntime_ENABLE_LIBRARY_EVOLUTION=NO -DSwiftRuntime_ENABLE_BACKTRACING=YES -DBUILD_SHARED_LIBS=NO
ninja -C $OUT/runtime-static
cmake --install $OUT/runtime-static --prefix $OUT/inst-static
cmake "${COMMON[@]}" -S Runtimes/Supplemental/Synchronization -B $OUT/sync -DSwiftCore_DIR=$OUT/core/cmake/SwiftCore \
  -DSwiftOverlay_DIR=$OUT/overlay/cmake/SwiftOverlay -DSwiftSynchronization_ENABLE_LIBRARY_EVOLUTION=NO
ninja -C $OUT/sync && cmake --install $OUT/sync --prefix $OUT/inst-dynamic
echo "=== installed Runtime and Synchronization files"
(cd $OUT && find inst-dynamic inst-static -type f \( -path '*Runtime*' -o -path '*Synchronization*' \) -not -path '*/cmake/*' | sort)
cmake "${COMMON[@]}" -S Runtimes/Supplemental/StackWalker -B $OUT/stackwalker -DSwiftCore_DIR=$OUT/core/cmake/SwiftCore \
  -DSwiftOverlay_DIR=$OUT/overlay/cmake/SwiftOverlay -DSwiftCxxOverlay_DIR=$OUT/overlay/Cxx/cmake/SwiftCxxOverlay \
  -DSwiftRuntime_DIR=$OUT/runtime/cmake/SwiftRuntime "-DCMAKE_Swift_FLAGS=-gnone -use-ld=lld -Xclang-linker -target -Xclang-linker $T -Xclang-linker --sysroot -Xclang-linker $SYS -Xclang-linker -resource-dir -Xclang-linker $PRE/lib/clang/$CLANGV"
ninja -C $OUT/stackwalker
find $OUT -name 'libswiftRuntime.so' -o -name 'swift-backtrace' -type f | xargs file
