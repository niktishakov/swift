#!/bin/bash
# Fork test only: build libswiftRuntime.so for Android from this checkout with the
# flags from stdlib/public/RuntimeModule/CMakeLists.txt, then build the backtrace tests.
# usage: build-runtime-android.sh <arch> <api> <out dir>
set -euo pipefail
ARCH=$1; API=$2; OUT=$3
TRIPLE=$ARCH-unknown-linux-android$API
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
R=$ROOT/stdlib/public/RuntimeModule
SDK=$( (find ~/.swiftpm ~/.config/swiftpm -maxdepth 3 -name swift-android -type d 2>/dev/null || true) | head -1)
[ -n "$SDK" ] || { echo 'Android Swift SDK not found'; exit 1; }
NDKBIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin
NDKCLANG=$(ls -d $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/* | head -1)
RES=$SDK/swift-resources/usr/lib/swift-$ARCH
mkdir -p $OUT/gen/swift/Runtime
printf '#pragma once\n#define SWIFT_BNI_OS_BUILD 0\n#define SWIFT_BNI_XCODE_BUILD 0\n' > $OUT/gen/swift/Runtime/CMakeConfig.h
echo "SDK=$SDK NDKCLANG=$NDKCLANG"

CFLAGS=(--target=$TRIPLE -fPIC -O1 -I$R -I$ROOT/include -I$OUT/gen)
$NDKBIN/clang -c $R/get-cpu-context.S "${CFLAGS[@]}" -o $OUT/get-cpu-context.o
$NDKBIN/clang++ -std=c++17 -c $R/SafeReadMemory.cpp "${CFLAGS[@]}" -o $OUT/SafeReadMemory.o

SWIFTFLAGS=(-target $TRIPLE -sdk $SDK/ndk-sysroot -resource-dir $RES
  -Xclang-linker -fuse-ld=lld -Xclang-linker -resource-dir -Xclang-linker $NDKCLANG
  -cxx-interoperability-mode=default -Xcc -I$ROOT/include -Xcc -I$OUT/gen -Xcc -I$R/modules
  -disable-upcoming-feature MemberImportVisibility)

srcs=($(sed -n '/^set(backtracing_sources/,/^)/p' $R/CMakeLists.txt | grep '\.swift' | sed "s|^ *|$R/|") $R/Mangling.swift)
swiftc "${SWIFTFLAGS[@]}" -O -parse-stdlib -module-name Runtime -swift-version 5 \
  -Xfrontend -experimental-spi-only-imports -enable-experimental-feature Reparenting \
  -DSWIFT_ASM_AVAILABLE -Xfrontend -define-availability -Xfrontend "BacktracingDT 6.2:macOS 26.0" \
  -enable-library-evolution -emit-library -emit-module -emit-module-path $OUT/Runtime.swiftmodule \
  -o $OUT/libswiftRuntime.so -Xlinker -soname=libswiftRuntime.so \
  "${srcs[@]}" $OUT/get-cpu-context.o $OUT/SafeReadMemory.o -lc++_shared
echo "built $OUT/libswiftRuntime.so"

# Tests: build each like its RUN line.
for t in SimpleBacktrace BacktraceWithLimit BacktraceWithLimitAndTop SymbolicatedBacktrace SimpleAsyncBacktrace; do
  src=$ROOT/test/Backtracing/$t.swift
  flags=($(grep -m1 '%target-build-swift' $src | sed -E 's/.*%target-build-swift //; s/ -o .*//; s/%s//'))
  swiftc "${SWIFTFLAGS[@]}" -I $OUT -L $OUT -lswiftRuntime "${flags[@]}" $src -o $OUT/$t.exe
  echo "built $t"
done

# Runtime libraries to push.
mkdir -p $OUT/push
cp $RES/android/*.so $OUT/push/
cp $SDK/ndk-sysroot/usr/lib/$ARCH-linux-android/libc++_shared.so $OUT/push/ 2>/dev/null \
  || cp $(find $ANDROID_NDK_HOME -path "*$ARCH-linux-android/libc++_shared.so" | head -1) $OUT/push/
cp $OUT/libswiftRuntime.so $OUT/*.exe $OUT/push/
ls $OUT/push | wc -l
