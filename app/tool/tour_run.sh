#!/bin/bash
# Runs the screenshot tour on a small screen with normal and large text. Saves shots/<scale>_<name>.jpg
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
  adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 >/dev/null
  seen=""
  for i in $(seq 1 240); do
    sleep 1
    lines=$(adb logcat -d -s flutter:I | grep -o "ADDA_TOUR [a-z]* *[a-z0-9_]*" || true)
    while read -r l; do
      [ -z "$l" ] && continue
      case "$seen" in *"|$l|"*) continue;; esac
      seen="$seen|$l|"
      name=$(echo "$l" | awk '{print $3}')
      if [ "$(echo "$l" | awk '{print $2}')" = "shot" ]; then
        adb exec-out screencap -p > /tmp/s.png && convert /tmp/s.png -resize 50% -quality 72 "shots/${scale}_${name}.jpg"
        echo "shot $scale $name"
      fi
    done <<< "$lines"
    case "$seen" in *"ADDA_TOUR done"*) break;; esac
    adb shell pidof $pkg >/dev/null || { echo "APP NOT RUNNING at ${i}s ($scale)"; adb logcat -d | grep -E "FATAL|AndroidRuntime: |E/flutter" | tail -30; break; }
  done
  adb logcat -d | grep -E "E/flutter|ADDA error|Another exception|RenderFlex overflowed|overflowed by" | head -60 > "shots/${scale}_errors.txt"
  echo "== errors ($scale):"; cat "shots/${scale}_errors.txt" | cut -c1-220
  adb shell am force-stop $pkg
done
exit 0
