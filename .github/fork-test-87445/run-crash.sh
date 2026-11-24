#!/bin/bash
# Runs the crash program on the emulator, as the shell user, for three kinds of
# crash, with and without SWIFT_BACKTRACE, and checks that the Swift report
# appears only with it and that debuggerd's report is the same either way.
OUT=$1
R=$OUT/results; mkdir -p $R
D=/data/local/tmp/t
adb shell mkdir -p $D
adb push $OUT/push/. $D/ >/dev/null
adb shell chmod 755 $D/crash $D/swift-backtrace
echo "user: $(adb shell id -un)  api: $(adb shell getprop ro.build.version.sdk)"
fail=0
for mode in fatal segv abort; do
  for e in off on; do
    N=$mode-$e
    ENV="LD_LIBRARY_PATH=$D"
    [ $e = on ] && ENV="$ENV SWIFT_BACKTRACE=enable=yes,color=no,swift-backtrace=$D/swift-backtrace"
    adb logcat -c
    adb shell "cd $D && $ENV ./crash $mode; echo EXIT=\$?" > $R/$N.out 2>&1
    sleep 5
    adb logcat -d -b crash > $R/$N.crashlog
    grep -E 'signal [0-9]+ \(|Abort message| #0[0-4] pc' $R/$N.crashlog | sed -E 's/^.*(signal|Abort|#)/\1/; s/fault addr.*//; s/ in tid.*//' > $R/$N.debuggerd
    swift=$(grep -c 'Program crashed' $R/$N.out)
    dbg=$(grep -c ' #00 pc' $R/$N.crashlog)
    echo "$N $(grep -o 'EXIT=[0-9]*' $R/$N.out) swiftReport=$swift debuggerdReport=$dbg"
    if [ $e = on ] && [ $swift -eq 0 ]; then echo "FAIL: $N has no Swift report"; fail=1; fi
    if [ $e = off ] && [ $swift -ne 0 ]; then echo "FAIL: $N has a Swift report"; fail=1; fi
    if [ $dbg -eq 0 ]; then echo "FAIL: $N has no debuggerd report"; fail=1; fi
  done
  if diff $R/$mode-off.debuggerd $R/$mode-on.debuggerd > /dev/null; then
    echo "$mode: debuggerd report is the same with and without SWIFT_BACKTRACE"
  else
    echo "FAIL: $mode: debuggerd report differs"; diff $R/$mode-off.debuggerd $R/$mode-on.debuggerd; fail=1
  fi
done
echo "--- Swift report for fatal-on:"; cat $R/fatal-on.out
exit $fail
