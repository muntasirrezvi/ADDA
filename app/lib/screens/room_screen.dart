import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/active_room.dart';
import '../services/api.dart';
import '../services/background.dart';
import '../services/presence.dart';
import '../services/rtc.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/entry_fx.dart';
import '../widgets/gift_fx.dart';
import 'create_room.dart';
import 'games.dart';
import 'party_games.dart';
import 'profile_screen.dart';
import 'room_people.dart';
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
  static final _noTalk = ValueNotifier<Set<int>>(<int>{});
  ActiveRoom? _r;
  String? _error;
  final _scroll = ScrollController();
  final _input = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _joinSub;
  final List<Map<String, dynamic>> _entries = [];
  int _lastLen = 0;
  Map<String, dynamic>? _roles;
  final Map<int, GlobalKey> _seatKeys = {};

  /// Screen position of the seat someone is sitting on (for gifts flying to them).
  Offset? _seatCenter(String uid) {
    final s = _seats.where((x) => x['user_id'] == uid).firstOrNull;
    if (s == null) return null;
    final box = _seatKeys[(s['seat'] as num).toInt()]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  int get _id => widget.roomId;
  Map<String, dynamic>? get _room => _r?.room;
  List<Map<String, dynamic>> get _seats => _r?.seats ?? const [];
  List<Map<String, dynamic>> get _msgs => _r?.msgs ?? const [];
  List<Map<String, dynamic>> get _gifts => _r?.gifts ?? const [];
  String? get _themeImage => _r?.themeImage;
  bool get _isAdmin => _r?.isAdmin ?? false;
  bool get _following => _r?.following ?? false;
  RtcSession? get _rtc => _r?.rtc;
  bool get _isOwner => _room?['owner_id'] == myId;
  Map<String, dynamic>? get _mySeat => _seats.where((s) => s['user_id'] == myId).firstOrNull;

  @override
  void initState() {
    super.initState();
    ActiveRoom.screenOpen.value = true;
    _open();
  }

  Future<void> _open({String? password}) async {
    try {
      final r = await ActiveRoom.enter(_id, password: password);
      _attach(r);
      // once per app session: may the room keep running when the app is in the background?
      if (mounted && await BackgroundAudio.askForSession(context)) {
        await BackgroundAudio.start('${r.room?['name'] ?? 'Voice room'}', micOn: r.mySeat != null && (r.rtc?.micOn.value ?? false));
      }
    } on RoomPasswordNeeded {
      if (!mounted) return;
      final pw = await askText(context, 'Private room', hint: 'Room password', number: true, obscure: true);
      if (pw != null && pw.isNotEmpty) return _open(password: pw);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    }
  }

  void _attach(ActiveRoom r) {
    if (!mounted) return;
    _r = r;
    r.addListener(_changed);
    r.closedReason.addListener(_closed);
    _joinSub = r.joins.stream.listen(_showEntry);
    r.stage.seatPos = _seatCenter;
    _loadRoles();
    setState(() {});
    _toBottom();
    if (r.voiceError != null) toast(context, 'Voice is unavailable: ${r.voiceError}', bad: true);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_msgs.length != _lastLen) {
      _lastLen = _msgs.length;
      _toBottom();
    }
  }

  void _closed() {
    final why = _r?.closedReason.value;
    if (why == null || !mounted) return;
    toast(context, why);
    Navigator.of(context).maybePop();
  }

  // entrances play one after another
  void _showEntry(Map<String, dynamic> row) {
    if (!mounted || _entries.length > 8) return;
    Profiles.load([row['user_id'] as String?]).then((_) {
      if (mounted) setState(() => _entries.add(row));
    });
  }

  Future<void> _loadRoles() async {
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('room_roles', {'p_room': _id}) as Map);
      if (mounted) setState(() => _roles = r);
    } catch (_) {}
  }

  bool _isRoomAdmin(String uid) => ((_roles?['admins'] as List?) ?? const []).any((a) => (a as Map)['id'] == uid);

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  /// Minimise: keep talking and listening while you use the rest of the app.
  void _minimise() => Navigator.of(context).maybePop();

  Future<void> _leave() async {
    await _r?.leave();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    ActiveRoom.screenOpen.value = false;
    _r?.removeListener(_changed);
    _r?.closedReason.removeListener(_closed);
    _joinSub?.cancel();
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
              if (uid == _room?['owner_id']) const Padding(padding: EdgeInsets.only(left: 6), child: HostTag()),
              const SizedBox(width: 6),
              LevelBadge((p?['wealth_level'] as num?)?.toInt() ?? 1),
            ]),
            Text('ID ${p?['public_id'] ?? ''}', style: const TextStyle(color: C.mute, fontSize: 12)),
            const SizedBox(height: 4),
            PresenceText(uid),
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
            if (_isAdmin && uid != _room?['owner_id']) ...[
              const SizedBox(height: 12),
              const Align(alignment: Alignment.centerLeft, child: Text('Room admin tools', style: TextStyle(color: C.mute, fontSize: 12, fontWeight: FontWeight.w700))),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (seat != null && seat != 0 && seatRow?['muted'] != true)
                  _tool(Icons.mic_off, 'Mute', () { Navigator.pop(ctx); _seatAction(sn, 'mute'); }),
                if (seat != null && seat != 0 && seatRow?['muted'] == true)
                  _tool(Icons.mic, 'Unmute', () { Navigator.pop(ctx); _seatAction(sn, 'unmute'); }),
                if (seat != null && seat != 0)
                  _tool(Icons.event_seat, 'Take off mic', () { Navigator.pop(ctx); _seatAction(sn, 'remove'); }),
                if (_isOwner && !_isRoomAdmin(uid))
                  _tool(Icons.shield, 'Make room admin', () async {
                    Navigator.pop(ctx);
                    if (await attempt(context, () => App.i.rpc('set_room_admin', {'p_room': _id, 'p_user': uid, 'p_admin': true}), ok: '${p?['username'] ?? 'They'} is now a room admin')) _loadRoles();
                  }),
                if (_isOwner && _isRoomAdmin(uid))
                  _tool(Icons.remove_moderator, 'Remove admin', () async {
                    Navigator.pop(ctx);
                    if (await attempt(context, () => App.i.rpc('set_room_admin', {'p_room': _id, 'p_user': uid, 'p_admin': false}), ok: 'No longer a room admin')) _loadRoles();
                  }),
                _tool(Icons.block, 'Block from room', () async {
                  Navigator.pop(ctx);
                  if (await confirm(context, 'Block ${p?['username']}?', 'They are removed and cannot come back until unblocked.', yes: 'Block', danger: true)) {
                    if (mounted && await attempt(context, () => App.i.rpc('kick_from_room', {'p_room': _id, 'p_user': uid}), ok: 'Blocked from the room')) _loadRoles();
                  }
                }, danger: true),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => Material(
        color: danger ? C.ruby.withValues(alpha: .15) : Colors.white10,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: danger ? C.ruby : C.gold),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: danger ? C.ruby : C.text, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
      );

  /// Room admins and blocked people, for the owner and room admins.
  Future<void> _adminsPanel() async {
    await _loadRoles();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final admins = ((_roles?['admins'] as List?) ?? const []).cast<Map>();
          final blocked = ((_roles?['blocked'] as List?) ?? const []).cast<Map>();
          Widget person(Map p, Widget action) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(profile: Map<String, dynamic>.from(p), size: 38),
                title: Text('${p['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('ID ${p['public_id'] ?? ''}', style: const TextStyle(color: C.mute, fontSize: 12)),
                trailing: action,
              );
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .75),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                Text('Room admins', style: serif(20)),
                const Text('Room admins can mute or unmute people, take them off the mic, lock seats and block people. Only the owner can add or remove admins.',
                    style: TextStyle(color: C.mute, fontSize: 12)),
                const SizedBox(height: 6),
                if (admins.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('No room admins yet. Tap someone in the room and choose "Make room admin".', style: TextStyle(color: C.mute))),
                for (final a in admins)
                  person(a, _isOwner
                      ? TextButton(
                          onPressed: () async {
                            if (await attempt(context, () => App.i.rpc('set_room_admin', {'p_room': _id, 'p_user': a['id'], 'p_admin': false}), ok: 'Removed as admin')) {
                              await _loadRoles();
                              set(() {});
                            }
                          },
                          child: const Text('Remove', style: TextStyle(color: C.ruby)),
                        )
                      : const Icon(Icons.shield, color: C.gold)),
                const SizedBox(height: 14),
                Text('Blocked', style: serif(20)),
                if (blocked.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Nobody is blocked.', style: TextStyle(color: C.mute))),
                for (final b in blocked)
                  person(b, TextButton(
                    onPressed: () async {
                      if (await attempt(context, () => App.i.rpc('room_unblock', {'p_room': _id, 'p_user': b['id']}), ok: 'Unblocked')) {
                        await _loadRoles();
                        set(() {});
                      }
                    },
                    child: const Text('Unblock', style: TextStyle(color: C.gold)),
                  )),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openGifts({String? preselect}) async {
    // everyone who can receive: people on mic first, then the host, then everyone else listening in the room
    final people = <String>[];
    void add(String? id) {
      if (id != null && id != myId && !people.contains(id)) people.add(id);
    }

    add(preselect);
    for (final s in _seats) {
      add(s['user_id'] as String?);
    }
    add(_room?['owner_id'] as String?);
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('room_people', {'p_room': _id}) as Map);
      for (final e in (r['active'] as List? ?? const [])) {
        add((e as Map)['id'] as String?);
      }
    } catch (_) {}
    await Profiles.load(people);
    if (!mounted) return;
    if (people.isEmpty) {
      toast(context, 'Nobody else is in the room yet');
      return;
    }
    if (_gifts.isEmpty) await _r?.reloadGifts();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GiftSheet(roomId: _id, gifts: _gifts, people: people, preselect: preselect ?? people.first),
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
            _r!.following = !_r!.following;
            setState(() {});
          })),
      if (_isOwner)
        ('Edit room, cover and theme', Icons.edit, () async {
          final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RoomEditor(room: _room)));
          if (changed == true) {
            await _r?.refreshRoom();
            await _r?.loadExtras();
            if (mounted) setState(() {});
          }
        }),
      if (_isAdmin)
        ('Mute everyone on the mic', Icons.mic_off, () => attempt(context, () => App.i.rpc('room_mute_all', {'p_room': _id, 'p_muted': true}), ok: 'Everyone is muted')),
      if (_isAdmin)
        ('Unmute everyone', Icons.mic, () => attempt(context, () => App.i.rpc('room_mute_all', {'p_room': _id, 'p_muted': false}), ok: 'Everyone can talk again')),
      if (_isAdmin)
        ('Room admins & blocked people', Icons.admin_panel_settings, _adminsPanel),
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
          if (ok) await _leave();
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
    final others = _seats.where((s) => (s['seat'] as num) > 0 && (s['seat'] as num) <= seatsCount).toList()
      ..sort((a, b) => (a['seat'] as num).compareTo(b['seat'] as num));

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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: LayoutBuilder(builder: (context, box) {
                // seats numbered No.1, No.2 … row by row from the top; size follows the screen width
                final cell = box.maxWidth / 4;
                final avatar = (cell - 26).clamp(36.0, 58.0);
                return Wrap(children: [
                  for (final s in others) SizedBox(width: cell, child: Padding(padding: const EdgeInsets.only(bottom: 6), child: _seatView(s, avatar: avatar))),
                ]);
              }),
            ),
            Expanded(child: _chat()),
            _bottomBar(),
          ]),
        ),
        if (_entries.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.of(context).padding.top + 54,
            bottom: 0,
            child: EntryShow(key: ValueKey(_entries.first['id'] ?? _entries.first.hashCode), row: _entries.first, onDone: () {
              if (mounted) setState(() => _entries.removeAt(0));
            }),
          ),
        if (_r != null) Positioned.fill(child: PartyLayer(key: ValueKey('party${_r!.id}'), room: _r!)),
        if (_r != null) Positioned.fill(child: GiftStage(controller: _r!.stage)),
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
        GestureDetector(
          onTap: () => showRoomPeople(context, roomId: _id, onTapUser: (uid) => _userSheet(uid, _seats.where((s) => s['user_id'] == uid).firstOrNull?['seat'] as int?)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white24)),
            child: Row(children: [
              const Icon(Icons.people, size: 14),
              const SizedBox(width: 4),
              Text(compact(r['listeners'] as num? ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right, size: 14, color: Colors.white54),
            ]),
          ),
        ),
        IconButton(onPressed: _menu, icon: const Icon(Icons.more_horiz)),
        IconButton(tooltip: 'Minimise', onPressed: _minimise, icon: const Icon(Icons.close_fullscreen)),
        IconButton(tooltip: 'Leave room', onPressed: _leave, icon: const Icon(Icons.power_settings_new, color: C.ruby)),
      ]),
    );
  }

  Widget _seatView(Map<String, dynamic> s, {bool big = false, double? avatar}) {
    final uid = s['user_id'] as String?;
    final p = Profiles.get(uid);
    final seat = (s['seat'] as num).toInt();
    final size = avatar ?? (big ? 74.0 : 54.0);
    return GestureDetector(
      onTap: () => _tapSeat(s),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ValueListenableBuilder<Set<int>>(
          key: _seatKeys.putIfAbsent(seat, () => GlobalKey()),
          valueListenable: _rtc?.talking ?? _noTalk,
          builder: (_, talking, __) {
            final pid = (p?['public_id'] as num?)?.toInt();
            final speaking = uid != null && s['muted'] != true && ((uid == myId && talking.contains(0)) || (pid != null && talking.contains(pid)));
            return SpeakingSeat(
              speaking: speaking,
              size: size,
              host: seat == 0,
              crown: uid != null && uid == _room?['owner_id'],
              child: uid == null
                  ? Container(
                      width: size,
                      height: size,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black38),
                      child: Icon(s['locked'] == true ? Icons.lock : Icons.event_seat, color: Colors.white54, size: size * .4),
                    )
                  : Avatar(profile: p, size: size),
              muted: uid != null && s['muted'] == true,
            );
          },
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: size + 22,
          child: Text(
            uid == null ? (seat == 0 ? 'Host' : 'No.$seat') : '${p?['username'] ?? ''}',
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
            final joined = m['body'] == 'joined the room';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text.rich(TextSpan(children: [
                if (joined) TextSpan(text: '${p?['username'] ?? 'Someone'} ', style: const TextStyle(color: Color(0xFF7CF5B5), fontWeight: FontWeight.w800, fontSize: 12)),
                TextSpan(text: '${m['body']}', style: TextStyle(color: joined ? const Color(0xFF7CF5B5) : C.gold, fontSize: 12)),
              ])),
            );
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
                  if (m['user_id'] == _room?['owner_id']) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: EdgeInsets.only(right: 5), child: HostTag(small: true))),
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
        _round(Icons.sports_esports, const Color(0xFF6A3DE8), () => openGames(context, roomId: _id)),
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

  static const tiers = [('classic', 'Gifts'), ('luxury', 'Luxury'), ('exclusive', 'Exclusive'), ('event', 'Event')];
  static const _panel = Color(0xFF141019);

  @override
  void initState() {
    super.initState();
    // a gift is chosen from the start, so Send always works
    _gift = widget.gifts.where((g) => g['tier'] == _tier).firstOrNull ?? widget.gifts.firstOrNull;
    if (_gift != null) _tier = '${_gift!['tier']}';
  }

  bool get _all => widget.people.every(_to.contains);

  Future<void> _send() async {
    final g = _gift;
    if (g == null || _to.isEmpty) return;
    final total = (g['price'] as num).toInt() * _qty * _to.length;
    if (total > App.i.coins.value) {
      toast(context, 'Not enough coins', bad: true);
      Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
      return;
    }
    setState(() => _busy = true);
    try {
      // the server allows up to 17 people per gift
      final to = _to.take(17).toList();
      final r = Map<String, dynamic>.from(await App.i.rpc('send_gift', {'p_room': widget.roomId, 'p_receivers': to, 'p_gift': g['id'], 'p_qty': _qty}) as Map);
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
    final mq = MediaQuery.of(context);
    return MediaQuery(
      // the panel keeps its layout even with very large system fonts
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.15)),
      child: Container(
        decoration: const BoxDecoration(color: _panel, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: math.min(mq.size.height * .62, 520),
            child: Column(children: [
              // who receives
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ListView(scrollDirection: Axis.horizontal, children: [
                        for (final id in widget.people)
                          GestureDetector(
                            onTap: () => setState(() => _to.contains(id) ? (_to.length > 1 ? _to.remove(id) : null) : _to.add(id)),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(clipBehavior: Clip.none, children: [
                                Opacity(opacity: _to.contains(id) ? 1 : .55, child: Avatar(profile: Profiles.get(id), size: 42, ring: _to.contains(id) ? C.gold : null)),
                                if (_to.contains(id))
                                  const Positioned(right: -2, bottom: -2, child: CircleAvatar(radius: 8, backgroundColor: C.gold, child: Icon(Icons.check, size: 11, color: Colors.black))),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() {
                      if (_all) {
                        _to
                          ..clear()
                          ..add(widget.people.first);
                      } else {
                        _to.addAll(widget.people);
                      }
                    }),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _all ? C.gold : Colors.white12),
                      child: Text('All', style: TextStyle(color: _all ? Colors.black : Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                    ),
                  ),
                ]),
              ),
              // tabs
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6), children: [
                  for (final t in tiers)
                    GestureDetector(
                      onTap: () => setState(() {
                        _tier = t.$1;
                        _gift = widget.gifts.where((g) => g['tier'] == t.$1).firstOrNull ?? _gift;
                        if (_gift?['tier'] == 'exclusive') _qty = 1;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(t.$2, style: TextStyle(color: _tier == t.$1 ? Colors.white : Colors.white54, fontWeight: _tier == t.$1 ? FontWeight.w800 : FontWeight.w500, fontSize: 14)),
                          const SizedBox(height: 3),
                          AnimatedContainer(duration: const Duration(milliseconds: 200), width: _tier == t.$1 ? 18 : 0, height: 3, decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(2))),
                        ]),
                      ),
                    ),
                ]),
              ),
              const Divider(height: 1, color: Colors.white10),
              // gifts
              Expanded(
                child: list.isEmpty
                    ? const EmptyState('No gifts here right now', icon: Icons.card_giftcard)
                    : LayoutBuilder(builder: (context, box) {
                        final cols = (box.maxWidth / 88).floor().clamp(3, 6);
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 104, mainAxisSpacing: 6, crossAxisSpacing: 6),
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
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                                decoration: BoxDecoration(
                                  color: sel ? const Color(0xFF2A2033) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: sel ? C.gold : Colors.transparent, width: 1.5),
                                ),
                                child: Column(children: [
                                  Expanded(child: AnimatedScale(scale: sel ? 1.12 : 1, duration: const Duration(milliseconds: 160), child: GiftIcon(gift: g, size: 52))),
                                  Text('${g['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                  FittedBox(child: CoinText(compact(g['price'] as num), size: 10)),
                                ]),
                              ),
                            );
                          },
                        );
                      }),
              ),
              // balance · quantity · send
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
                child: Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                      child: Row(children: [
                        Flexible(child: ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: CoinText(grouped(c))))),
                        const SizedBox(width: 6),
                        const Text('Recharge ›', style: TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 12)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // quantity + send joined like one button
                  Container(
                    height: 38,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(19), border: Border.all(color: C.gold)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      PopupMenuButton<int>(
                        enabled: !exclusive,
                        initialValue: _qty,
                        onSelected: (q) => setState(() => _qty = q),
                        color: const Color(0xFF231B2B),
                        itemBuilder: (_) => [for (final q in const [99, 10, 1]) PopupMenuItem(value: q, child: Text('×$q', style: const TextStyle(fontWeight: FontWeight.w800)))],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('×$_qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                            Icon(Icons.keyboard_arrow_up, size: 18, color: exclusive ? Colors.white24 : Colors.white70),
                          ]),
                        ),
                      ),
                      GestureDetector(
                        onTap: _busy || _gift == null ? null : _send,
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(gradient: C.goldGrad, borderRadius: BorderRadius.circular(19)),
                          child: _busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Text('Send', style: TextStyle(color: Color(0xFF1A1206), fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
              if (_gift != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Total ${grouped((_gift!['price'] as num) * _qty * math.min(_to.length, 17))} coins · ${_to.length} ${_to.length == 1 ? 'person' : 'people'}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Seat avatar with a live "talking" animation: ripples around the avatar and a bouncing mic badge.
class SpeakingSeat extends StatefulWidget {
  const SpeakingSeat({super.key, required this.speaking, required this.size, required this.child, this.host = false, this.muted = false, this.crown = false});
  final bool crown;
  final bool speaking;
  final double size;
  final Widget child;
  final bool host;
  final bool muted;
  @override
  State<SpeakingSeat> createState() => _SpeakingSeatState();
}

class _SpeakingSeatState extends State<SpeakingSeat> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    if (widget.speaking) _a.repeat();
  }

  @override
  void didUpdateWidget(covariant SpeakingSeat old) {
    super.didUpdateWidget(old);
    if (widget.speaking && !_a.isAnimating) _a.repeat();
    if (!widget.speaking && _a.isAnimating) {
      _a.stop();
      _a.value = 0;
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size + 18;
    return SizedBox(
      width: box,
      height: box,
      child: AnimatedBuilder(
        animation: _a,
        builder: (_, __) => Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          if (widget.speaking)
            for (final k in const [0.0, 0.5])
              Builder(builder: (_) {
                final t = (_a.value + k) % 1.0;
                return Container(
                  width: widget.size + 4 + t * 16,
                  height: widget.size + 4 + t * 16,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.gold.withValues(alpha: (1 - t) * .8), width: 2.5)),
                );
              }),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: widget.speaking ? C.gold : (widget.host ? C.gold2 : Colors.white24), width: 2),
              boxShadow: widget.speaking ? [BoxShadow(color: C.gold.withValues(alpha: .55), blurRadius: 14, spreadRadius: 1)] : null,
            ),
            child: widget.child,
          ),
          if (widget.crown)
            Positioned(
              top: -widget.size * .2,
              child: Transform.rotate(
                angle: -.12,
                child: Image.asset('assets/games/crown.webp', width: widget.size * .62, filterQuality: FilterQuality.medium),
              ),
            ),
          if (widget.crown) const Positioned(bottom: 0, child: HostTag(small: true)),
          if (widget.speaking || widget.muted)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(color: widget.muted ? C.ruby : C.emerald, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black54)),
                child: widget.muted
                    ? const Icon(Icons.mic_off, size: 11, color: Colors.white)
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.mic, size: 11, color: Colors.white),
                        for (var i = 0; i < 3; i++)
                          Container(
                            margin: const EdgeInsets.only(left: 1.5),
                            width: 2,
                            height: 3 + 7 * (0.5 + 0.5 * math.sin((_a.value * 2 * math.pi * 2) + i * 1.3)).abs(),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1)),
                          ),
                      ]),
              ),
            ),
        ]),
      ),
    );
  }
}
