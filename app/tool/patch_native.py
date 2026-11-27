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
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MICROPHONE",
    "android.permission.POST_NOTIFICATIONS",
]
add = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in s)
if add:
    s = s.replace("<application", add + "    <application", 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Adda"', s, count=1)
# keeps voice rooms and calls running when the app is in the background
if "flutter_foreground_task.service.ForegroundService" not in s:
    s = s.replace("</application>", '        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"\n'
                  '            android:foregroundServiceType="microphone" android:exported="false" android:stopWithTask="true" />\n    </application>', 1)
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
    # ADDA_ABI=arm64-v8a (or armeabi-v7a) keeps only that phone type's native libraries, so the APK stays small
    if "ADDA_ABI" not in t:
        line = ('        ((project.findProperty("addaAbi") as String?) ?: System.getenv("ADDA_ABI"))?.let { abi -> ndk { abiFilters.clear(); abiFilters += abi } }\n' if name.endswith(".kts")
                else '        def addaAbi = project.findProperty("addaAbi") ?: System.getenv("ADDA_ABI")\n        if (addaAbi) { ndk { abiFilters addaAbi } }\n')
        t = re.sub(r'(defaultConfig\s*\{\n)', lambda m: m.group(1) + line, t, count=1)
    g.write_text(t)
# ---------- Android: build old plugins (e.g. Agora, compiled against android-31) with a current SDK ----------
(root / "android/compile_sdk_fix.gradle").write_text(
    "// Added by tool/patch_native.py: some plugins still build against an old Android SDK,\n"
    "// which newer AndroidX libraries refuse. Build every plugin with SDK 36 instead.\n"
    "subprojects { p ->\n"
    "    def fix = {\n"
    "        if (p.plugins.hasPlugin('com.android.library') && p.hasProperty('android')) {\n"
    "            p.android.compileSdkVersion 36\n"
    "        }\n"
    "    }\n"
    "    if (p.state.executed) { fix() } else { p.afterEvaluate { fix() } }\n"
    "}\n"
)
for name, line in (("android/build.gradle.kts", 'apply(from = "compile_sdk_fix.gradle")'), ("android/build.gradle", "apply from: 'compile_sdk_fix.gradle'")):
    rg = root / name
    if rg.exists() and "compile_sdk_fix.gradle" not in rg.read_text():
        rg.write_text(line + "\n\n" + rg.read_text())
        
# ---------- Android: don't let a crashing lint check stop the release build ----------
(root / "android/lint_fix.gradle").write_text(
    "subprojects { p ->\n"
    "    p.plugins.withId('com.android.application') {\n"
    "        p.android.lint {\n"
    "            checkReleaseBuilds = false\n"
    "            abortOnError = false\n"
    "        }\n"
    "    }\n"
    "}\n"
)
for name, line in (("android/build.gradle.kts", 'apply(from = "lint_fix.gradle")'), ("android/build.gradle", "apply from: 'lint_fix.gradle'")):
    rg = root / name
    if rg.exists() and "lint_fix.gradle" not in rg.read_text():
        rg.write_text(line + "\n" + rg.read_text())

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
    if "UIBackgroundModes" not in p:
        extra += "\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t\t<string>voip</string>\n\t</array>\n"
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
# iOS 15+ (Agora and the camera plugins need a recent iOS) and the same app id as Android
if podfile.exists():
    pf = podfile.read_text()
    pf2 = re.sub(r"^#?\s*platform :ios, '[0-9.]+'", "platform :ios, '15.0'", pf, flags=re.M)
    if "platform :ios" not in pf2:
        pf2 = "platform :ios, '15.0'\n" + pf2
    if "IPHONEOS_DEPLOYMENT_TARGET" not in pf2:
        pf2 = pf2.replace(
            "flutter_additional_ios_build_settings(target)\n",
            "flutter_additional_ios_build_settings(target)\n"
            "    target.build_configurations.each do |config|\n"
            "      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'\n"
            "    end\n", 1)
    podfile.write_text(pf2)
pbx = root / "ios/Runner.xcodeproj/project.pbxproj"
if pbx.exists():
    t = pbx.read_text()
    t = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = app\.adda\.adda;", "PRODUCT_BUNDLE_IDENTIFIER = app.adda.voice;", t)
    t = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.0;", t)
    pbx.write_text(t)

print("patched", man.relative_to(root))
