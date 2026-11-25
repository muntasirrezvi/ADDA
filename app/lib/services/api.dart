import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Values passed at build time:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

SupabaseClient get db => Supabase.instance.client;
String? get myId => db.auth.currentUser?.id;

/// Turns any backend error into a short sentence for the user.
String errText(Object e) {
  if (e is PostgrestException) return _clean(e.message);
  if (e is AuthException) return _clean(e.message);
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['error'] != null) return d['error'].toString();
    return 'Server error (${e.status})';
  }
  if (e is StorageException) return _clean(e.message);
  final s = e.toString();
  return _clean(s.startsWith('Exception: ') ? s.substring(11) : s);
}

String _clean(String s) => s.isEmpty ? 'Something went wrong' : s[0].toUpperCase() + s.substring(1);

/// Global app state: who is signed in, their wallet and app settings.
class App {
  App._();
  static final App i = App._();

  final me = ValueNotifier<Map<String, dynamic>?>(null);
  final coins = ValueNotifier<int>(0);
  final diamonds = ValueNotifier<int>(0);
  final unread = ValueNotifier<int>(0);
  Map<String, dynamic> settings = {};
  RealtimeChannel? _ch;

  bool flag(String key, {bool fallback = false}) {
    final v = settings[key];
    if (v is bool) return v;
    if (v is String) return v == 'true';
    return fallback;
  }

  num number(String key, num fallback) {
    final v = settings[key];
    if (v is num) return v;
    return num.tryParse('$v') ?? fallback;
  }

  Future<void> loadSettings() async {
    try {
      final rows = await db.from('app_settings').select('key, value');
      settings = {for (final r in rows) r['key'] as String: r['value']};
    } catch (_) {/* keep defaults */}
  }

  Future<void> loadMe() async {
    final id = myId;
    if (id == null) return;
    final p = await db.from('profiles').select().eq('id', id).single();
    me.value = p;
    Profiles.put(p);
    await refreshWallet();
    await refreshUnread();
    _listen(id);
  }

  Future<void> refreshWallet() async {
    final id = myId;
    if (id == null) return;
    final w = await db.from('wallets').select('coins, diamonds').eq('user_id', id).single();
    coins.value = (w['coins'] as num).toInt();
    diamonds.value = (w['diamonds'] as num).toInt();
  }

  Future<void> refreshUnread() async {
    final id = myId;
    if (id == null) return;
    final r = await db.from('notifications').select('id').eq('user_id', id).eq('read', false).count(CountOption.exact);
    unread.value = r.count;
  }

  void _listen(String id) {
    if (_ch != null) db.removeChannel(_ch!);
    _ch = db
        .channel('me:$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: id),
          callback: (p) {
            coins.value = (p.newRecord['coins'] as num?)?.toInt() ?? coins.value;
            diamonds.value = (p.newRecord['diamonds'] as num?)?.toInt() ?? diamonds.value;
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: id),
          callback: (p) {
            unread.value = unread.value + 1;
            notifications.add(p.newRecord);
          },
        )
        .subscribe();
  }

  /// New notifications as they arrive (the shell shows a banner).
  final notifications = StreamController<Map<String, dynamic>>.broadcast();

  Future<void> signOut() async {
    if (_ch != null) await db.removeChannel(_ch!);
    _ch = null;
    me.value = null;
    await db.auth.signOut();
  }

  Future<dynamic> rpc(String fn, [Map<String, dynamic>? params]) => db.rpc(fn, params: params);

  Future<dynamic> fn(String name, Map<String, dynamic> body) async {
    final r = await db.functions.invoke(name, body: body);
    return r.data;
  }

  /// Uploads into `<bucket>/<my id>/<name>` and returns the public URL (or the path for private buckets).
  Future<String> upload(String bucket, Uint8List bytes, String ext, {bool private = false}) async {
    final contentType = switch (ext.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'm4a' => 'audio/m4a',
      'aac' => 'audio/aac',
      _ => 'image/jpeg',
    };
    final path = '$myId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await db.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false));
    return private ? path : db.storage.from(bucket).getPublicUrl(path);
  }
}

/// Small cache of public profiles so rooms and chats can show names and avatars.
class Profiles {
  static final Map<String, Map<String, dynamic>> _c = {};
  static const cols = 'id, public_id, username, avatar_url, avatar_preset, wealth_level, charm_xp, vip_tier, verified, bio, cover_url, country, role';

  static Map<String, dynamic>? get(String? id) => id == null ? null : _c[id];
  static void put(Map<String, dynamic> p) => _c[p['id'] as String] = p;

  static Future<void> load(Iterable<String?> ids) async {
    final need = ids.whereType<String>().where((id) => !_c.containsKey(id)).toSet().toList();
    if (need.isEmpty) return;
    final rows = await db.from('profiles').select(cols).inFilter('id', need);
    for (final r in rows) {
      put(r);
    }
  }

  static Future<Map<String, dynamic>?> fetch(String id, {bool fresh = false}) async {
    if (!fresh && _c.containsKey(id)) return _c[id];
    final r = await db.from('profiles').select(cols).eq('id', id).maybeSingle();
    if (r != null) put(r);
    return r;
  }
}

String compact(num n) {
  final v = n.abs();
  String f(double x, String s) => '${x.toStringAsFixed(x >= 100 || x == x.roundToDouble() ? 0 : 1)}$s';
  final sign = n < 0 ? '-' : '';
  if (v >= 1e9) return sign + f(v / 1e9, 'B');
  if (v >= 1e6) return sign + f(v / 1e6, 'M');
  if (v >= 1e3) return sign + f(v / 1e3, 'K');
  return '$n';
}

String grouped(num n) {
  final s = n.toInt().abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
