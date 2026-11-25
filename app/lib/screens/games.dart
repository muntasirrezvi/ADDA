import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'wallet_screen.dart';

/// Lucky games. Every result is decided by the server (`play_game`), the app only animates it.
Future<void> openGames(BuildContext context, {int? roomId}) async {
  Map<String, dynamic> st;
  try {
    st = Map<String, dynamic>.from(await App.i.rpc('my_game_status') as Map);
  } catch (e) {
    if (context.mounted) toast(context, errText(e), bad: true);
    return;
  }
  if (!context.mounted) return;
  if (st['enabled'] != true) return toast(context, 'Games are switched off right now');
  if (st['accepted'] != true) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Lucky games', style: serif(22)),
        content: const Text(
          'Games use your Adda coins. Coins have no cash value and cannot be withdrawn.\n\n'
          'You must be 18 or older to play. A daily loss limit protects you.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now', style: TextStyle(color: C.mute))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('I am 18+, continue', style: TextStyle(color: C.gold))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await App.i.rpc('accept_games');
    } catch (e) {
      if (context.mounted) toast(context, errText(e), bad: true);
      return;
    }
  }
  if (!context.mounted) return;
  final minBet = (st['min_bet'] as num? ?? 10000).toInt();
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Lucky games', style: serif(22)),
          const SizedBox(height: 4),
          ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(grouped(c))),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _GameTile('Greedy', '🍗', 'Up to x45', const [Color(0xFFFF9F43), Color(0xFF8A2B0F)], () => _go(ctx, GreedyGame(minBet: minBet, roomId: roomId))),
              _GameTile('Lucky 777', '🎰', 'Jackpot x50', const [Color(0xFFC9506C), Color(0xFF3D0C1C)], () => _go(ctx, SlotsGame(minBet: minBet, roomId: roomId))),
              _GameTile('Rocket', '🚀', 'Cash out up to x100', const [Color(0xFF6A3DE8), Color(0xFF120A2E)], () => _go(ctx, CrashGame(minBet: minBet, roomId: roomId))),
              _GameTile('Dice', '🎲', 'Big · Small · Seven', const [Color(0xFF2A9D7F), Color(0xFF07261E)], () => _go(ctx, DiceGame(minBet: minBet, roomId: roomId))),
            ],
          ),
        ]),
      ),
    ),
  );
}

void _go(BuildContext ctx, Widget page) {
  Navigator.pop(ctx);
  Navigator.push(ctx, MaterialPageRoute(builder: (_) => page));
}

class _GameTile extends StatelessWidget {
  const _GameTile(this.title, this.emoji, this.sub, this.colors, this.onTap);
  final String title, emoji, sub;
  final List<Color> colors;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: colors.first.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(emoji, style: const TextStyle(fontSize: 34)),
            const Spacer(),
            Text(title, style: serif(19, color: Colors.white)),
            Text(sub, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ),
      );
}

// ---------- shared pieces ----------

const _chips = [10000, 50000, 100000, 500000, 1000000, 5000000];

Future<Map<String, dynamic>?> _play(BuildContext context, String game, {int bet = 0, Map<String, dynamic>? pick, int? roomId}) async {
  try {
    final r = Map<String, dynamic>.from(await App.i.rpc('play_game', {'p_game': game, 'p_bet': bet, 'p_pick': pick ?? {}, 'p_room': roomId}) as Map);
    return r;
  } catch (e) {
    if (!context.mounted) return null;
    final msg = errText(e);
    toast(context, msg, bad: true);
    if (msg.toLowerCase().contains('insufficient')) Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
    return null;
  }
}

void _settle(Map<String, dynamic> r) {
  App.i.coins.value = (r['coins'] as num).toInt();
}

class _ChipBar extends StatelessWidget {
  const _ChipBar({required this.value, required this.onChanged, required this.minBet});
  final int value;
  final int minBet;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        for (final c in _chips.where((c) => c >= minBet))
          GestureDetector(
            onTap: () => onChanged(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(right: 8),
              width: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: value == c ? const [Color(0xFFFFF1C9), C.gold2] : const [Color(0xFF5A4A33), Color(0xFF2A2218)]),
                border: Border.all(color: value == c ? Colors.white : C.gold2, width: value == c ? 3 : 2),
                boxShadow: value == c ? [BoxShadow(color: C.gold.withValues(alpha: .6), blurRadius: 12)] : null,
              ),
              alignment: Alignment.center,
              child: Text(compact(c), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: value == c ? const Color(0xFF1A1206) : C.gold)),
            ),
          ),
      ]),
    );
  }
}

