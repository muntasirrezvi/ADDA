#!/bin/bash
# Runs the screenshot tour on a small screen with normal and large text. Saves shots/<scale>_<name>.png
apk=$1; pkg=app.adda.voice
mkdir -p shots
adb install -r "$apk" >/dev/null
adb shell wm size 720x1280
adb shell wm density 320
for scale in 1.0 1.3; do
  adb shell settings put system font_scale $scale
  adb shell pm clear $pkg >/dev/null
  adb shell pm grant $pkg android.permission.POST_NOTIFICATIONS 2>/dev/null
  adb logcat -c
  adb logcat -s flutter:I > /tmp/flog.txt 2>/dev/null &
  lp=$!
  adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 >/dev/null
  done_shots=0
  for i in $(seq 1 170); do
    sleep 1
    n=$(grep -c "ADDA_TOUR shot" /tmp/flog.txt)
    while [ "$done_shots" -lt "$n" ]; do
      done_shots=$((done_shots + 1))
      name=$(grep "ADDA_TOUR shot" /tmp/flog.txt | sed -n "${done_shots}p" | awk '{print $NF}')
      adb exec-out screencap -p > "shots/${scale}_${name}.png"
      echo "shot $scale $name"
    done
    grep -q "ADDA_TOUR done" /tmp/flog.txt && break
    if ! adb shell pidof $pkg >/dev/null; then echo "APP NOT RUNNING at ${i}s ($scale)"; break; fi
  done
  kill $lp 2>/dev/null
  adb logcat -d | grep -E "E/flutter|ADDA error|Another exception" | head -40 > "shots/${scale}_errors.txt"
  echo "== errors ($scale):"; cut -c1-220 "shots/${scale}_errors.txt"
  adb shell am force-stop $pkg
done
exit 0
