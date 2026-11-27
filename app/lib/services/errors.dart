import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
}