class _GameScaffold extends StatelessWidget {
  const _GameScaffold({required this.title, required this.colors, required this.child});
  final String title;
  final List<Color> colors;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(compact(c)))),
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          child: SafeArea(child: child),
        ),
      );
}

Future<void> _resultPopup(BuildContext context, {required bool win, required int amount, String? note}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'result',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (_, __, ___) => const SizedBox(),
    transitionBuilder: (ctx, a, _, __) {
      final t = Curves.elasticOut.transform(a.value);
      return Center(
        child: Transform.scale(
          scale: .4 + .6 * t,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: 270,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: win ? const [Color(0xFF3A2A12), Color(0xFF15100A)] : const [Color(0xFF2A2026), Color(0xFF120D10)]),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: win ? C.gold : Colors.white24, width: 2),
                  boxShadow: win ? [BoxShadow(color: C.gold.withValues(alpha: .5), blurRadius: 30)] : null,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(win ? '🏆' : '🍀', style: const TextStyle(fontSize: 54)),
                  const SizedBox(height: 6),
                  Text(win ? 'You won!' : 'So close!', style: serif(26, color: win ? C.gold : Colors.white)),
                  const SizedBox(height: 6),
                  if (win) CoinText('+${grouped(amount)}', size: 22) else const Text('Try again — luck changes fast', style: TextStyle(color: C.mute)),
                  if (note != null) ...[const SizedBox(height: 6), Text(note, textAlign: TextAlign.center, style: const TextStyle(color: C.mute, fontSize: 12))],
                ]),
              ),
            ),
          ),
        ),
      );
    },
  );
}

// ---------- Greedy (food wheel) ----------

const _foods = [
  ('tomato', '🍅', 5),
  ('corn', '🌽', 5),
  ('carrot', '🥕', 5),
  ('lettuce', '🥬', 5),
  ('fish', '🐟', 10),
  ('shrimp', '🍤', 15),
  ('steak', '🥩', 25),
  ('chicken', '🍗', 45),
];

class GreedyGame extends StatefulWidget {
  const GreedyGame({super.key, required this.minBet, this.roomId});
  final int minBet;
  final int? roomId;
  @override
  State<GreedyGame> createState() => _GreedyGameState();
}

class _GreedyGameState extends State<GreedyGame> {
  late int _chip = widget.minBet;
  final Map<String, int> _bets = {};
  int? _lit;
  String? _winner;
  bool _busy = false;

  int get _total => _bets.values.fold(0, (a, b) => a + b);

