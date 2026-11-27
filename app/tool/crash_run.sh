#!/bin/bash
# Installs test.apk, opens it, and saves logs + screenshots to out/
mkdir -p out
adb install -r test.apk
pkg=$(aapt dump badging test.apk 2>/dev/null | sed -n "s/package: name='\([^']*\)'.*/\1/p")
[ -z "$pkg" ] && pkg=$(adb shell pm list packages | grep -i adda | head -1 | cut -d: -f2 | tr -d '\r')
echo "package: $pkg" | tee out/info.txt
adb logcat -c
adb shell pm grant "$pkg" android.permission.POST_NOTIFICATIONS 2>/dev/null
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1
for t in 10 25 45; do
  sleep $((t - ${prev:-0})); prev=$t
  adb exec-out screencap -p > out/screen_${t}s.png
  adb shell pidof "$pkg" > /dev/null && echo "${t}s: running" >> out/info.txt || echo "${t}s: NOT RUNNING (crashed)" >> out/info.txt
done
adb logcat -d > out/logcat_full.txt
grep -E "flutter|ADDA|AndroidRuntime|FATAL|DEBUG|crash|Exception" out/logcat_full.txt > out/logcat_important.txt
cat out/info.txt
tail -n 150 out/logcat_important.txt
exit 0
