#!/bin/bash
# Builds the crash program for Android x86_64 with the SDK built in this run,
# and collects what the emulator needs.
set -euxo pipefail
OUT=$1
mkdir -p $OUT/pkg/Sources/crash $OUT/push
cp "$(dirname $0)/crash.swift" $OUT/pkg/Sources/crash/main.swift
cat > $OUT/pkg/Package.swift <<'P'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "crash", targets: [.executableTarget(name: "crash")])
P
SDKID=$(swift sdk list | grep -i android | head -1)
cd $OUT/pkg && swift build --swift-sdk x86_64-unknown-linux-android28 -c debug
cp .build/debug/crash $OUT/push/
BUNDLE=$(find ~/.swiftpm ~/.config/swiftpm -maxdepth 3 -name '*android*.artifactbundle' -type d 2>/dev/null | head -1)
echo "bundle: $BUNDLE"
find $BUNDLE -path '*swift-x86_64/android/*.so' -exec cp {} $OUT/push/ \;
find $ANDROID_NDK_HOME -path '*x86_64-linux-android/libc++_shared.so' | head -1 | xargs -I{} cp {} $OUT/push/
BT=$(find $BUNDLE -name swift-backtrace -type f | head -1)
echo "swift-backtrace in the SDK: ${BT:-none}"
test -n "$BT"
cp $BT $OUT/push/
ls -la $OUT/push
