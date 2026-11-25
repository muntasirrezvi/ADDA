import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/gift_fx.dart';
import 'api.dart';
import 'background.dart';
import 'rtc.dart';

class RoomPasswordNeeded implements Exception {}

/// The voice room you are in. It lives outside the room screen, so you can minimise the room,
/// use the rest of the app (or other apps) and keep talking and listening.
class ActiveRoom extends ChangeNotifier {
  ActiveRoom._(this.id);

  static final current = ValueNotifier<ActiveRoom?>(null);
  static final screenOpen = ValueNotifier<bool>(false);

  final int id;
  Map<String, dynamic>? room;
  final List<Map<String, dynamic>> seats = [];
  final List<Map<String, dynamic>> msgs = [];
  List<Map<String, dynamic>> gifts = [];
  String? themeImage;
  bool isAdmin = false;
  bool following = false;
  String? voiceError;
  RtcSession? rtc;
  final stage = GiftStageController();
  final joins = StreamController<Map<String, dynamic>>.broadcast();
  final closedReason = ValueNotifier<String?>(null);

  RealtimeChannel? _ch;
  Timer? _poll;
  bool _left = false;
  String _lastGiftKey = '';
  DateTime _lastGiftAt = DateTime(2000);

  bool get isOwner => room?['owner_id'] == myId;
  Map<String, dynamic>? get mySeat => seats.where((s) => s['user_id'] == myId).firstOrNull;

  /// Joins a room (or returns the one you are already in). Throws [RoomPasswordNeeded] for a locked room.
  static Future<ActiveRoom> enter(int id, {String? password}) async {
    final cur = current.value;
    if (cur != null && cur.id == id && !cur._left) return cur;
    if (cur != null) await cur.leave();
    final r = ActiveRoom._(id);
    try {
      r.room = Map<String, dynamic>.from(await App.i.rpc('join_room', {'p_room': id, 'p_password': password}) as Map);
    } catch (e) {
      if (errText(e).toLowerCase().contains('wrong password')) throw RoomPasswordNeeded();
      rethrow;
    }
    await Future.wait([r.loadSeats(), r._loadMessages(), r._loadGifts(), r.loadExtras()]);
    r._subscribe();
    r._poll = Timer.periodic(const Duration(seconds: 30), (_) => r.refreshRoom());
    current.value = r;
    App.i.beforeSignOut = () async => current.value?.leave();
    unawaited(r._startVoice());
    return r;
  }

  Future<void> _startVoice() async {
    final s = RtcSession(kind: 'room', id: '$id');
    rtc = s;
    try {
      if (isOwner) await Permission.microphone.request();
      await s.start();
      await BackgroundAudio.start('${room?['name'] ?? 'Voice room'}');
      voiceError = null;
    } catch (e) {
      voiceError = errText(e);
    }
    _notify();
  }

  void _notify() {
    if (!_left) notifyListeners();
  }

  Future<void> refreshRoom() async {
    final r = await db
        .from('rooms')
        .select('id, owner_id, name, topic, language, announcement, cover_url, cover_template, theme, seats, locked, status, listeners, score_today')
        .eq('id', id)
        .maybeSingle();
    if (_left) return;
    if (r == null || r['status'] != 'open') {
      closedReason.value = 'This room has closed';
      await leave();
      return;
    }
    room = r;
    _notify();
  }

  Future<void> loadSeats() async {
    final rows = await db.from('room_seats').select().eq('room_id', id).order('seat');
    seats
      ..clear()
      ..addAll(List<Map<String, dynamic>>.from(rows));
    await Profiles.load(seats.map((s) => s['user_id'] as String?));
    final m = await db.from('room_members').select('role').eq('room_id', id).eq('user_id', myId!).maybeSingle();
    final role = App.i.me.value?['role'];
    isAdmin = isOwner || m?['role'] == 'admin' || role == 'admin' || role == 'moderator';
  }