  Future<void> _go() async {
    if (_total < widget.minBet) return toast(context, 'Tap the foods to place at least ${compact(widget.minBet)} coins');
    setState(() {
      _busy = true;
      _winner = null;
    });
    final r = await _play(context, 'greedy', pick: {'bets': _bets}, roomId: widget.roomId);
    if (r == null) return setState(() => _busy = false);
    final winner = r['winner'] as String;
    final target = winner == 'bomb' ? -1 : _foods.indexWhere((f) => f.$1 == winner);
    // run the light around the wheel, slowing down, and stop on the winner
    final steps = 8 * 4 + (target < 0 ? 5 : target);
    for (var i = 0; i <= steps; i++) {
      if (!mounted) return;
      setState(() => _lit = i % 8);
      final slow = i / steps;
      await Future.delayed(Duration(milliseconds: (45 + 320 * slow * slow * slow).round()));
    }
    if (!mounted) return;
    setState(() {
      _lit = target < 0 ? null : target;
      _winner = winner;
    });
    _settle(r);
    final payout = (r['payout'] as num).toInt();
    await _resultPopup(context, win: payout > 0, amount: payout, note: winner == 'bomb' ? 'The bomb went off 💣' : 'Winner: ${_foods[target].$2} x${_foods[target].$3}');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return _GameScaffold(
      title: 'Greedy',
      colors: const [Color(0xFF5A2A0F), Color(0xFF1A0D06)],
      child: Column(children: [
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final d = math.min(box.maxWidth, box.maxHeight) - 24;
            final rr = d / 2 - 44;
            return Center(
              child: SizedBox(
                width: d,
                height: d,
                child: Stack(children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(colors: [Color(0xFF8A4B1F), Color(0xFF3A1A08)]),
                        border: Border.all(color: C.gold, width: 4),
                        boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: .35), blurRadius: 30)],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: d * .34,
                      height: d * .34,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black38, border: Border.all(color: C.gold2, width: 2)),
                      alignment: Alignment.center,
                      child: _winner == 'bomb'
                          ? const Text('💥', style: TextStyle(fontSize: 46))
                          : Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_busy ? '🎯' : '💣', style: const TextStyle(fontSize: 30)),
                              Text(_total > 0 ? compact(_total) : 'Bet', style: serif(16, color: C.gold)),
                            ]),
                    ),
                  ),
                  for (var i = 0; i < 8; i++)
                    Builder(builder: (_) {
                      final ang = -math.pi / 2 + i * math.pi / 4;
                      final f = _foods[i];
                      final lit = _lit == i;
                      final stake = _bets[f.$1] ?? 0;
                      return Positioned(
                        left: d / 2 + rr * math.cos(ang) - 38,
                        top: d / 2 + rr * math.sin(ang) - 38,
                        child: GestureDetector(
                          onTap: _busy ? null : () => setState(() => _bets[f.$1] = stake + _chip),
                          onLongPress: _busy ? null : () => setState(() => _bets.remove(f.$1)),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 90),
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: lit ? const [Color(0xFFFFF7D6), Color(0xFFFFB84D)] : const [Color(0xFFFFE9C2), Color(0xFFC98A4B)]),
                              border: Border.all(color: lit ? Colors.white : C.gold2, width: lit ? 4 : 2),
                              boxShadow: [BoxShadow(color: (lit ? Colors.yellow : Colors.black).withValues(alpha: lit ? .9 : .4), blurRadius: lit ? 24 : 6)],
                            ),
                            child: Stack(alignment: Alignment.center, children: [
                              Text(f.$2, style: const TextStyle(fontSize: 34)),
                              Positioned(bottom: 4, child: Text('x${f.$3}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF5A2A0F)))),
                              if (stake > 0)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(color: C.ruby, borderRadius: BorderRadius.circular(8)),
                                    child: Text(compact(stake), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      );
                    }),
                ]),
              ),
            );
          }),
        ),
        const Text('Tap a food to bet the selected chip · long-press to clear it', style: TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 8),
        _ChipBar(value: _chip, minBet: widget.minBet, onChanged: (c) => setState(() => _chip = c)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(children: [
            OutlinedButton(onPressed: _busy || _bets.isEmpty ? null : () => setState(_bets.clear), child: const Text('Clear', style: TextStyle(color: Colors.white))),
            const SizedBox(width: 10),
            Expanded(child: GoldButton(label: _busy ? 'Spinning…' : 'GO  ·  ${compact(_total)}', busy: false, onTap: _busy ? null : _go)),
          ]),
        ),
      ]),
    );
  }
}

// ---------- Lucky 777 (slots) ----------

const _symbols = ['7', 'BAR', '🔔', '🍒', '🍋', '🍇', '⭐'];

class SlotsGame extends StatefulWidget {
  const SlotsGame({super.key, required this.minBet, this.roomId});
  final int minBet;
  final int? roomId;
  @override
  State<SlotsGame> createState() => _SlotsGameState();
}

class _SlotsGameState extends State<SlotsGame> with TickerProviderStateMixin {
  late int _bet = widget.minBet;
  final _rnd = math.Random();
  late final List<AnimationController> _reels =
      List.generate(3, (i) => AnimationController(vsync: this, duration: Duration(milliseconds: 1500 + i * 450)));
  List<int> _from = [0, 3, 5];
  List<int> _to = [0, 3, 5];
  bool _busy = false;
  static const _itemH = 86.0;

  @override
  void dispose() {
    for (final c in _reels) {
      c.dispose();
    }
    super.dispose();
  }

  List<int> _faces(String outcome) {
    int idx(String s) => _symbols.indexOf(s);
    switch (outcome) {
      case '777':
        return [0, 0, 0];
      case 'bar':
        return [1, 1, 1];
      case 'bell':
        return [2, 2, 2];
      case 'cherry3':
        return [3, 3, 3];
      case 'cherry2':
        return [3, 3, [4, 5, 6][_rnd.nextInt(3)]];
    }
    // a losing line: never three of a kind, never two cherries at the start
    while (true) {
      final f = List.generate(3, (_) => _rnd.nextInt(_symbols.length));
      final three = f[0] == f[1] && f[1] == f[2];
      final cherries = f[0] == idx('🍒') && f[1] == idx('🍒');
      if (!three && !cherries) return f;
    }
  }

