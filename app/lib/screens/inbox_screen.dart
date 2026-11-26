import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api.dart';
import '../services/presence.dart';
import '../services/calls.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';
import 'room_screen.dart';
import 'wallet_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});
  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    _load();
    _ch = db
        .channel('inbox:$myId')
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'direct_messages', callback: (_) => _load())
        .subscribe();
  }

  @override
  void dispose() {
    if (_ch != null) db.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> _load() async {
    final me = myId;
    if (me == null) return;
    try {
      final rows = await db.from('direct_messages').select().or('sender_id.eq.$me,receiver_id.eq.$me').order('id', ascending: false).limit(300);
      final seen = <String>{};
      final threads = <Map<String, dynamic>>[];
      final unread = <String, int>{};
      for (final m in rows) {
        final other = m['sender_id'] == me ? m['receiver_id'] as String : m['sender_id'] as String;
        if (m['receiver_id'] == me && m['read_at'] == null) unread[other] = (unread[other] ?? 0) + 1;
        if (seen.add(other)) threads.add({...m, 'other': other});
      }
      for (final t in threads) {
        t['unread'] = unread[t['other']] ?? 0;
      }
      await Profiles.load(threads.map((t) => t['other'] as String));
      if (mounted) setState(() => _threads = threads);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _preview(Map<String, dynamic> m) {
    switch (m['kind']) {
      case 'call':
        return '📞 ${m['body'] ?? 'Call'}';
      case 'voice':
        return '🎤 Voice message';
      case 'gift':
        return '🎁 ${m['body'] ?? 'Gift'}';
      default:
        return '${m['sender_id'] == myId ? 'You: ' : ''}${m['body'] ?? ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox'), actions: [
        IconButton(
          icon: ValueListenableBuilder<int>(valueListenable: App.i.unread, builder: (_, n, __) => Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.notifications_none))),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        ),
      ]),
      body: RefreshIndicator(
        color: C.gold,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: C.gold))
            : _threads.isEmpty
                ? ListView(children: const [EmptyState('No messages yet. Say hi to someone from their profile.', icon: Icons.chat_bubble_outline)])
                : ListView.separated(
                    itemCount: _threads.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                    itemBuilder: (_, i) {
                      final t = _threads[i];
                      final p = Profiles.get(t['other'] as String);
                      final unread = t['unread'] as int;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Avatar(profile: p, size: 48),
                        title: Text('${p?['username'] ?? ''}', style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600)),
                        subtitle: Text(_preview(t), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread > 0 ? C.text : C.mute)),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(shortTime('${t['created_at']}'), style: const TextStyle(color: C.mute, fontSize: 11)),
                          if (unread > 0)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: C.ruby, borderRadius: BorderRadius.circular(10)),
                              child: Text('$unread', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                        ]),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(userId: t['other'] as String)));
                          _load();
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

