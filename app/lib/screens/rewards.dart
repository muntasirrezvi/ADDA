import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'games_kit.dart';

/// Opens the 7-day reward calendar. With [onlyIfReady] it opens only when today's reward
/// has not been collected yet (used once when the app starts).
Future<void> showDailyRewards(BuildContext context, {bool onlyIfReady = false}) async {
  Map<String, dynamic> st;
  try {
    st = Map<String, dynamic>.from(await App.i.rpc('checkin_status') as Map);
  } catch (e) {
    if (!onlyIfReady && context.mounted) toast(context, errText(e), bad: true);
    return;
  }
  if (onlyIfReady && st['claimed_today'] == true) return;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RewardSheet(initial: st),
  );
}

class _RewardSheet extends StatefulWidget {
  const _RewardSheet({required this.initial});
  final Map<String, dynamic> initial;
  @override
  State<_RewardSheet> createState() => _RewardSheetState();
}

class _RewardSheetState extends State<_RewardSheet> with TickerProviderStateMixin {
  late Map<String, dynamic> _st = widget.initial;
  bool _busy = false;
  int? _won;
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _st['claimed_today'] == true) setState(() {});
    });
  }

  @override
  void dispose() {
    _glow.dispose();
    _burst.dispose();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _collect() async {
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('daily_checkin') as Map);
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Come back tomorrow');
      _won = (r['reward'] as num).toInt();
      Sfx.play('coin');
      Future.delayed(const Duration(milliseconds: 250), () => Sfx.play('win'));
      _burst.forward(from: 0);
      unawaited(App.i.refreshWallet());
      _st = Map<String, dynamic>.from(await App.i.rpc('checkin_status') as Map);
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  String _countdown() {
    final next = DateTime.tryParse('${_st['next_at']}')?.toLocal();
    if (next == null) return 'tomorrow';
    final d = next.difference(DateTime.now());
    if (d.isNegative) return 'now';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final days = List<Map<String, dynamic>>.from((_st['days'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final claimed = _st['claimed_today'] == true;
    final today = days.firstWhere((d) => d['state'] == 'today', orElse: () => days.first);
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF3A1C5A), Color(0xFF1A0E2A), Color(0xFF0E0A14)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 10),
          Row(children: [
            Floaty(amp: 3, child: art('coins_pile', size: 56)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Daily rewards', style: serif(24, color: C.gold)),
                Text('Collect every day — each day pays 20% more. Miss a day and it starts again from day 1.', style: const TextStyle(color: C.mute, fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          // days 1-6 in a grid, day 7 as the big prize
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: .95,
            children: [for (final d in days.take(days.length - 1)) _day(d)],
          ),
          if (days.length > 1) ...[const SizedBox(height: 10), SizedBox(height: 108, child: _day(days.last, big: true))],
          const SizedBox(height: 16),
          if (claimed)
            Column(children: [
              if (_won != null) CountUp(_won!, size: 26),
              const SizedBox(height: 6),
              Text('Next reward in ${_countdown()}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: C.gold))),
            ])
          else
            PressButton(label: 'COLLECT DAY ${today['day']}  ·  ${compact(today['amount'] as num)}', busy: _busy, onTap: _collect),
        ]),
        Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: _burst, builder: (_, __) => _burst.value == 0 ? const SizedBox() : CoinShower(progress: _burst.value)))),
      ]),
    );
  }

  Widget _day(Map<String, dynamic> d, {bool big = false}) {
    final state = d['state'];
    final isToday = state == 'today';
    final done = state == 'claimed';
    final n = (d['day'] as num).toInt();
    final img = big ? 'coins_pile' : (n >= 4 ? 'coins_pile' : 'coin');
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: isToday ? const [Color(0xFFFFE7A0), Color(0xFFE0A93A), Color(0xFF9A6210)] : done ? const [Color(0xFF2A2A34), Color(0xFF1A1A22)] : const [Color(0xFF4A2A6E), Color(0xFF241638)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: isToday ? Colors.white : Colors.white12, width: isToday ? 2 : 1),
          boxShadow: isToday ? [BoxShadow(color: C.gold.withValues(alpha: .35 + .35 * _glow.value), blurRadius: 18 + 8 * _glow.value)] : null,
        ),
        child: child,
      ),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: big
              ? Row(children: [
                  Expanded(child: _label(n, d, isToday, done)),
                  Floaty(amp: isToday ? 4 : 0, child: art(img, size: 84)),
                ])
              : Column(children: [
                  _label(n, d, isToday, done, center: true),
                  Expanded(child: Opacity(opacity: done ? .45 : 1, child: isToday ? Floaty(amp: 3, child: art(img)) : art(img))),
                ]),
        ),
        if (done)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: C.emerald),
              child: const Icon(Icons.check, size: 14, color: Colors.white),
            ),
          ),
        if (state == 'upcoming') const Positioned(right: 8, top: 8, child: Icon(Icons.lock_outline, size: 14, color: Colors.white38)),
      ]),
    );
  }

  Widget _label(int n, Map<String, dynamic> d, bool isToday, bool done, {bool center = false}) {
    final dark = isToday ? const Color(0xFF2A1A04) : Colors.white;
    return Column(crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(isToday ? 'TODAY' : 'Day $n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: dark.withValues(alpha: done ? .5 : .9))),
      Text(compact(d['amount'] as num), style: TextStyle(fontSize: center ? 15 : 22, fontWeight: FontWeight.w900, color: isToday ? dark : (done ? Colors.white38 : C.gold))),
      if (!center) Text(n == 7 ? 'Big prize · day 7' : '', style: TextStyle(fontSize: 11, color: dark.withValues(alpha: .7))),
    ]);
  }
}
