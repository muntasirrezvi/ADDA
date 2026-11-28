import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api.dart';
import '../services/tour.dart' show tourEnabled;
import '../theme.dart';
import '../widgets/common.dart';
import 'games_kit.dart';
import 'inbox_screen.dart';
import 'leaderboard_screen.dart';
import 'rewards.dart';
import 'room_screen.dart';
import 'wallet_screen.dart';

/// Cached homepage extras (templates, themes) so other screens can use them.
class HomeData {
  static Map<String, dynamic> feed = {};
  static List<Map<String, dynamic>> get templates => List<Map<String, dynamic>>.from(feed['templates'] ?? const []);
  static List<Map<String, dynamic>> get themes => List<Map<String, dynamic>>.from(feed['themes'] ?? const []);
  static String? templateImage(String? id) => templates.where((t) => t['id'] == id).map((t) => t['image_url'] as String?).firstOrNull;
  static Future<void> load() async {
    final r = await App.i.rpc('home_feed');
    feed = Map<String, dynamic>.from(r as Map);
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _rooms = <String, List<Map<String, dynamic>>>{};
  bool _loading = true;
  int _refreshes = 0;
  Timer? _auto;

  static const _tabKeys = ['hot', 'new', 'following'];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _loadRooms(_tabKeys[_tabs.index]);
    });
    _load();
    _auto = Timer.periodic(const Duration(seconds: 45), (_) => _loadRooms(_tabKeys[_tabs.index], quiet: true));
    // pop the reward calendar once per app start when today's reward is waiting
    if (!_rewardShown) {
      _rewardShown = true;
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && !tourEnabled) showDailyRewards(context, onlyIfReady: true);
      });
    }
  }

  static bool _rewardShown = false;

  @override
  void dispose() {
    _auto?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _refreshes++;
    try {
      await HomeData.load();
    } catch (_) {}
    await _loadRooms('hot');
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRooms(String tab, {bool quiet = false}) async {
    try {
      final r = await App.i.rpc('home_rooms', {'p_tab': tab, 'p_limit': 60});
      _rooms[tab] = List<Map<String, dynamic>>.from(r as List);
      if (mounted) setState(() {});
    } catch (e) {
      if (!quiet && mounted) toast(context, errText(e), bad: true);
    }
  }

  Future<void> _checkin() => showDailyRewards(context);

  void _banner(Map<String, dynamic> b) {
    final a = (b['action'] as String?) ?? '';
    if (a.startsWith('room:')) {
      final id = int.tryParse(a.substring(5));
      if (id != null) openRoom(context, id);
    } else if (a.startsWith('topup')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
    } else if (a.startsWith('url:')) {
      launchUrl(Uri.parse(a.substring(4)), mode: LaunchMode.externalApplication);
    } else if (a == 'leaderboard') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
    } else if (a == 'events') {
      _tabs.animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = List<String>.from(HomeData.feed['layout'] ?? const ['banners', 'events', 'rooms']);
    final banners = List<Map<String, dynamic>>.from(HomeData.feed['banners'] ?? const []);
    final events = List<Map<String, dynamic>>.from(HomeData.feed['events'] ?? const []);
    final tab = _tabKeys[_tabs.index];
    final rooms = _rooms[tab];

    final top = <Widget>[];
    for (final s in layout) {
      if (s == 'banners' && banners.isNotEmpty) top.add(SliverToBoxAdapter(child: _Banners(banners: banners, onTap: _banner)));
      if (s == 'banners') top.add(SliverToBoxAdapter(child: LeaderboardStrip(key: ValueKey(_refreshes))));
      if (s == 'events' && events.isNotEmpty) top.add(SliverToBoxAdapter(child: _Events(events: events, onChanged: _load)));
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: C.gold,
          onRefresh: _load,
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverAppBar(
                floating: true,
                titleSpacing: 16,
                title: ShaderMask(shaderCallback: (r) => C.goldGrad.createShader(r), child: Text('Adda', style: serif(30, color: Colors.white))),
                actions: [
                  IconButton(tooltip: 'Daily reward', onPressed: _checkin, icon: Floaty(amp: 2, child: art('coins_pile', size: 30))),
                  ValueListenableBuilder<int>(
                    valueListenable: App.i.coins,
                    builder: (_, c, __) => GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
                        child: Row(children: [CoinText(compact(c), size: 13), const SizedBox(width: 4), const Icon(Icons.add_circle, size: 16, color: C.gold)]),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                    icon: ValueListenableBuilder<int>(
                      valueListenable: App.i.unread,
                      builder: (_, n, __) => Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.notifications_none)),
                    ),
                  ),
                ],
              ),
              ...top,
              SliverPersistentHeader(pinned: true, delegate: _TabHeader(TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [Tab(text: 'Popular'), Tab(text: 'New'), Tab(text: 'Following')]))),
            ],
            body: _loading && rooms == null
                ? const Center(child: CircularProgressIndicator(color: C.gold))
                : (rooms == null || rooms.isEmpty)
                    ? ListView(children: [EmptyState(tab == 'following' ? 'Follow rooms you like and they show up here' : 'No live rooms yet. Start one!', icon: Icons.mic_none)])
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .78),
                        itemCount: rooms.length,
                        itemBuilder: (_, i) => RoomCard(room: rooms[i]),
                      ),
          ),
        ),
      ),
    );
  }
}