String shortTime(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (now.difference(d).inDays < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
  return '${d.day}/${d.month}';
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.userId});
  final String userId;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgs = <Map<String, dynamic>>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  RealtimeChannel? _ch;
  Map<String, dynamic>? _other;

  String get _o => widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
    _ch = db
        .channel('dm:${myId}_$_o')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'direct_messages',
          callback: (p) {
            final m = p.newRecord;
            final ours = (m['sender_id'] == _o && m['receiver_id'] == myId) || (m['sender_id'] == myId && m['receiver_id'] == _o);
            if (!ours || _msgs.any((x) => x['id'] == m['id'])) return;
            setState(() => _msgs.insert(0, m));
            if (m['receiver_id'] == myId) _markRead();
          },
        )
        .subscribe();
  }

  Future<void> _load() async {
    _other = await Profiles.fetch(_o);
    final me = myId!;
    final rows = await db
        .from('direct_messages')
        .select()
        .or('and(sender_id.eq.$me,receiver_id.eq.$_o),and(sender_id.eq.$_o,receiver_id.eq.$me)')
        .order('id', ascending: false)
        .limit(100);
    if (!mounted) return;
    setState(() => _msgs
      ..clear()
      ..addAll(rows));
    _markRead();
  }

  Future<void> _markRead() async {
    try {
      await db.from('direct_messages').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('receiver_id', myId!).eq('sender_id', _o).isFilter('read_at', null);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      final row = await db.from('direct_messages').insert({'sender_id': myId, 'receiver_id': _o, 'body': text, 'kind': 'text'}).select().single();
      if (mounted && !_msgs.any((x) => x['id'] == row['id'])) setState(() => _msgs.insert(0, row));
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
      _input.text = text;
    }
  }

  @override
  void dispose() {
    if (_ch != null) db.removeChannel(_ch!);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _other;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: _o))),
          child: Row(children: [
            Avatar(profile: p, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${p?['username'] ?? ''}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                PresenceText(_o, size: 11),
              ]),
            ),
          ]),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.call, color: C.gold), onPressed: () => CallService.i.call(context, _o, video: false)),
          IconButton(icon: const Icon(Icons.videocam, color: C.gold), onPressed: () => CallService.i.call(context, _o, video: true)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length,
            itemBuilder: (_, i) {
              final m = _msgs[i];
              final mine = m['sender_id'] == myId;
              if (m['kind'] == 'call') {
                return Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(('${m['body']}').contains('Video') ? Icons.videocam : Icons.call, size: 15, color: C.gold),
                      const SizedBox(width: 6),
                      Text('${m['body']}', style: const TextStyle(fontSize: 12, color: C.mute)),
                    ]),
                  ),
                );
              }
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .74),
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: mine ? C.goldGrad : null,
                    color: mine ? null : C.card,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(mine ? 18 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 18),
                    ),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${m['body'] ?? ''}', style: TextStyle(color: mine ? const Color(0xFF1A1206) : C.text)),
                    const SizedBox(height: 2),
                    Text(shortTime('${m['created_at']}') + (mine && m['read_at'] != null ? '  ✓✓' : ''), style: TextStyle(fontSize: 10, color: mine ? const Color(0x991A1206) : C.mute)),
                  ]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Message', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(gradient: C.goldGrad, shape: BoxShape.circle),
                child: IconButton(onPressed: _send, icon: const Icon(Icons.send, color: Color(0xFF1A1206))),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await db.from('notifications').select().eq('user_id', myId!).order('id', ascending: false).limit(100);
    _rows = List<Map<String, dynamic>>.from(rows);
    if (mounted) setState(() => _loading = false);
    try {
      await db.from('notifications').update({'read': true}).eq('user_id', myId!).eq('read', false);
      App.i.unread.value = 0;
    } catch (_) {}
  }

  IconData _icon(String? type) => switch (type) {
        'gift' => Icons.card_giftcard,
        'topup' || 'topup_order' => Icons.monetization_on,
        'call' => Icons.call,
        'donation' => Icons.volunteer_activism,
        'promo' => Icons.campaign,
        _ => Icons.notifications,
      };

  void _open(Map<String, dynamic> n) {
    final d = Map<String, dynamic>.from(n['data'] as Map? ?? {});
    if (d['room'] != null) {
      openRoom(context, (d['room'] as num).toInt());
    } else if (d['type'] == 'topup') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.gold))
          : _rows.isEmpty
              ? const EmptyState('Nothing yet', icon: Icons.notifications_none)
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = _rows[i];
                    final type = (n['data'] as Map?)?['type'] as String?;
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: const Color(0xFF3A2E17), child: Icon(_icon(type), color: C.gold, size: 20)),
                      title: Text('${n['title']}', style: TextStyle(fontWeight: n['read'] == true ? FontWeight.w500 : FontWeight.w800)),
                      subtitle: n['body'] == null ? null : Text('${n['body']}', style: const TextStyle(color: C.mute)),
                      trailing: Text(shortTime('${n['created_at']}'), style: const TextStyle(color: C.mute, fontSize: 11)),
                      onTap: () => _open(n),
                    );
                  },
                ),
    );
  }
}
