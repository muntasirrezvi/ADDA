import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Who is in the room right now, and who left in the last 24 hours.
Future<void> showRoomPeople(BuildContext context, {required int roomId, required void Function(String uid) onTapUser}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      maxChildSize: .92,
      builder: (ctx, scroll) => _People(roomId: roomId, scroll: scroll, onTapUser: (uid) {
        Navigator.pop(ctx);
        onTapUser(uid);
      }),
    ),
  );
}

class _People extends StatefulWidget {
  const _People({required this.roomId, required this.scroll, required this.onTapUser});
  final int roomId;
  final ScrollController scroll;
  final void Function(String uid) onTapUser;
  @override
  State<_People> createState() => _PeopleState();
}

class _PeopleState extends State<_People> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _active = [], _left = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('room_people', {'p_room': widget.roomId}) as Map);
      _active = List<Map<String, dynamic>>.from((r['active'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      _left = List<Map<String, dynamic>>.from((r['left'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _ago(String? iso) {
    final t = DateTime.tryParse('$iso')?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }

  Widget _row(Map<String, dynamic> p, {required bool here}) {
    final tags = <Widget>[
      if (p['owner'] == true) const HostTag(small: true),
      if (here && p['seat'] != null && p['owner'] != true)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: C.emerald.withValues(alpha: .2), borderRadius: BorderRadius.circular(8)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.mic, size: 10, color: C.emerald), SizedBox(width: 2), Text('On mic', style: TextStyle(fontSize: 10, color: C.emerald))]),
        ),
    ];
    return ListTile(
      onTap: () => widget.onTapUser(p['id'] as String),
      leading: Stack(clipBehavior: Clip.none, children: [
        Opacity(opacity: here ? 1 : .55, child: Avatar(profile: p, size: 44)),
        if (here)
          Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF3DDC84), border: Border.all(color: C.bg, width: 2)))),
      ]),
      title: Row(children: [
        Flexible(child: Text('${p['username']}', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: here ? C.text : C.mute))),
        const SizedBox(width: 6),
        LevelBadge((p['wealth_level'] as num?)?.toInt() ?? 1),
        for (final t in tags) Padding(padding: const EdgeInsets.only(left: 5), child: t),
      ]),
      subtitle: Text(here ? 'In the room · joined ${_ago(p['joined_at'] as String?)}' : 'Left ${_ago(p['left_at'] as String?)}', style: const TextStyle(color: C.mute, fontSize: 12)),
      trailing: Text('ID ${p['public_id']}', style: const TextStyle(color: C.mute, fontSize: 11)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 8),
      Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Row(children: [Text('People', style: serif(22)), const Spacer(), IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: C.mute))])),
      TabBar(
        controller: _tabs,
        indicatorColor: C.gold,
        labelColor: C.gold,
        unselectedLabelColor: C.mute,
        tabs: [Tab(text: 'In the room (${_active.length})'), Tab(text: 'Left (${_left.length})')],
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: C.gold))
            : TabBarView(controller: _tabs, children: [
                _active.isEmpty
                    ? const EmptyState('Nobody here right now', icon: Icons.people_outline)
                    : ListView(controller: widget.scroll, children: [for (final p in _active) _row(p, here: true)]),
                _left.isEmpty
                    ? const EmptyState('Nobody has left in the last 24 hours', icon: Icons.logout)
                    : ListView(children: [for (final p in _left) _row(p, here: false)]),
              ]),
      ),
    ]);
  }
}