  Future<void> _loadMessages() async {
    final rows = await db.from('room_messages').select().eq('room_id', id).order('id', ascending: false).limit(50);
    msgs
      ..clear()
      ..addAll(List<Map<String, dynamic>>.from(rows).reversed);
    await Profiles.load(msgs.map((m) => m['user_id'] as String?));
  }

  Future<void> _loadGifts() async {
    final rows = await db.from('gifts').select().eq('active', true).order('sort');
    final now = DateTime.now();
    gifts = List<Map<String, dynamic>>.from(rows).where((g) {
      final s = DateTime.tryParse('${g['starts_at']}');
      final e = DateTime.tryParse('${g['ends_at']}');
      return (s == null || s.isBefore(now)) && (e == null || e.isAfter(now));
    }).toList();
  }

  Future<void> loadExtras() async {
    final t = await db.from('room_themes').select('image_url').eq('id', '${room?['theme'] ?? ''}').maybeSingle();
    themeImage = t?['image_url'] as String?;
    final f = await db.from('room_follows').select('room_id').eq('room_id', id).eq('user_id', myId!).maybeSingle();
    following = f != null;
  }

  void _subscribe() {
    PostgresChangeFilter byRoom() => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: id);
    _ch = db
        .channel('room:$id')
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'room_seats', filter: byRoom(), callback: (p) => _onSeat(p.newRecord))
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'room_messages', filter: byRoom(), callback: (p) => _onMessage(p.newRecord))
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'gift_events', filter: byRoom(), callback: (p) => _onGift(p.newRecord))
        .subscribe();
  }

  Future<void> _onSeat(Map<String, dynamic> row) async {
    final wasMine = mySeat?['seat'] == row['seat'];
    await Profiles.load([row['user_id'] as String?]);
    if (_left) return;
    final i = seats.indexWhere((s) => s['seat'] == row['seat']);
    if (i >= 0) {
      seats[i] = row;
    } else {
      seats.add(row);
    }
    final mineNow = row['user_id'] == myId;
    if (wasMine && !mineNow) {
      await rtc?.refresh();
    } else if (mineNow && row['muted'] == true) {
      await rtc?.setMic(false);
      await rtc?.refresh();
    }
    _notify();
  }

  Future<void> _onMessage(Map<String, dynamic> row) async {
    await Profiles.load([row['user_id'] as String?]);
    if (_left) return;
    msgs.add(row);
    if (msgs.length > 200) msgs.removeRange(0, msgs.length - 200);
    if (row['kind'] == 'system') {
      final body = '${row['body']}';
      if (body == 'joined the room' && row['user_id'] != myId) joins.add(row);
      if (body.contains('closed the room') && !isOwner) {
        closedReason.value = 'The host closed the room';
        await leave();
        return;
      }
    }
    _notify();
  }

  Future<void> _onGift(Map<String, dynamic> row) async {
    final g = gifts.where((x) => x['id'] == row['gift_id']).firstOrNull;
    if (g == null) return;
    await Profiles.load([row['sender_id'] as String?, row['receiver_id'] as String?]);
    final key = '${row['sender_id']}|${row['gift_id']}|${row['qty']}';
    if (key == _lastGiftKey && DateTime.now().difference(_lastGiftAt).inMilliseconds < 2500) return;
    _lastGiftKey = key;
    _lastGiftAt = DateTime.now();
    if (!screenOpen.value) return; // minimised: skip the animation
    stage.play(GiftShow(
      gift: g,
      from: '${Profiles.get(row['sender_id'] as String?)?['username'] ?? 'Someone'}',
      to: '${Profiles.get(row['receiver_id'] as String?)?['username'] ?? 'someone'}',
      qty: (row['qty'] as num).toInt(),
    ));
  }

  /// Leave the room completely: stop voice, free your seat.
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    _poll?.cancel();
    if (_ch != null) await db.removeChannel(_ch!);
    await rtc?.stop();
    await BackgroundAudio.stop();
    try {
      await App.i.rpc('leave_room', {'p_room': id});
    } catch (_) {}
    if (current.value == this) current.value = null;
  }
}
