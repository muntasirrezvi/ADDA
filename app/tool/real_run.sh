#!/bin/bash
# Installs the published APK, signs in through the login screen, records what happens. Args: apk email password
apk=$1; email=$2; pass=$3; tag=$(basename "$apk" .apk)
mkdir -p out
adb install -r "$apk" || { echo "$tag: INSTALL FAILED"; exit 0; }
pkg=app.adda.voice
adb shell pm grant $pkg android.permission.POST_NOTIFICATIONS 2>/dev/null
adb logcat -c
adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 12
echo "== $tag login screen:"; python3 app/tool/ui.py dump | head -20
python3 app/tool/ui.py field 0
adb shell input text "$email"; sleep 1
python3 app/tool/ui.py field 1
adb shell input text "$pass"; sleep 1
adb shell input keyevent 66    # Enter on the password field signs in
sleep 2; adb exec-out screencap -p > out/after_enter.png
for t in 5 15 30 50; do
  sleep $((t - ${prev:-0})); prev=$t
  adb exec-out screencap -p > out/${tag}_${t}s.png
  if adb shell pidof $pkg >/dev/null; then echo "$tag ${t}s after sign in: running"; else echo "$tag ${t}s after sign in: CRASHED"; fi
done
echo "== $tag screen now:"; python3 app/tool/ui.py dump | head -30
adb logcat -d > out/${tag}_logcat.txt
echo "== $tag crash buffer:"; adb logcat -d -b crash | tail -80
echo "== $tag important:"; grep -E "flutter|ADDA|FATAL|AndroidRuntime: |DEBUG  |libc  |shorebird|updater" out/${tag}_logcat.txt | grep -v "Telephony\|GmsCore" | tail -120
adb uninstall $pkg >/dev/null
exit 0
