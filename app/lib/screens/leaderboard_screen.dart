import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';

Future<List<Map<String, dynamic>>> fetchLeaderboard(String kind, String period, {int limit = 50}) async {
  final r = await App.i.rpc('leaderboard', {'p_kind': kind, 'p_period': period, 'p_limit': limit});
  return List<Map<String, dynamic>>.from(r as List);
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, this.kind = 'wealth'});
  final String kind;
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late String _kind = widget.kind;
  String _period = 'week';
  Future<List<Map<String, dynamic>>>? _f;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _f = fetchLeaderboard(_kind, _period));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3A2A12), C.bg], begin: Alignment.topCenter, end: Alignment.center)),
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              const BackButton(),
              Expanded(child: Text('Leaderboard', style: serif(24))),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'wealth', label: Text('Top gifters'), icon: Icon(Icons.workspace_premium)),
                  ButtonSegment(value: 'charm', label: Text('Top stars'), icon: Icon(Icons.favorite)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) {
                  _kind = s.first;
                  _load();
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final p in const [('day', 'Today'), ('week', 'This week'), ('all', 'All time')])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(label: Text(p.$2), selected: _period == p.$1, onSelected: (_) {
                    _period = p.$1;
                    _load();
                  }),
                ),
            ]),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _f,
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: C.gold));
                  final rows = snap.data!;
                  if (rows.isEmpty) return const EmptyState('No gifts yet in this period. Send a gift to get on the board!', icon: Icons.emoji_events);
                  final top = rows.take(3).toList();
                  final rest = rows.skip(3).toList();
                  return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
                    _Podium(top: top, kind: _kind),
                    for (final r in rest) _Row(r: r),
                  ]);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.top, required this.kind});
  final List<Map<String, dynamic>> top;
  final String kind;
  @override
  Widget build(BuildContext context) {
    Widget spot(int i, double h, Color c) {
      if (i >= top.length) return const Expanded(child: SizedBox());
      final r = top[i];
      return Expanded(
        child: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: r['user_id'] as String))),
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(i == 0 ? '👑' : i == 1 ? '🥈' : '🥉', style: TextStyle(fontSize: i == 0 ? 34 : 26)),
            Avatar(profile: {'username': r['username'], 'avatar_url': r['avatar_url'], 'avatar_preset': r['avatar_preset']}, size: i == 0 ? 82 : 64, ring: c),
            const SizedBox(height: 6),
            Text('${r['username']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            CoinText(compact(r['score'] as num), size: 12),
            const SizedBox(height: 6),
            Container(
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c, c.withValues(alpha: .25)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              alignment: Alignment.center,
              child: Text('${i + 1}', style: serif(30, color: Colors.white)),
            ),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
      child: SizedBox(
        height: 290,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          spot(1, 80, const Color(0xFFC0C6D0)),
          spot(0, 110, C.gold),
          spot(2, 60, const Color(0xFFCD8B5A)),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.r});
  final Map<String, dynamic> r;
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: r['user_id'] as String))),
        leading: SizedBox(
          width: 86,
          child: Row(children: [
            SizedBox(width: 30, child: Text('${r['rank']}', style: serif(18, color: C.mute))),
            Avatar(profile: {'username': r['username'], 'avatar_url': r['avatar_url'], 'avatar_preset': r['avatar_preset']}, size: 44),
          ]),
        ),
        title: Row(children: [
          Flexible(child: Text('${r['username']}', overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          LevelBadge((r['wealth_level'] as num?)?.toInt() ?? 1),
        ]),
        trailing: CoinText(compact(r['score'] as num), size: 13),
      );
}

/// Compact "Top gifters this week" card for the home screen.
class LeaderboardStrip extends StatefulWidget {
  const LeaderboardStrip({super.key});
  @override
  State<LeaderboardStrip> createState() => _LeaderboardStripState();
}

class _LeaderboardStripState extends State<LeaderboardStrip> {
  List<Map<String, dynamic>> _w = [];
  List<Map<String, dynamic>> _c = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final w = await fetchLeaderboard('wealth', 'week', limit: 3);
      final c = await fetchLeaderboard('charm', 'week', limit: 3);
      if (mounted) {
        setState(() {
          _w = w;
          _c = c;
        });
      }
    } catch (_) {}
  }

  Widget _card(String title, String emoji, List<Map<String, dynamic>> rows, String kind, List<Color> g) => Expanded(
        child: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaderboardScreen(kind: kind))),
          child: Container(
            height: 92,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 4),
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                const Icon(Icons.chevron_right, size: 16),
              ]),
              const Spacer(),
              rows.isEmpty
                  ? const Text('Be the first!', style: TextStyle(fontSize: 12, color: Colors.white70))
                  : Row(children: [
                      for (var i = 0; i < rows.length; i++)
                        Align(
                          widthFactor: .75,
                          child: Avatar(profile: {'username': rows[i]['username'], 'avatar_url': rows[i]['avatar_url'], 'avatar_preset': rows[i]['avatar_preset']}, size: 34, ring: i == 0 ? C.gold : Colors.white70),
                        ),
                    ]),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          _card('Top gifters', '👑', _w, 'wealth', const [Color(0xFF8A6A2B), Color(0xFF3A2A12)]),
          const SizedBox(width: 10),
          _card('Top stars', '⭐', _c, 'charm', const [Color(0xFFC9506C), Color(0xFF3D0C1C)]),
        ]),
      );
}
