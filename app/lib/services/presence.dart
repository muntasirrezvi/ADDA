import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'api.dart';

/// Online status: the app reports "I'm here" every minute while it is open, and shows
/// others as Online / Last seen … / Offline (when they hide their last seen).
class OnlineStatus {
  static Timer? _beat;
  static final Map<String, ({bool online, DateTime? lastSeen, bool hidden, DateTime fetched})> _cache = {};

  static void start() {
    _ping();
    _beat?.cancel();
    _beat = Timer.periodic(const Duration(seconds: 60), (_) => _ping());
  }

  static void stop() {
    _beat?.cancel();
    _beat = null;
  }

  static Future<void> _ping() async {
    if (myId == null) return;
    try {
      await App.i.rpc('touch_presence');
    } catch (_) {}
  }

  static Future<({bool online, DateTime? lastSeen, bool hidden})?> of(String id, {bool fresh = false}) async {
    final c = _cache[id];
    if (!fresh && c != null && DateTime.now().difference(c.fetched).inSeconds < 30) return (online: c.online, lastSeen: c.lastSeen, hidden: c.hidden);
    try {
      final rows = await App.i.rpc('user_presence', {'p_ids': [id]}) as List;
      if (rows.isEmpty) return null;
      final r = Map<String, dynamic>.from(rows.first as Map);
      final v = (online: r['online'] == true, lastSeen: DateTime.tryParse('${r['last_seen']}')?.toLocal(), hidden: r['hidden'] == true, fetched: DateTime.now());
      _cache[id] = v;
      return (online: v.online, lastSeen: v.lastSeen, hidden: v.hidden);
    } catch (_) {
      return null;
    }
  }

  static String ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 7) return '${d.inDays} days ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}

/// "● Online", "Last seen 5 min ago" or "Offline".
class PresenceText extends StatefulWidget {
  const PresenceText(this.userId, {super.key, this.size = 12});
  final String userId;
  final double size;
  @override
  State<PresenceText> createState() => _PresenceTextState();
}

class _PresenceTextState extends State<PresenceText> {
  ({bool online, DateTime? lastSeen, bool hidden})? _p;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 45), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await OnlineStatus.of(widget.userId);
    if (mounted) setState(() => _p = p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const SizedBox.shrink();
    final online = p.online;
    final text = online ? 'Online' : (p.lastSeen == null ? 'Offline' : 'Last seen ${OnlineStatus.ago(p.lastSeen!)}');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: widget.size * .65,
        height: widget.size * .65,
        decoration: BoxDecoration(shape: BoxShape.circle, color: online ? const Color(0xFF3DDC84) : C.mute, boxShadow: online ? const [BoxShadow(color: Color(0x803DDC84), blurRadius: 6)] : null),
      ),
      const SizedBox(width: 5),
      Text(text, style: TextStyle(fontSize: widget.size, color: online ? const Color(0xFF7FE8B0) : C.mute)),
    ]);
  }
}