  Future<void> _spin() async {
    setState(() => _busy = true);
    final r = await _play(context, 'slots', bet: _bet, roomId: widget.roomId);
    if (r == null) return setState(() => _busy = false);
    _from = List.of(_to);
    _to = _faces(r['outcome'] as String);
    setState(() {});
    await Future.wait([for (final c in _reels) c.forward(from: 0)]);
    _settle(r);
    final payout = (r['payout'] as num).toInt();
    if (mounted) await _resultPopup(context, win: payout > 0, amount: payout, note: payout > 0 ? 'x${r['mult']}' : null);
    if (mounted) setState(() => _busy = false);
  }

  Widget _symbol(int i) {
    final s = _symbols[i % _symbols.length];
    if (s == '7') {
      return ShaderMask(
        shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFF5E5E), Color(0xFFB0123C)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r),
        child: Text('7', style: serif(56, color: Colors.white, weight: FontWeight.w900)),
      );
    }
    if (s == 'BAR') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6), border: Border.all(color: C.gold, width: 2)),
        child: Text('BAR', style: serif(20, color: C.gold, weight: FontWeight.w900)),
      );
    }
    return Text(s, style: const TextStyle(fontSize: 46));
  }

  Widget _reel(int r) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        height: _itemH * 3,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFDDD6C8), Colors.white, Color(0xFFDDD6C8)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AnimatedBuilder(
            animation: _reels[r],
            builder: (_, __) {
              final n = _symbols.length;
              // spin through several full loops and land on the target in the middle row
              final loops = 6 + r * 2;
              final startPos = _from[r].toDouble();
              final endPos = (_to[r] + n * loops).toDouble();
              final pos = startPos + (endPos - startPos) * Curves.easeOutBack.transform(_reels[r].value.clamp(0.0, 1.0));
              final base = pos.floor();
              final frac = pos - base;
              return Stack(children: [
                for (var k = -2; k <= 2; k++)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _itemH * (1 + k - frac),
                    height: _itemH,
                    child: Center(child: _symbol(((base + k) % n + n) % n)),
                  ),
                IgnorePointer(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54], stops: [0, .3, .7, 1]),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _GameScaffold(
      title: 'Lucky 777',
      colors: const [Color(0xFF4A0C1E), Color(0xFF12060A)],
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFF0D9A6), Color(0xFFB8924F), Color(0xFF6B4A12)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: C.gold.withValues(alpha: .4), blurRadius: 30)],
          ),
          child: Column(children: [
            Text('★ LUCKY 777 ★', style: serif(22, color: const Color(0xFF3A1206), weight: FontWeight.w900)),
            const SizedBox(height: 8),
            Stack(alignment: Alignment.center, children: [
              Row(children: [_reel(0), _reel(1), _reel(2)]),
              IgnorePointer(child: Container(height: _itemH, decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: C.ruby.withValues(alpha: .8), width: 3))))),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 28), children: const [
            _PayRow('7  7  7', 'x50'),
            _PayRow('BAR  BAR  BAR', 'x20'),
            _PayRow('🔔 🔔 🔔', 'x10'),
            _PayRow('🍒 🍒 🍒', 'x5'),
            _PayRow('🍒 🍒  any', 'x2'),
          ]),
        ),
        _ChipBar(value: _bet, minBet: widget.minBet, onChanged: (c) => setState(() => _bet = c)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: GoldButton(label: _busy ? 'Spinning…' : 'SPIN  ·  ${compact(_bet)}', icon: Icons.casino, onTap: _busy ? null : _spin),
        ),
      ]),
    );
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow(this.combo, this.pays);
  final String combo, pays;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(combo, style: const TextStyle(fontSize: 16))), Text(pays, style: serif(18, color: C.gold))]),
      );
}

// ---------- Rocket (crash) ----------

class CrashGame extends StatefulWidget {
  const CrashGame({super.key, required this.minBet, this.roomId});
  final int minBet;
  final int? roomId;
  @override
  State<CrashGame> createState() => _CrashGameState();
}

