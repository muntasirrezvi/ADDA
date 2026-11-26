import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// Runs in the foreground-service isolate: forwards notification button taps to the app.
@pragma('vm:entry-point')
void roomTaskCallback() => FlutterForegroundTask.setTaskHandler(_RoomTaskHandler());

class _RoomTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp) async {}
  @override
  void onNotificationButtonPressed(String id) => FlutterForegroundTask.sendDataToMain(id);
}

/// Keeping a voice room alive while Adda is in the background.
///
/// The person decides once per app session (when they first join a room). They can tick
/// "Don't ask again" to always allow it. When allowed on Android, a notification shows the room
/// with Mute/Unmute and Leave buttons. When not allowed, leaving the app mutes the mic and the
/// room sound until they come back.
class BackgroundAudio {
  static const _prefKey = 'bg_voice_always';
  static bool? _session; // this session's answer
  static bool _always = false;
  static bool _ready = false;
  static bool _portReady = false;
  static String _room = 'Voice room';

  /// Set by the active room: 'mic' toggles the mic, 'leave' leaves the room.
  static void Function(String action)? onAction;

  static bool get allowed => _always || (_session ?? false);
  static bool get alwaysAllowed => _always;

  /// Call once at app start.
  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _always = p.getBool(_prefKey) ?? false;
    } catch (_) {}
    if (Platform.isAndroid && !_portReady) {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.addTaskDataCallback((data) {
        if (data is String) onAction?.call(data);
      });
      _portReady = true;
    }
  }

  static Future<void> setAlways(bool v) async {
    _always = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefKey, v);
    } catch (_) {}
  }

  /// Ask (once per session) whether the room may keep running in the background.
  static Future<bool> askForSession(BuildContext context) async {
    if (_always) return true;
    if (_session != null) return _session!;
    var dontAsk = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Row(children: [const Icon(Icons.headset_mic, color: C.gold), const SizedBox(width: 8), Expanded(child: Text('Keep the room on?', style: serif(20)))]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('When you switch to another app, Adda can keep you in this room so you can keep listening and talking.'),
            const SizedBox(height: 8),
            const Text('If you say no, your mic and the room sound pause while you are away, and come back when you return.', style: TextStyle(color: C.mute, fontSize: 13)),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: dontAsk,
              onChanged: (v) => set(() => dontAsk = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: C.gold,
              title: const Text("Allow and don't ask again", style: TextStyle(fontSize: 14)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, pause me', style: TextStyle(color: C.mute))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Allow', style: TextStyle(color: C.gold))),
          ],
        ),
      ),
    );
    _session = ok ?? false;
    if (_session! && dontAsk) await setAlways(true);
    if (_session! && Platform.isAndroid) {
      try {
        if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
          await FlutterForegroundTask.requestNotificationPermission();
        }
      } catch (_) {}
    }
    return _session!;
  }

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

  static List<NotificationButton> _buttons(bool micOn) => [
        NotificationButton(id: 'mic', text: micOn ? 'Mute mic' : 'Unmute mic'),
        const NotificationButton(id: 'leave', text: 'Leave room', textColor: Color(0xFFE0485A)),
      ];

  /// Show (or refresh) the room notification. Does nothing unless background voice is allowed.
  static Future<void> start(String room, {bool micOn = true}) async {
    _room = room;
    if (!Platform.isAndroid || !allowed) return;
    try {
      _init();
      final text = micOn ? 'You are live · mic on' : 'You are listening · mic off';
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationTitle: 'Adda · $_room', notificationText: text, notificationButtons: _buttons(micOn));
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 7101,
          notificationTitle: 'Adda · $_room',
          notificationText: text,
          notificationButtons: _buttons(micOn),
          callback: roomTaskCallback,
        );
      }
    } catch (_) {
      // voice still works while the app is open
    }
  }

  static Future<void> update({required bool micOn}) => start(_room, micOn: micOn);

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
