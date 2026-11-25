import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api.dart';
import '../services/rtc.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gift_fx.dart';
import 'create_room.dart';
import 'profile_screen.dart';
import 'wallet_screen.dart';

void openRoom(BuildContext context, int id) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => RoomScreen(roomId: id)));
}

const themeLook = <String, List<Color>>{
  'majlis': [Color(0xFF4A0C1E), Color(0xFF1A0910), Color(0xFF0C0A09)],
  'midnight': [Color(0xFF13234A), Color(0xFF0A0F22), Color(0xFF05070F)],
  'garden': [Color(0xFF1F4A2A), Color(0xFF0D2414), Color(0xFF060F09)],
  'ocean': [Color(0xFF0F4A4F), Color(0xFF082629), Color(0xFF041214)],
  'palace': [Color(0xFF6B4A12), Color(0xFF3A1E3A), Color(0xFF120812)],
  'galaxy': [Color(0xFF3A1E7A), Color(0xFF140A33), Color(0xFF05030F)],
  'sakura': [Color(0xFF7A2E4F), Color(0xFF3A1226), Color(0xFF14060D)],
  'gold': [Color(0xFF8A6A2B), Color(0xFF3A2A12), Color(0xFF120D06)],
};

class RoomBackground extends StatelessWidget {
  const RoomBackground({super.key, required this.themeId, this.image});
  final String themeId;
  final String? image;
  @override
  Widget build(BuildContext context) {
    final g = Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: themeLook[themeId] ?? themeLook['majlis']!)),
    );
    if (image == null || image!.isEmpty) return g;
    return CachedNetworkImage(imageUrl: image!, fit: BoxFit.cover, placeholder: (_, __) => g, errorWidget: (_, __, ___) => g);
  }
}

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.roomId});
  final int roomId;
  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  Map<String, dynamic>? _room;
  List<Map<String, dynamic>> _seats = [];
  final List<Map<String, dynamic>> _msgs = [];
  List<Map<String, dynamic>> _gifts = [];
  String? _themeImage;
  bool _isAdmin = false;
  bool _following = false;
  String? _error;
  RtcSession? _rtc;
  RealtimeChannel? _ch;
  Timer? _poll;
  final _stage = GiftStageController();
  final _scroll = ScrollController();
  final _input = TextEditingController();
  String _lastGiftKey = '';
  DateTime _lastGiftAt = DateTime(2000);

  int get _id => widget.roomId;
  bool get _isOwner => _room?['owner_id'] == myId;
  Map<String, dynamic>? get _mySeat => _seats.where((s) => s['user_id'] == myId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _enter();
  }

  Future<void> _enter({String? password}) async {
    try {
      final r = await App.i.rpc('join_room', {'p_room': _id, 'p_password': password});
      _room = Map<String, dynamic>.from(r as Map);
    } catch (e) {
      final msg = errText(e);
      if (msg.toLowerCase().contains('wrong password') && mounted) {
        final pw = await askText(context, 'Private room', hint: 'Room password', number: true, obscure: true);
        if (pw != null && pw.isNotEmpty) return _enter(password: pw);
        if (mounted) Navigator.pop(context);
        return;
      }
      if (mounted) setState(() => _error = msg);
      return;
    }
    await Future.wait([_loadSeats(), _loadMessages(), _loadGifts(), _loadExtras()]);
    _subscribe();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshRoom());
    if (mounted) setState(() {});
    // voice: start as listener; the owner starts on the host seat
    final s = RtcSession(kind: 'room', id: '$_id');
    _rtc = s;
    try {
      if (_isOwner) await Permission.microphone.request();
      await s.start();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) toast(context, 'Voice is unavailable: ${errText(e)}', bad: true);
    }
  }

  Future<void> _refreshRoom() async {
    final r = await db.from('rooms').select('id, owner_id, name, topic, language, announcement, cover_url, cover_template, theme, seats, locked, status, listeners, score_today').eq('id', _id).maybeSingle();
    if (!mounted) return;
    if (r == null || r['status'] != 'open') {
      toast(context, 'This room has closed');
      Navigator.pop(context);
      return;
    }
    setState(() => _room = r);
  }

  Future<void> _loadSeats() async {
    final rows = await db.from('room_seats').select().eq('room_id', _id).order('seat');
    _seats = List<Map<String, dynamic>>.from(rows);
    await Profiles.load(_seats.map((s) => s['user_id'] as String?));
    final m = await db.from('room_members').select('role').eq('room_id', _id).eq('user_id', myId!).maybeSingle();
    _isAdmin = _isOwner || m?['role'] == 'admin' || App.i.me.value?['role'] == 'admin' || App.i.me.value?['role'] == 'moderator';
  }

  Future<void> _loadMessages() async {
    final rows = await db.from('room_messages').select().eq('room_id', _id).order('id', ascending: false).limit(50);
    _msgs
      ..clear()
      ..addAll(List<Map<String, dynamic>>.from(rows).reversed);
    await Profiles.load(_msgs.map((m) => m['user_id'] as String?));
    _toBottom();
  }

  Future<void> _loadGifts() async {
    final rows = await db.from('gifts').select().eq('active', true).order('sort');
    final now = DateTime.now();
    _gifts = List<Map<String, dynamic>>.from(rows).where((g) {
      final s = DateTime.tryParse('${g['starts_at']}');
      final e = DateTime.tryParse('${g['ends_at']}');
      return (s == null || s.isBefore(now)) && (e == null || e.isAfter(now));
    }).toList();
  }

  Future<void> _loadExtras() async {
    final theme = _room?['theme'];
    final t = await db.from('room_themes').select('image_url').eq('id', theme ?? '').maybeSingle();
    _themeImage = t?['image_url'] as String?;
    final f = await db.from('room_follows').select('room_id').eq('room_id', _id).eq('user_id', myId!).maybeSingle();
    _following = f != null;
  }

  void _subscribe() {
    PostgresChangeFilter byRoom() => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: _id);
    _ch = db
        .channel('room:$_id')
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'room_seats', filter: byRoom(), callback: (p) => _onSeat(p.newRecord))
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'room_messages', filter: byRoom(), callback: (p) => _onMessage(p.newRecord))
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'gift_events', filter: byRoom(), callback: (p) => _onGift(p.newRecord))
        .subscribe();
  }

  Future<void> _onSeat(Map<String, dynamic> row) async {
    final wasMine = _mySeat?['seat'] == row['seat'];
    await Profiles.load([row['user_id'] as String?]);
    if (!mounted) return;
    setState(() {
      final i = _seats.indexWhere((s) => s['seat'] == row['seat']);
      if (i >= 0) {
        _seats[i] = row;
      } else {
        _seats.add(row);
      }
    });
    final mineNow = row['user_id'] == myId;
    if (wasMine && !mineNow) {
      toast(context, 'You are off the mic');
      _rtc?.refresh();
    } else if (mineNow && row['muted'] == true) {
      _rtc?.setMic(false);
      _rtc?.refresh();
    }
  }

  Future<void> _onMessage(Map<String, dynamic> row) async {
    await Profiles.load([row['user_id'] as String?]);
    if (!mounted) return;
    setState(() => _msgs.add(row));
    if (_msgs.length > 200) _msgs.removeRange(0, _msgs.length - 200);
    _toBottom();
    if (row['kind'] == 'system' && '${row['body']}'.contains('closed the room') && !_isOwner) {
      toast(context, 'The host closed the room');
      Navigator.pop(context);
    }
  }

  Future<void> _onGift(Map<String, dynamic> row) async {
    final g = _gifts.where((x) => x['id'] == row['gift_id']).firstOrNull;
    if (g == null) return;
    await Profiles.load([row['sender_id'] as String?, row['receiver_id'] as String?]);
    // a gift to several people arrives as several rows: show it once
    final key = '${row['sender_id']}|${row['gift_id']}|${row['qty']}';
    if (key == _lastGiftKey && DateTime.now().difference(_lastGiftAt).inMilliseconds < 2500) return;
    _lastGiftKey = key;
    _lastGiftAt = DateTime.now();
    _stage.play(GiftShow(
      gift: g,
      from: '${Profiles.get(row['sender_id'] as String?)?['username'] ?? 'Someone'}',
      to: '${Profiles.get(row['receiver_id'] as String?)?['username'] ?? 'someone'}',
      qty: (row['qty'] as num).toInt(),
    ));
    if (mounted) setState(() {});
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (_ch != null) db.removeChannel(_ch!);
    _rtc?.stop();
    if (_room != null) App.i.rpc('leave_room', {'p_room': _id}).catchError((_) => null);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  // ---------- actions ----------
  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await attempt(context, () => db.from('room_messages').insert({'room_id': _id, 'user_id': myId, 'body': text}));
  }

  Future<void> _takeSeat(int seat) async {
    final p = await Permission.microphone.request();
    if (!p.isGranted) {
      if (mounted) toast(context, 'Allow microphone access to speak', bad: true);
      return;
    }
    if (!mounted) return;
    await attempt(context, () async {
      await App.i.rpc('take_seat', {'p_room': _id, 'p_seat': seat});
      await _rtc?.refresh();
      await _rtc?.setMic(true);
    });
  }

  Future<void> _leaveSeat() async {
    await attempt(context, () async {
      await App.i.rpc('leave_seat', {'p_room': _id});
      await _rtc?.refresh();
    });
  }

  Future<void> _seatAction(int seat, String action) =>
      attempt(context, () => App.i.rpc('host_seat_action', {'p_room': _id, 'p_seat': seat, 'p_action': action}));

  void _tapSeat(Map<String, dynamic> s) {
    final uid = s['user_id'] as String?;
    final seat = (s['seat'] as num).toInt();
    if (uid == null) {
      if (s['locked'] == true) {
        if (_isAdmin) _seatAction(seat, 'unlock');
        return;
      }
      if (_isAdmin) {
        _sheet([
          ('Take this seat', Icons.event_seat, () => _takeSeat(seat)),
          ('Lock seat', Icons.lock, () => _seatAction(seat, 'lock')),
        ]);
      } else {
        _takeSeat(seat);
      }
      return;
    }
    if (uid == myId) {
      final muted = !(_rtc?.micOn.value ?? true);
      _sheet([
        (muted ? 'Turn mic on' : 'Mute my mic', muted ? Icons.mic : Icons.mic_off, () => _rtc?.setMic(muted)),
        if (seat != 0) ('Leave seat', Icons.logout, _leaveSeat),
      ]);
      return;
    }
    _userSheet(uid, seat);
  }

  void _sheet(List<(String, IconData, VoidCallback)> items) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final it in items)
            ListTile(
              leading: Icon(it.$2, color: C.gold),
              title: Text(it.$1),
              onTap: () {
                Navigator.pop(ctx);
                it.$3();
              },
            ),
        ]),
      ),
    );
  }

  void _userSheet(String uid, int? seat) {
    final p = Profiles.get(uid);
    final sn = seat ?? -1;
    final seatRow = seat == null ? null : _seats.where((s) => s['seat'] == seat).firstOrNull;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Avatar(profile: p, size: 72, ring: C.gold),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text('${p?['username'] ?? ''}', overflow: TextOverflow.ellipsis, style: serif(20))),
              const SizedBox(width: 6),
              LevelBadge((p?['wealth_level'] as num?)?.toInt() ?? 1),
            ]),
            Text('ID ${p?['public_id'] ?? ''}', style: const TextStyle(color: C.mute, fontSize: 12)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)));
                },
                icon: const Icon(Icons.person, color: C.gold),
                label: const Text('Profile', style: TextStyle(color: C.text)),
              )),
              const SizedBox(width: 10),
              Expanded(child: GoldButton(label: 'Send gift', icon: Icons.card_giftcard, onTap: () {
                Navigator.pop(ctx);
                _openGifts(preselect: uid);
              })),
            ]),
            if (_isAdmin) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                if (seat != null && seat != 0 && seatRow?['muted'] != true) ActionChip(label: const Text('Mute'), onPressed: () { Navigator.pop(ctx); _seatAction(sn, 'mute'); }),
                if (seat != null && seat != 0 && seatRow?['muted'] == true) ActionChip(label: const Text('Unmute'), onPressed: () { Navigator.pop(ctx); _seatAction(sn, 'unmute'); }),
                if (seat != null && seat != 0) ActionChip(label: const Text('Remove from mic'), onPressed: () { Navigator.pop(ctx); _seatAction(sn, 'remove'); }),
                if (_isOwner) ActionChip(label: const Text('Make room admin'), onPressed: () { Navigator.pop(ctx); attempt(context, () => App.i.rpc('set_room_admin', {'p_room': _id, 'p_user': uid, 'p_admin': true}), ok: 'Now a room admin'); }),
                ActionChip(
                  label: const Text('Kick out', style: TextStyle(color: C.ruby)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (await confirm(context, 'Kick ${p?['username']}?', 'They will not be able to come back to this room.', yes: 'Kick', danger: true)) {
                      if (mounted) attempt(context, () => App.i.rpc('kick_from_room', {'p_room': _id, 'p_user': uid}), ok: 'Removed from the room');
                    }
                  },
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  void _openGifts({String? preselect}) {
    final onMic = _seats.where((s) => s['user_id'] != null && s['user_id'] != myId).map((s) => s['user_id'] as String).toList();
    final owner = _room?['owner_id'] as String?;
    if (owner != null && owner != myId && !onMic.contains(owner)) onMic.insert(0, owner);
    if (preselect != null && !onMic.contains(preselect)) onMic.insert(0, preselect);
    if (onMic.isEmpty) {
      toast(context, 'Nobody to send a gift to yet');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GiftSheet(roomId: _id, gifts: _gifts, people: onMic, preselect: preselect ?? onMic.first),
    );
  }

  void _menu() {
    _sheet([
      ('Copy room ID $_id', Icons.copy, () {
        Clipboard.setData(ClipboardData(text: '$_id'));
        toast(context, 'Room ID copied');
      }),
      (_following ? 'Unfollow room' : 'Follow room', _following ? Icons.favorite : Icons.favorite_border, () => attempt(context, () async {
            if (_following) {
              await db.from('room_follows').delete().eq('room_id', _id).eq('user_id', myId!);
            } else {
              await db.from('room_follows').insert({'room_id': _id, 'user_id': myId});
            }
            setState(() => _following = !_following);
          })),
      if (_isOwner)
        ('Edit room, cover and theme', Icons.edit, () async {
          final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RoomEditor(room: _room)));
          if (changed == true) {
            await _refreshRoom();
            await _loadExtras();
            if (mounted) setState(() {});
          }
        }),
      if (_isAdmin)
        ('Schedule an event', Icons.event, () async {
          final title = await askText(context, 'Event title', hint: 'e.g. Friday night music');
          if (title == null || title.length < 2 || !mounted) return;
          final day = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
          if (day == null || !mounted) return;
          final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 21, minute: 0));
          if (time == null || !mounted) return;
          final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
          await attempt(context, () => db.from('room_events').insert({'room_id': _id, 'title': title, 'starts_at': at.toUtc().toIso8601String(), 'created_by': myId}), ok: 'Event scheduled');
        }),
      if (!_isOwner)
        ('Report room', Icons.flag, () async {
          final why = await askText(context, 'Report this room', hint: 'What is wrong?');
          if (why == null || why.isEmpty || !mounted) return;
          await attempt(context, () => db.from('reports').insert({'reporter_id': myId, 'target_room': _id, 'reason': 'room', 'details': why}), ok: 'Thanks, our team will review it');
        }),
      if (_isOwner)
        ('Close room', Icons.power_settings_new, () async {
          if (!await confirm(context, 'Close the room?', 'Everyone will be sent out.', yes: 'Close', danger: true)) return;
          if (!mounted) return;
          final ok = await attempt(context, () => App.i.rpc('close_room', {'p_room': _id}));
          if (ok && mounted) Navigator.pop(context);
        }),
    ]);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(_error!, icon: Icons.meeting_room_outlined));
    }
    final r = _room;
    if (r == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: C.gold)));
    final seatsCount = (r['seats'] as num).toInt();
    final host = _seats.where((s) => s['seat'] == 0).firstOrNull;
    final others = _seats.where((s) => (s['seat'] as num) > 0 && (s['seat'] as num) <= seatsCount).toList();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(fit: StackFit.expand, children: [
        RoomBackground(themeId: '${r['theme']}', image: _themeImage),
        Container(color: Colors.black.withValues(alpha: .25)),
        SafeArea(
          child: Column(children: [
            _header(r),
            if ('${r['announcement'] ?? ''}'.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.campaign, size: 16, color: C.gold),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${r['announcement']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                ]),
              ),
            const SizedBox(height: 10),
            if (host != null) _seatView(host, big: true),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                childAspectRatio: seatsCount > 8 ? .95 : .82,
                children: [for (final s in others) _seatView(s)],
              ),
            ),
            Expanded(child: _chat()),
            _bottomBar(),
          ]),
        ),
        Positioned.fill(child: GiftStage(controller: _stage)),
      ]),
    );
  }

  Widget _header(Map<String, dynamic> r) {
    final owner = Profiles.get(r['owner_id'] as String?);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 40, height: 40, child: CoverArt(imageUrl: r['cover_url'] as String?, template: '${r['cover_template']}', radius: 10, iconSize: 18))),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text('ID $_id · ${owner?['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [const Icon(Icons.people, size: 14), const SizedBox(width: 4), Text(compact(r['listeners'] as num? ?? 0), style: const TextStyle(fontSize: 12))]),
        ),
        IconButton(onPressed: _menu, icon: const Icon(Icons.more_horiz)),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.power_settings_new, color: C.ruby)),
      ]),
    );
  }

  Widget _seatView(Map<String, dynamic> s, {bool big = false}) {
    final uid = s['user_id'] as String?;
    final p = Profiles.get(uid);
    final seat = (s['seat'] as num).toInt();
    final size = big ? 74.0 : 54.0;
    return GestureDetector(
      onTap: () => _tapSeat(s),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ValueListenableBuilder<Set<int>>(
          valueListenable: _rtc?.talking ?? ValueNotifier<Set<int>>({}),
          builder: (_, talking, __) {
            final pid = (p?['public_id'] as num?)?.toInt();
            final speaking = uid != null && ((uid == myId && talking.contains(0)) || (pid != null && talking.contains(pid)));
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: speaking ? [BoxShadow(color: C.gold.withValues(alpha: .7), blurRadius: 16, spreadRadius: 2)] : null,
                border: Border.all(color: speaking ? C.gold : (seat == 0 ? C.gold2 : Colors.white24), width: 2),
              ),
              child: uid == null
                  ? Container(
                      width: size,
                      height: size,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black38),
                      child: Icon(s['locked'] == true ? Icons.lock : Icons.event_seat, color: Colors.white54, size: size * .4),
                    )
                  : Stack(children: [
                      Avatar(profile: p, size: size),
                      if (s['muted'] == true)
                        const Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 9, backgroundColor: C.ruby, child: Icon(Icons.mic_off, size: 11, color: Colors.white))),
                    ]),
            );
          },
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: size + 18,
          child: Text(
            uid == null ? (seat == 0 ? 'Host' : '$seat') : '${p?['username'] ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: uid == null ? Colors.white54 : Colors.white, fontWeight: seat == 0 ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      ]),
    );
  }

  Widget _chat() {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.white], stops: [0, .12]).createShader(r),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 16, 60, 8),
        itemCount: _msgs.length,
        itemBuilder: (_, i) {
          final m = _msgs[i];
          final p = Profiles.get(m['user_id'] as String?);
          if (m['kind'] == 'system') {
            return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('${m['body']}', style: const TextStyle(color: C.gold, fontSize: 12)));
          }
          return Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: m['user_id'] == myId ? null : () => _userSheet(m['user_id'] as String, null),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .38), borderRadius: BorderRadius.circular(14)),
                child: Text.rich(TextSpan(children: [
                  WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: const EdgeInsets.only(right: 5), child: LevelBadge((p?['wealth_level'] as num?)?.toInt() ?? 1))),
                  TextSpan(text: '${p?['username'] ?? '…'}: ', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 13)),
                  TextSpan(text: '${m['body'] ?? ''}', style: const TextStyle(fontSize: 13)),
                ])),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bottomBar() {
    final onSeat = _mySeat != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: _input,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              maxLength: 200,
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Say hi…',
                filled: true,
                fillColor: Colors.black45,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: C.gold)),
                suffixIcon: IconButton(icon: const Icon(Icons.send, size: 18, color: C.gold), onPressed: _send),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (onSeat && _rtc != null)
          ValueListenableBuilder<bool>(
            valueListenable: _rtc!.micOn,
            builder: (_, on, __) => _round(on ? Icons.mic : Icons.mic_off, on ? C.emerald : Colors.black45, () => _rtc!.setMic(!on)),
          )
        else
          _round(Icons.event_seat, Colors.black45, () {
            final free = _seats.where((s) => (s['seat'] as num) > 0 && s['user_id'] == null && s['locked'] != true).firstOrNull;
            if (free == null) {
              toast(context, 'All seats are taken');
            } else {
              _takeSeat((free['seat'] as num).toInt());
            }
          }),
        const SizedBox(width: 8),
        Container(
          decoration: const BoxDecoration(gradient: C.goldGrad, shape: BoxShape.circle),
          child: IconButton(onPressed: () => _openGifts(), icon: const Icon(Icons.card_giftcard, color: Color(0xFF1A1206))),
        ),
      ]),
    );
  }

  Widget _round(IconData icon, Color bg, VoidCallback onTap) => Material(
        color: bg,
        shape: const CircleBorder(),
        child: IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white)),
      );
}

