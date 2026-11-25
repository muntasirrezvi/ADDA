"""Applies Adda's Android and iOS settings to the files `flutter create` generates. Safe to run again."""
import pathlib, re

APP_ID = "app.adda.voice"
root = pathlib.Path(__file__).resolve().parent.parent

# ---------- Android: permissions, name, links ----------
man = root / "android/app/src/main/AndroidManifest.xml"
s = man.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.RECORD_AUDIO",
    "android.permission.CAMERA",
    "android.permission.MODIFY_AUDIO_SETTINGS",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.ACCESS_WIFI_STATE",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.WAKE_LOCK",
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.READ_MEDIA_VIDEO",
    "com.android.vending.BILLING",
]
add = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in s)
if add:
    s = s.replace("<application", add + "    <application", 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Adda"', s, count=1)
intents = (
    '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>\n'
    '        <intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="mailto"/></intent>\n'
)
if 'android:scheme="mailto"' not in s:
    if "<queries>" in s:
        s = s.replace("<queries>", "<queries>\n" + intents, 1)
    else:
        s = s.replace("</manifest>", "    <queries>\n" + intents + "    </queries>\n</manifest>")
man.write_text(s)

# ---------- Android: app id, minimum Android version ----------
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    g = root / name
    if not g.exists():
        continue
    t = g.read_text()
    t = re.sub(r'applicationId\s*=?\s*"[^"]+"', f'applicationId = "{APP_ID}"' if name.endswith(".kts") else f'applicationId "{APP_ID}"', t)
    t = re.sub(r'minSdk(Version)?\s*=?\s*(flutter\.minSdkVersion|\d+)', "minSdk = 24" if name.endswith(".kts") else "minSdkVersion 24", t)
    g.write_text(t)

# keep Agora's native classes when the release build shrinks code
(root / "android/app/proguard-rules.pro").write_text(
    "-keep class io.agora.** { *; }\n-dontwarn io.agora.**\n-keep class com.google.android.play.core.** { *; }\n-dontwarn com.google.android.play.core.**\n"
)

# ---------- iOS: permission texts ----------
plist = root / "ios/Runner/Info.plist"
if plist.exists():
    p = plist.read_text()
    keys = {
        "NSMicrophoneUsageDescription": "Adda uses the microphone so you can talk in voice rooms and calls.",
        "NSCameraUsageDescription": "Adda uses the camera for video calls and recording reels.",
        "NSPhotoLibraryUsageDescription": "Adda uses your photos for your profile picture, room covers and payment screenshots.",
    }
    extra = "".join(f"\t<key>{k}</key>\n\t<string>{v}</string>\n" for k, v in keys.items() if k not in p)
    if extra:
        p = p.replace("<dict>", "<dict>\n" + extra, 1)
    p = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1Adda\2", p)
    plist.write_text(p)

# permission_handler on iOS only includes the permissions switched on here
podfile = root / "ios/Podfile"
if podfile.exists():
    pf = podfile.read_text()
    if "PERMISSION_MICROPHONE" not in pf:
        pf = pf.replace(
            "flutter_additional_ios_build_settings(target)",
            "flutter_additional_ios_build_settings(target)\n"
            "    target.build_configurations.each do |config|\n"
            "      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)', 'PERMISSION_MICROPHONE=1', 'PERMISSION_CAMERA=1', 'PERMISSION_PHOTOS=1']\n"
            "    end",
        )
        podfile.write_text(pf)
print("patched", man.relative_to(root))