class _TabHeader extends SliverPersistentHeaderDelegate {
  _TabHeader(this.tabBar);
  final TabBar tabBar;
  @override
  double get minExtent => 46;
  @override
  double get maxExtent => 46;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: C.bg, child: tabBar);
  @override
  bool shouldRebuild(covariant _TabHeader old) => old.tabBar != tabBar;
}

class RoomCard extends StatelessWidget {
  const RoomCard({super.key, required this.room});
  final Map<String, dynamic> room;

  @override
  Widget build(BuildContext context) {
    final r = room;
    final listeners = (r['listeners'] as num?)?.toInt() ?? 0;
    return GestureDetector(
      onTap: () => openRoom(context, (r['id'] as num).toInt()),
      child: Container(
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: r['featured'] == true ? C.gold2 : C.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              CoverArt(imageUrl: r['cover_image'] as String?, template: (r['cover_template'] as String?) ?? 'lantern', radius: 17),
              const DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(17)), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87], stops: [.45, 1]))),
              Positioned(
                left: 8,
                top: 8,
                child: Row(children: [
                  if (r['featured'] == true) _chip('TOP', gold: true),
                  if (r['locked'] == true) _chip('', icon: Icons.lock),
                ]),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: _chip(compact(listeners), icon: Icons.graphic_eq),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Row(children: [
                  Avatar(profile: {'username': r['owner_name'], 'avatar_url': r['owner_avatar'], 'avatar_preset': r['owner_preset']}, size: 24),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${r['owner_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70))),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${r['topic']} · ${r['language']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.mute, fontSize: 11)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String text, {IconData? icon, bool gold = false}) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(gradient: gold ? C.goldGrad : null, color: gold ? null : Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, size: 12, color: gold ? const Color(0xFF1A1206) : Colors.white),
          if (icon != null && text.isNotEmpty) const SizedBox(width: 3),
          if (text.isNotEmpty) Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: gold ? const Color(0xFF1A1206) : Colors.white)),
        ]),
      );
}

class _Banners extends StatefulWidget {
  const _Banners({required this.banners, required this.onTap});
  final List<Map<String, dynamic>> banners;
  final void Function(Map<String, dynamic>) onTap;
  @override
  State<_Banners> createState() => _BannersState();
}

class _BannersState extends State<_Banners> {
  final _pc = PageController(viewportFraction: .92);
  Timer? _t;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_pc.hasClients || widget.banners.length < 2) return;
      _pc.animateToPage((_i + 1) % widget.banners.length, duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _pc.dispose();
    super.dispose();
  }

  Color _hex(String? h, Color f) {
    if (h == null || !h.startsWith('#') || h.length != 7) return f;
    return Color(int.parse('FF${h.substring(1)}', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 150,
        child: PageView.builder(
          controller: _pc,
          itemCount: widget.banners.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) {
            final b = widget.banners[i];
            final img = b['image_url'] as String?;
            return GestureDetector(
              onTap: () => widget.onTap(b),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: [_hex(b['color_from'], C.ruby), _hex(b['color_to'], C.bg)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Stack(fit: StackFit.expand, children: [
                  if (img != null && img.isNotEmpty) CachedNetworkImage(imageUrl: img, fit: BoxFit.cover),
                  if (img == null || img.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('${b['title']}', maxLines: 2, style: serif(22, color: Colors.white)),
                        if (b['subtitle'] != null) Text('${b['subtitle']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                        if (b['cta_label'] != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                            child: Text('${b['cta_label']}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ],
                      ]),
                    ),
                ]),
              ),
            );
          },
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < widget.banners.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.all(3),
            width: i == _i ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(color: i == _i ? C.gold : C.line, borderRadius: BorderRadius.circular(3)),
          ),
      ]),
    ]);
  }
}

class _Events extends StatelessWidget {
  const _Events({required this.events, required this.onChanged});
  final List<Map<String, dynamic>> events;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Section('Upcoming events'),
      SizedBox(
        height: 96,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final e = events[i];
            final at = DateTime.tryParse('${e['starts_at']}')?.toLocal();
            final going = e['me'] == true;
            return Container(
              width: 240,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${e['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${e['room']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.mute, fontSize: 12)),
                    if (at != null) Text('${_day(at)} · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')} · ${e['going']} going', style: const TextStyle(color: C.gold, fontSize: 11)),
                  ]),
                ),
                IconButton(
                  icon: Icon(going ? Icons.event_available : Icons.event, color: going ? C.emerald : C.gold),
                  onPressed: () => attempt(context, () async {
                    if (going) {
                      await db.from('event_rsvps').delete().eq('event_id', e['id']).eq('user_id', myId!);
                    } else {
                      await db.from('event_rsvps').insert({'event_id': e['id'], 'user_id': myId});
                    }
                    await onChanged();
                  }, ok: going ? 'Removed from your events' : 'We will remind you'),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  String _day(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today';
    final t = now.add(const Duration(days: 1));
    if (d.year == t.year && d.month == t.month && d.day == t.day) return 'Tomorrow';
    return '${d.day}/${d.month}';
  }
}