class GiftSheet extends StatefulWidget {
  const GiftSheet({super.key, required this.roomId, required this.gifts, required this.people, required this.preselect});
  final int? roomId;
  final List<Map<String, dynamic>> gifts;
  final List<String> people;
  final String preselect;
  @override
  State<GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<GiftSheet> {
  late final Set<String> _to = {widget.preselect};
  String _tier = 'classic';
  Map<String, dynamic>? _gift;
  int _qty = 1;
  bool _busy = false;

  static const tiers = [('classic', 'Classic'), ('luxury', 'Luxury'), ('exclusive', 'Exclusive'), ('event', 'Event')];

  Future<void> _send() async {
    final g = _gift;
    if (g == null) return;
    final total = (g['price'] as num).toInt() * _qty * _to.length;
    if (total > App.i.coins.value) {
      toast(context, 'Not enough coins', bad: true);
      Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('send_gift', {'p_room': widget.roomId, 'p_receivers': _to.toList(), 'p_gift': g['id'], 'p_qty': _qty}) as Map);
      App.i.coins.value = (r['coins'] as num).toInt();
      if (r['level_up'] == true && mounted) toast(context, 'Level up! You are now level ${r['level']}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.gifts.where((g) => g['tier'] == _tier).toList();
    final exclusive = _gift?['tier'] == 'exclusive';
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .62,
        child: Column(children: [
          SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final id in widget.people)
                GestureDetector(
                  onTap: () => setState(() => _to.contains(id) ? (_to.length > 1 ? _to.remove(id) : null) : _to.add(id)),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Column(children: [
                      Avatar(profile: Profiles.get(id), size: 40, ring: _to.contains(id) ? C.gold : null),
                      SizedBox(width: 54, child: Text('${Profiles.get(id)?['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))),
                    ]),
                  ),
                ),
            ]),
          ),
          Row(children: [
            for (final t in tiers)
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _tier = t.$1),
                  child: Text(t.$2, style: TextStyle(color: _tier == t.$1 ? C.gold : C.mute, fontWeight: _tier == t.$1 ? FontWeight.w800 : FontWeight.w500)),
                ),
              ),
          ]),
          Expanded(
            child: list.isEmpty
                ? const EmptyState('No gifts here right now', icon: Icons.card_giftcard)
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: .78, mainAxisSpacing: 6, crossAxisSpacing: 6),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final g = list[i];
                      final sel = _gift?['id'] == g['id'];
                      return GestureDetector(
                        onTap: () => setState(() {
                          _gift = g;
                          if (g['tier'] == 'exclusive') _qty = 1;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: sel ? const Color(0xFF3A2E17) : C.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: sel ? C.gold : C.line),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            AnimatedScale(scale: sel ? 1.15 : 1, duration: const Duration(milliseconds: 180), child: GiftIcon(gift: g, size: 38)),
                            const SizedBox(height: 6),
                            Text('${g['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                            CoinText(compact(g['price'] as num), size: 10),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(children: [
              ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(compact(c))),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                child: const Text('Top up', style: TextStyle(color: C.gold, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              for (final q in const [1, 10, 99])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('×$q'),
                    selected: _qty == q,
                    onSelected: exclusive && q != 1 ? null : (_) => setState(() => _qty = q),
                  ),
                ),
              GoldButton(label: 'Send', expand: false, busy: _busy, onTap: _gift == null ? null : _send),
            ]),
          ),
        ]),
      ),
    );
  }
}