class _CrashGameState extends State<CrashGame> with SingleTickerProviderStateMixin {
  late int _bet = widget.minBet;
  double _target = 2.0;
  double _m = 1.0;
  double? _crash;
  bool _busy = false;
  bool _cashed = false;
  final List<Offset> _trail = [];
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _launch() async {
    setState(() {
      _busy = true;
      _crash = null;
      _cashed = false;
      _m = 1.0;
      _trail.clear();
    });
    final r = await _play(context, 'crash', bet: _bet, pick: {'target': _target}, roomId: widget.roomId);
    if (r == null) return setState(() => _busy = false);
    final crash = (r['crash'] as num).toDouble();
    final start = DateTime.now();
    final done = Completer<void>();
    _t = Timer.periodic(const Duration(milliseconds: 30), (t) {
      final secs = DateTime.now().difference(start).inMilliseconds / 1000;
      final m = math.pow(math.e, 0.22 * secs).toDouble();
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _m = math.min(m, crash);
        _trail.add(Offset(secs, _m));
        if (!_cashed && _m >= _target && crash >= _target) _cashed = true;
        if (m >= crash) {
          _crash = crash;
          t.cancel();
          done.complete();
        }
      });
    });
    await done.future;
    _settle(r);
    final payout = (r['payout'] as num).toInt();
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      await _resultPopup(context, win: payout > 0, amount: payout, note: payout > 0 ? 'Cashed out at x${_target.toStringAsFixed(2)} · rocket reached x${crash.toStringAsFixed(2)}' : 'Rocket exploded at x${crash.toStringAsFixed(2)}');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final exploded = _crash != null;
    return _GameScaffold(
      title: 'Rocket',
      colors: const [Color(0xFF120A2E), Color(0xFF05030F)],
      child: Column(children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white12)),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _CrashPainter(_trail, exploded, _target))),
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('x${_m.toStringAsFixed(2)}', style: serif(56, color: exploded ? C.ruby : (_cashed ? C.emerald : Colors.white))),
                  if (exploded) Text('💥 Exploded', style: serif(20, color: C.ruby)),
                  if (_cashed && !exploded) const Text('✓ Cashed out', style: TextStyle(color: C.emerald, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Text('Cash out at', style: TextStyle(color: Colors.white70)),
            const Spacer(),
            for (final t in const [1.5, 2.0, 3.0, 5.0, 10.0])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(label: Text('x${t % 1 == 0 ? t.toStringAsFixed(0) : t}'), selected: _target == t, onSelected: _busy ? null : (_) => setState(() => _target = t)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        _ChipBar(value: _bet, minBet: widget.minBet, onChanged: (c) => setState(() => _bet = c)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: GoldButton(label: _busy ? 'Flying…' : 'LAUNCH  ·  ${compact(_bet)}', icon: Icons.rocket_launch, onTap: _busy ? null : _launch),
        ),
      ]),
    );
  }
}

class _CrashPainter extends CustomPainter {
  _CrashPainter(this.trail, this.exploded, this.target);
  final List<Offset> trail;
  final bool exploded;
  final double target;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = Colors.white10;
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(Offset(0, size.height * i / 5), Offset(size.width, size.height * i / 5), grid);
    }
    if (trail.isEmpty) return;
    final maxT = math.max(6.0, trail.last.dx * 1.1);
    final maxM = math.max(target * 1.2, trail.last.dy * 1.15);
    Offset map(Offset p) => Offset(16 + (size.width - 40) * p.dx / maxT, size.height - 16 - (size.height - 40) * (p.dy - 1) / (maxM - 1));
    final path = Path()..moveTo(map(trail.first).dx, map(trail.first).dy);
    for (final p in trail) {
      final q = map(p);
      path.lineTo(q.dx, q.dy);
    }
    final fill = Path.from(path)
      ..lineTo(map(trail.last).dx, size.height - 16)
      ..lineTo(16, size.height - 16)
      ..close();
    canvas.drawPath(fill, Paint()..shader = LinearGradient(colors: [(exploded ? C.ruby : C.gold).withValues(alpha: .35), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()
      ..color = exploded ? C.ruby : C.gold
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round);
    // target line
    final ty = map(Offset(0, target)).dy;
    canvas.drawLine(Offset(0, ty), Offset(size.width, ty), Paint()
      ..color = C.emerald.withValues(alpha: .7)
      ..strokeWidth = 1.5);
    // rocket or explosion at the head
    final head = map(trail.last);
    final tp = TextPainter(text: TextSpan(text: exploded ? '💥' : '🚀', style: TextStyle(fontSize: exploded ? 44 : 34)), textDirection: TextDirection.ltr)..layout();
    canvas.save();
    canvas.translate(head.dx, head.dy);
    if (!exploded) canvas.rotate(-0.15);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrashPainter old) => true;
}

