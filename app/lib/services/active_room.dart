import 'dart:async';

import 'package:flutter/widgets.dart';
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

  // ---- mic queue (Yari style) ----
  /// Pending mic applications (host/admins only).
  List<Map<String, dynamic>> micQueue = [];
  /// My own waiting application id, if any.
  int? myApply;
  /// Invitations to the mic for me: {id, seat, by}.
  final invites = StreamController<Map<String, dynamic>>.broadcast();
  /// Short messages for me ("You were taken off the mic", ...).
  final notices = StreamController<String>.broadcast();
  final Set<int> _seenInvites = {};
  String get micMode => '${room?['mic_mode'] ?? 'free'}';

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
    unawaited(r.loadMic());
    r._subscribe();
    r._poll = Timer.periodic(const Duration(seconds: 30), (_) => r._heartbeat());
    current.value = r;
    App.i.beforeSignOut = () async => current.value?.leave();
    BackgroundAudio.onAction = (a) {
      final cur = current.value;
      if (cur == null) return;
      if (a == 'leave') {
        cur.leave();
      } else if (a == 'mic' && cur.mySeat != null) {
        cur.rtc?.setMic(!(cur.rtc?.micOn.value ?? true));
      }
    };
    unawaited(r._startVoice());
    return r;
  }

  Future<void> _startVoice() async {
    final s = RtcSession(kind: 'room', id: '$id');
    rtc = s;
    try {
      if (isOwner) await Permission.microphone.request();
      await s.start();
      s.micOn.addListener(() => BackgroundAudio.update(micOn: mySeat != null && s.micOn.value));
      await BackgroundAudio.start('${room?['name'] ?? 'Voice room'}', micOn: mySeat != null && s.micOn.value);
      voiceError = null;
    } catch (e) {
      voiceError = errText(e);
    }
    _notify();
  }

  void _notify() {
    if (!_left) notifyListeners();
  }

  /// Tells the server we are still here (keeps the member list accurate) and refreshes the room.
  Future<void> _heartbeat() async {
    try {
      final n = await App.i.rpc('room_ping', {'p_room': id});
      if (room != null && n is num) room!['listeners'] = n;
    } catch (_) {}
    await refreshRoom();
  }

  bool? _micBeforePause;

  /// Called by the app when it goes to the background or comes back.
  static Future<void> onLifecycle(AppLifecycleState state) async {
    final r = current.value;
    if (r == null || r._left) return;
    final s = r.rtc;
    if (state == AppLifecycleState.detached) {
      await r.leave();
      return;
    }
    if (BackgroundAudio.allowed || s == null) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (r._micBeforePause != null) return;
      r._micBeforePause = s.micOn.value;
      await s.setMic(false);
      await s.engine?.muteAllRemoteAudioStreams(true);
    } else if (state == AppLifecycleState.resumed && r._micBeforePause != null) {
      await s.engine?.muteAllRemoteAudioStreams(false);
      await s.setMic(r._micBeforePause!);
      r._micBeforePause = null;
    }
  }

  Future<void> refreshRoom() async {
    final r = await db
        .from('rooms')
        .select('id, owner_id, name, topic, language, announcement, cover_url, cover_template, theme, seats, locked, status, listeners, score_today, mic_mode')
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

  Future<void> reloadGifts() async {
    try {
      await _loadGifts();
    } catch (_) {}
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

  /// Loads the waiting list (admins), my own application and any invitation waiting for me.
  Future<void> loadMic() async {
    try {
      if (isAdmin) {
        micQueue = List<Map<String, dynamic>>.from(await App.i.rpc('mic_queue', {'p_room': id}) as List);
      }
      final mine = await db.from('mic_requests').select('id').eq('room_id', id).eq('user_id', myId!).eq('kind', 'apply').eq('status', 'pending').maybeSingle();
      myApply = (mine?['id'] as num?)?.toInt();
      final inv = await App.i.rpc('mic_my_invite', {'p_room': id});
      if (inv is Map && inv['id'] != null && invites.hasListener && _seenInvites.add((inv['id'] as num).toInt())) invites.add(Map<String, dynamic>.from(inv));
    } catch (_) {}
    _notify();
  }

  Future<void> _onMicRequest(Map<String, dynamic> row) async {
    if (_left || row.isEmpty) return;
    final mine = row['user_id'] == myId;
    final rid = (row['id'] as num?)?.toInt();
    if (mine && row['kind'] == 'invite' && row['status'] == 'pending' && rid != null && _seenInvites.add(rid)) {
      final by = Profiles.get(row['by_user'] as String?)?['username'];
      if (by == null) await Profiles.load([row['by_user'] as String?]);
      invites.add({'id': rid, 'seat': row['seat'], 'by': Profiles.get(row['by_user'] as String?)?['username'] ?? 'The host'});
    }
    if (mine && row['kind'] == 'apply') {
      if (row['status'] == 'pending') {
        myApply = rid;
      } else {
        if (myApply == rid && row['status'] == 'declined') notices.add('The host declined your mic request');
        myApply = null;
      }
    }
    if (isAdmin && row['kind'] == 'apply') {
      try {
        micQueue = List<Map<String, dynamic>>.from(await App.i.rpc('mic_queue', {'p_room': id}) as List);
      } catch (_) {}
    }
    _notify();
  }

  /// I was put on a seat by the host (approved request / accepted invite): switch my mic on like Yari does.
  Future<void> _wentOnMic() async {
    try {
      final p = await Permission.microphone.request();
      await rtc?.refresh();
      if (p.isGranted) await rtc?.setMic(true);
    } catch (_) {}
  }

  void _subscribe() {
    PostgresChangeFilter byRoom() => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: id);
    _ch = db
        .channel('room:$id')
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'room_seats', filter: byRoom(), callback: (p) => _onSeat(p.newRecord))
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'room_messages', filter: byRoom(), callback: (p) => _onMessage(p.newRecord))
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'gift_events', filter: byRoom(), callback: (p) => _onGift(p.newRecord))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'mic_requests', filter: byRoom(), callback: (p) => _onMicRequest(p.newRecord))
        .subscribe();
  }

  Future<void> _onSeat(Map<String, dynamic> row) async {
    final old = seats.where((s) => s['seat'] == row['seat']).firstOrNull;
    final wasMine = old?['user_id'] == myId && myId != null;
    final hadSeat = mySeat != null;
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
      // moved by me to another seat is fine; otherwise an admin took me off
      if (mySeat == null && !_leavingSeat && !_takingSeat) notices.add('You were taken off the mic');
    } else if (mineNow && row['muted'] == true) {
      await rtc?.setMic(false);
      await rtc?.refresh();
      if (old?['muted'] != true && wasMine) notices.add('A room admin muted your mic');
    } else if (mineNow && wasMine && old?['muted'] == true && row['muted'] != true) {
      notices.add('You can talk again');
    } else if (mineNow && !hadSeat && !_takingSeat) {
      myApply = null;
      notices.add('You are on mic No.${row['seat']} 🎙️');
      await _wentOnMic();
    }
    _notify();
  }

  bool _takingSeat = false;
  bool _leavingSeat = false;

  /// Wraps my own seat changes so they are not mistaken for admin actions.
  Future<T> mySeatChange<T>(Future<T> Function() fn, {bool leaving = false}) async {
    if (leaving) {
      _leavingSeat = true;
    } else {
      _takingSeat = true;
    }
    try {
      return await fn();
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        _takingSeat = false;
        _leavingSeat = false;
      });
    }
  }

  Future<void> _onMessage(Map<String, dynamic> row) async {
    await Profiles.load([row['user_id'] as String?]);
    if (_left) return;
    msgs.add(row);
    if (msgs.length > 200) msgs.removeRange(0, msgs.length - 200);
    if (row['kind'] == 'system') {
      final body = '${row['body']}';
      if (body == 'joined the room' && row['user_id'] != myId) joins.add(row);
      if (body.contains('mic to apply mode') || body.startsWith('opened the mic')) unawaited(refreshRoom());
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
      fromId: row['sender_id'] as String?,
      toId: row['receiver_id'] as String?,
      qty: (row['qty'] as num).toInt(),
    ));
  }

  /// Leave the room completely: stop voice, free your seat.
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    _poll?.cancel();
    BackgroundAudio.onAction = null;
    if (_ch != null) await db.removeChannel(_ch!);
    await rtc?.stop();
    await BackgroundAudio.stop();
    try {
      await App.i.rpc('leave_room', {'p_room': id});
    } catch (_) {}
    if (current.value == this) current.value = null;
  }
}
