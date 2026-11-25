import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the microphone and voice running while Adda is in the background
/// (Android requires a visible "foreground service" notification for this).
class BackgroundAudio {
  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'adda_voice',
        channelName: 'Voice room',
        channelDescription: 'Shown while you are in a voice room or call',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _ready = true;
  }

  static Future<void> start(String text) async {
    if (!Platform.isAndroid) return;
    try {
      _init();
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationTitle: 'Adda · live', notificationText: text);
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 7101,
          notificationTitle: 'Adda · live',
          notificationText: text,
        );
      }
    } catch (_) {
      // voice still works while the app is open
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
