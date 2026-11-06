#!/bin/bash
# Fork test only: push the built files to the running emulator, run each test, FileCheck the output.
# usage: run-tests.sh <out dir>
set -uo pipefail
OUT=$1
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
D=/data/local/tmp/bt
adb shell getprop ro.build.version.sdk
adb shell getprop ro.product.cpu.abi
adb shell mkdir -p $D
adb push $OUT/push/. $D/ > /dev/null
adb shell chmod +x "$D/*.exe"
fail=0
for t in SimpleBacktrace BacktraceWithLimit BacktraceWithLimitAndTop SymbolicatedBacktrace SimpleAsyncBacktrace; do
  adb shell "cd $D && LD_LIBRARY_PATH=$D timeout 120 ./$t.exe" > $OUT/$t.out 2>&1
  if filecheck $ROOT/test/Backtracing/$t.swift < $OUT/$t.out > $OUT/$t.fc 2>&1; then
    echo "$t: PASS"
  else
    echo "$t: FAIL"; head -12 $OUT/$t.fc; echo "--- output:"; head -12 $OUT/$t.out
    case $t in SimpleBacktrace|BacktraceWithLimit|BacktraceWithLimitAndTop) fail=1 ;; esac
  fi
done
exit $fail
