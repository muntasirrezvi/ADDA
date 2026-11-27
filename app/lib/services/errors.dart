import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Sends app errors to the server (table app_errors) so problems on real phones can be fixed.
class ErrorReporter {
  static int _sent = 0;
  static final Set<String> _seen = {};

  static void install() {
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      prev?.call(details);
      report(details.exception, details.stack, where: details.library ?? 'flutter');
    };
    PlatformDispatcher.instance.onError = (e, st) {
      report(e, st, where: 'async');
      return true;
    };
    // a broken widget shows a small notice instead of a grey or red screen
    ErrorWidget.builder = (details) => const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('Something went wrong here', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        );
  }

  static void report(Object e, StackTrace? st, {String where = ''}) {
    debugPrint('ADDA error [$where]: $e\n$st');
    final key = '$where|$e'.substring(0, '$where|$e'.length.clamp(0, 300));
    if (_sent > 30 || !_seen.add(key)) return;
    _sent++;
    try {
      db.from('app_errors').insert({
        'user_id': db.auth.currentUser?.id,
        'where_': where,
        'message': '$e'.substring(0, '$e'.length.clamp(0, 2000)),
        'stack': '${st ?? ''}'.substring(0, '${st ?? ''}'.length.clamp(0, 6000)),
        'platform': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      }).then((_) {}, onError: (_) {});
    } catch (_) {}
  }

  static const _exitNames = {2: 'killed by signal', 3: 'out of memory', 4: 'Java crash', 5: 'native crash', 6: 'froze (ANR)', 7: 'failed to start', 9: 'used too many resources', 13: 'other'};

  /// Android 11+: if Android closed the app last time (crash, out of memory, freeze), send the reason and trace.
  static Future<void> reportLastExit() async {
    if (!Platform.isAndroid) return;
    try {
      final r = await const MethodChannel('adda/exit').invokeMapMethod<String, dynamic>('reasons');
      if (r == null) return;
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('exit_reported') ?? 0;
      var newest = last;
      for (final e in (r['list'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(e as Map);
        final t = (m['time'] as num?)?.toInt() ?? 0;
        if (t <= last) continue;
        if (t > newest) newest = t;
        final reason = (m['reason'] as num?)?.toInt() ?? 0;
        if (!_exitNames.containsKey(reason)) continue;
        await db.from('app_errors').insert({
          'user_id': db.auth.currentUser?.id,
          'where_': 'android exit: ${_exitNames[reason]}',
          'message': 'desc=${m['desc']} status=${m['status']} importance=${m['importance']} pss=${m['pss']} rss=${m['rss']} at=${DateTime.fromMillisecondsSinceEpoch(t).toUtc()}',
          'stack': '${m['trace'] ?? ''}'.substring(0, '${m['trace'] ?? ''}'.length.clamp(0, 6000)),
          'platform': 'Android sdk ${r['sdk']} · ${r['device']} · ${r['abis']}',
        });
      }
      if (newest > last) await prefs.setInt('exit_reported', newest);
    } catch (e) {
      debugPrint('ADDA exit report failed: $e');
    }
  }
}