// ---------- Dice ----------

class DiceGame extends StatefulWidget {
  const DiceGame({super.key, required this.minBet, this.roomId});
  final int minBet;
  final int? roomId;
  @override
  State<DiceGame> createState() => _DiceGameState();
}

class _DiceGameState extends State<DiceGame> with SingleTickerProviderStateMixin {
  late int _bet = widget.minBet;
  String _side = 'big';
  List<int> _dice = [3, 4];
  bool _busy = false;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  final _rnd = math.Random();

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _roll() async {
    setState(() => _busy = true);
    final r = await _play(context, 'dice', bet: _bet, pick: {'side': _side}, roomId: widget.roomId);
    if (r == null) return setState(() => _busy = false);
    final result = List<int>.from((r['dice'] as List).map((e) => (e as num).toInt()));
    void flick() {
      if (_shake.isAnimating && mounted) setState(() => _dice = [_rnd.nextInt(6) + 1, _rnd.nextInt(6) + 1]);
    }
    _shake.addListener(flick);
    await _shake.forward(from: 0);
    _shake.removeListener(flick);
    if (!mounted) return;
    setState(() => _dice = result);
    _settle(r);
    final payout = (r['payout'] as num).toInt();
    await _resultPopup(context, win: payout > 0, amount: payout, note: 'Rolled ${result[0]} + ${result[1]} = ${result[0] + result[1]}');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return _GameScaffold(
      title: 'Dice',
      colors: const [Color(0xFF0B3328), Color(0xFF041210)],
      child: Column(children: [
        Expanded(
          child: Center(
            child: Container(
              width: 290,
              height: 200,
              decoration: BoxDecoration(
                gradient: const RadialGradient(colors: [Color(0xFF1F7A5F), Color(0xFF0B3328)]),
                borderRadius: BorderRadius.circular(110),
                border: Border.all(color: const Color(0xFF6B4A12), width: 10),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 10))],
              ),
              child: AnimatedBuilder(
                animation: _shake,
                builder: (_, __) {
                  final v = _shake.value;
                  final wob = _shake.isAnimating ? math.sin(v * math.pi * 14) * (1 - v) : 0.0;
                  return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < 2; i++)
                      Transform.translate(
                        offset: Offset(wob * 18 * (i == 0 ? 1 : -1), -wob.abs() * 26),
                        child: Transform.rotate(angle: wob * 1.4 * (i == 0 ? 1 : -1), child: _Die(_dice[i])),
                      ),
                  ]);
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final s in const [('small', 'SMALL', '2–6 · x2.25'), ('seven', 'SEVEN', '7 · x5.5'), ('big', 'BIG', '8–12 · x2.25')])
              Expanded(
                child: GestureDetector(
                  onTap: _busy ? null : () => setState(() => _side = s.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _side == s.$1 ? const Color(0xFF3A2E17) : Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _side == s.$1 ? C.gold : Colors.white24, width: 2),
                    ),
                    child: Column(children: [
                      Text(s.$2, style: serif(18, color: _side == s.$1 ? C.gold : Colors.white)),
                      Text(s.$3, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        _ChipBar(value: _bet, minBet: widget.minBet, onChanged: (c) => setState(() => _bet = c)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: GoldButton(label: _busy ? 'Rolling…' : 'ROLL  ·  ${compact(_bet)}', icon: Icons.casino, onTap: _busy ? null : _roll),
        ),
      ]),
    );
  }
}

class _Die extends StatelessWidget {
  const _Die(this.n);
  final int n;
  static const _pips = {
    1: [Alignment.center],
    2: [Alignment.topLeft, Alignment.bottomRight],
    3: [Alignment.topLeft, Alignment.center, Alignment.bottomRight],
    4: [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight],
    5: [Alignment.topLeft, Alignment.topRight, Alignment.center, Alignment.bottomLeft, Alignment.bottomRight],
    6: [Alignment.topLeft, Alignment.topRight, Alignment.centerLeft, Alignment.centerRight, Alignment.bottomLeft, Alignment.bottomRight],
  };
  @override
  Widget build(BuildContext context) => Container(
        width: 76,
        height: 76,
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Colors.white, Color(0xFFE2DDD4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(3, 6))],
        ),
        child: Stack(children: [
          for (final a in _pips[n]!)
            Align(
              alignment: a,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(shape: BoxShape.circle, color: n == 1 ? C.ruby : const Color(0xFF1A1206)),
              ),
            ),
        ]),
      );
}
