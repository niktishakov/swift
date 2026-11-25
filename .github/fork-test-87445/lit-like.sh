#!/bin/bash
# Fork test only: run the RUN lines of some test/Backtracing tests the way lit
# does for Android (adb_test_runner.py, ANDROID_CHILD_ env), with real FileCheck.
set -u
REPO=$PWD
SDKROOT=$( (find ~/.swiftpm ~/.config/swiftpm -maxdepth 3 -name '*android*.artifactbundle' -type d 2>/dev/null || true) | head -1)/swift-android
RES=$SDKROOT/swift-resources/usr/lib/swift-x86_64
SYS=$SDKROOT/ndk-sysroot
NDKBIN=$(find $ANDROID_NDK_HOME/toolchains/llvm/prebuilt -maxdepth 2 -name bin -type d | head -1)
FC=$(ls /usr/lib/llvm-*/bin/FileCheck | tail -1)
BUILD="swiftc -target x86_64-unknown-linux-android28 -sdk $SYS -resource-dir $RES -tools-directory $NDKBIN -Xclang-linker -fuse-ld=lld"
# What test/CMakeLists.txt pushes before the tests: the stdlib and swift-backtrace.
adb push $RES/android/. /data/local/tmp/ > /dev/null
LIBCXX=$(find -L $SYS $ANDROID_NDK_HOME/toolchains -path '*x86_64-linux-android/libc++_shared.so' 2>/dev/null | head -1); echo "libc++: $LIBCXX"; test -n "$LIBCXX" || exit 1
adb push $LIBCXX /data/local/tmp/ > /dev/null
python3 utils/android/adb_push_built_products.py --destination /data/local/tmp $SDKROOT/swift-resources/usr/libexec/swift/android/swift-backtrace
adb shell ls -la /data/local/tmp/swift-backtrace /data/local/tmp/libswiftCore.so
fail=0
for t in "$@"; do
  T=$(mktemp -d); S=$REPO/test/Backtracing; f=$S/$t
  status=PASS
  while IFS= read -r line; do
    cmd=${line#*RUN: }
    cmd=$(printf '%s' "$cmd" | sed -E "s#%empty-directory\(([^)]*)\)#mkdir_clean \1#g; s#%target-build-swift#$BUILD#g; s#%swift-debug-flags#-g#g; s#%target-codesign#true#g; s#%target-run#python3 $REPO/utils/android/adb_test_runner.py#g; s#%env-#ANDROID_CHILD_#g; s#%FileCheck#$FC#g; s#%S#$S#g; s#%s#$f#g; s#%t#$T#g")
    out=$(bash -c "mkdir_clean() { rm -rf \"\$1\"; mkdir -p \"\$1\"; }; $cmd" < /dev/null 2>&1); rc=$?
    echo "  [$rc] ${cmd:0:110}"
    if [ $rc -ne 0 ]; then status=FAIL; echo "---- $t: failed: $cmd"; echo "$out" | head -60; break; fi
  done < <(grep -E '^// RUN:' $f)
  echo "$status: $t"; [ $status = FAIL ] && fail=1
  for o in $T/*.out; do [ -f "$o" ] && { echo "---- $(basename $o):"; head -25 "$o"; }; done
done
exit $fail
