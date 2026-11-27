import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'casino_kit.dart';
import 'games_kit.dart';

/// Greedy / Fruit Party: one live round for everyone. 25 s to place chips, then the light runs
/// around the wheel and stops on the winner. Played with coins only.
class GreedyLive extends StatefulWidget {
  const GreedyLive({super.key, this.minBet = 1000, this.cfg = greedyCfg});
  final int minBet;
  final WheelCfg cfg;
  @override
  State<GreedyLive> createState() => _GreedyLiveState();
}

class WheelCfg {
  const WheelCfg({required this.game, required this.title, required this.items, required this.left, required this.right, required this.leftLabel, required this.rightLabel, required this.bg, required this.help});
  final String game;
  final String title;
  final List<_Food> items;
  final _Food left;
  final _Food right;
  final String leftLabel;
  final String rightLabel;
  final List<Color> bg;
  final String help;
  String artFor(String id) => [...items, left, right].firstWhere((f) => f.id == id, orElse: () => items.first).art;
}

const greedyCfg = WheelCfg(
  game: 'greedy',
  title: 'Greedy',
  items: _foods,
  left: _groupFruit,
  right: _groupPizza,
  leftLabel: 'Fruit',
  rightLabel: 'Pizza',
  bg: [Color(0xFF6A3FA0), Color(0xFF3A1D5C), Color(0xFF1C0C2C)],
  help: 'Fruit pays x1.25 if any of the four x5 foods wins. Pizza pays x4.3 if fish, burger, pizza or chicken wins.',
);

const fruitCfg = WheelCfg(
  game: 'fruit',
  title: 'Fruit Party',
  items: [
    _Food('cherry', 'fruit_cherry', 5),
    _Food('lemon', 'fruit_lemon', 5),
    _Food('orange', 'fruit_orange', 5),
    _Food('apple', 'fruit_apple', 5),
    _Food('grape', 'fruit_grape', 10),
    _Food('banana', 'fruit_banana', 15),
    _Food('strawberry', 'fruit_strawberry', 25),
    _Food('watermelon', 'fruit_watermelon', 45),
  ],
  left: _Food('g_small', 'group_fruit', 1.25),
  right: _Food('g_big', 'fruit_watermelon', 4.3),
  leftLabel: 'Small',
  rightLabel: 'Big',
  bg: [Color(0xFF2FA05A), Color(0xFF13603A), Color(0xFF07301C)],
  help: 'Small pays x1.25 if cherry, lemon, orange or apple wins. Big pays x4.3 if grape, banana, strawberry or watermelon wins.',
);

class _Food {
  const _Food(this.id, this.art, this.mult);
  final String id;
  final String art;
  final num mult;
}

// clockwise from the top, same order as the server
const _foods = [
  _Food('apple', 'fruit_apple', 5),
  _Food('lemon', 'fruit_lemon', 5),
  _Food('strawberry', 'fruit_strawberry', 5),
  _Food('mango', 'food_mango', 5),
  _Food('fish', 'food_fish', 10),
  _Food('burger', 'food_burger', 15),
  _Food('pizza', 'food_pizza', 25),
  _Food('chicken', 'food_chicken', 45),
];
const _groupFruit = _Food('g_fruit', 'group_fruit', 1.25);
const _groupPizza = _Food('g_pizza', 'group_pizza', 4.3);


class _GreedyLiveState extends State<GreedyLive> with TickerProviderStateMixin {
  Map<String, dynamic>? _s;
  int _chip = 1000;
  int _offset = 0; // server clock minus phone clock (ms)
  Timer? _tick;
  Timer? _poll;
  int? _spunRound; // round whose wheel animation already ran
  int _light = -1; // index of the lit food while the wheel runs
  bool _showPopup = false;
  final Map<String, int> _pending = {};
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  int get _now => DateTime.now().millisecondsSinceEpoch + _offset;
  String get _phase => '${_s?['phase'] ?? 'bet'}';
  int get _round => (_s?['round'] as num? ?? 0).toInt();

  @override
  void initState() {
    super.initState();
    _chip = casinoChips.firstWhere((c) => c >= widget.minBet, orElse: () => casinoChips.first);
    _load();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  bool _loading = false;
  int _lastLeft = -1;

  Future<void> _load({bool quiet = false}) async {
    if (_loading) return;
    _loading = true;
    try {
      final s = Map<String, dynamic>.from(await App.i.rpc('wheel_state', {'p_game': widget.cfg.game}) as Map);
      if (!mounted) return;
      _offset = (s['now_ms'] as num).toInt() - DateTime.now().millisecondsSinceEpoch;
      final c = s['coins'] as num?;
      if (c != null) App.i.coins.value = c.toInt();
      final newRound = (s['round'] as num).toInt() != _round;
      setState(() {
        _s = s;
        if (newRound) {
          _showPopup = false;
          _light = -1;
        }
      });
      if (s['phase'] == 'show' && s['result'] != null && _spunRound != _round) _spin();
    } catch (e) {
      if (!quiet && mounted) toast(context, errText(e), bad: true);
    } finally {
      _loading = false;
    }
  }

  void _onTick() {
    final s = _s;
    if (s == null) return;
    final betUntil = (s['bet_until_ms'] as num).toInt();
    final ends = (s['ends_ms'] as num).toInt();
    if (_phase == 'bet' && _now >= betUntil) {
      _load(quiet: true); // betting closed: fetch the result
    } else if (_now >= ends + 300) {
      _load(quiet: true); // next round
    }
    final left = ((_phase == 'bet' ? betUntil : ends) - _now) ~/ 1000;
    if (_phase == 'bet' && left <= 3 && left >= 0 && left != _lastLeft) Sfx.play('tick', volume: .4);
    _lastLeft = left;
    setState(() {});
  }

  Future<void> _spin() async {
    final s = _s!;
    _spunRound = _round;
    final target = widget.cfg.items.indexWhere((f) => f.id == s['result']);
    if (target < 0) return;
    // the light runs 3 laps and slows down onto the winner
    final steps = 8 * 3 + target;
    var delay = 60;
    for (var i = 0; i <= steps; i++) {
      if (!mounted || _spunRound != _round) return;
      setState(() => _light = i % 8);
      Sfx.play('tick', volume: .35);
      final left = steps - i;
      if (left < 10) delay += 35;
      await Future.delayed(Duration(milliseconds: delay));
    }
    if (!mounted) return;
    final me = s['me'] as Map?;
    final win = (me?['win'] as num? ?? 0).toInt();
    Sfx.play(win > 0 ? 'win' : (me == null ? 'pop' : 'lose'));
    if (win > 0) Future.delayed(const Duration(milliseconds: 300), () => Sfx.play('coin'));
    setState(() => _showPopup = true);
  }

  Future<void> _bet(String item) async {
    if (_phase != 'bet') {
      toast(context, 'Wait for the next round');
      return;
    }
    if (App.i.coins.value < _chip) {
      toast(context, 'Not enough coins', bad: true);
      return;
    }
    Sfx.play('pop', volume: .6);
    setState(() => _pending[item] = (_pending[item] ?? 0) + _chip);
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('wheel_bet', {'p_game': widget.cfg.game, 'p_item': item, 'p_amount': _chip}) as Map);
      App.i.coins.value = (r['coins'] as num).toInt();
      if (!mounted) return;
      setState(() {
        _s = {...?_s, 'my_bets': r['my_bets'], 'chests': r['chests']};
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    } finally {
      if (mounted) setState(() => _pending[item] = (_pending[item] ?? _chip) - _chip);
    }
  }

  int _mine(String id) => ((_s?['my_bets'] as Map?)?[id] as num? ?? 0).toInt() + (_pending[id] ?? 0);

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final chests = s?['chests'] as Map<String, dynamic>?;
    final todayWin = (chests?['win'] as num? ?? 0).toInt();
    return Scaffold(
      backgroundColor: const Color(0xFF2A1238),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.cfg.title),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: _help),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(grouped(c)))),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(center: const Alignment(0, -.45), radius: 1.1, colors: widget.cfg.bg),
        ),
        child: s == null
            ? const Center(child: CircularProgressIndicator(color: C.gold))
            : Stack(children: [
                ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
                  _wheel(),
                  const SizedBox(height: 6),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text("TODAY'S WIN  ", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 13)),
                        Text(grouped(todayWin), style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w900, fontSize: 16)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GoldPanel(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                    child: Column(children: [
                      Text(_phase == 'bet' ? 'Choose the amount  →  Choose food' : 'Round closed, the next one starts soon',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 70,
                        child: ListView(scrollDirection: Axis.horizontal, children: [
                          for (final c in casinoChips.where((c) => c >= widget.minBet))
                            GestureDetector(
                              onTap: () {
                                Sfx.play('pop', volume: .5);
                                setState(() => _chip = c);
                              },
                              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: PokerChip(value: c, selected: c == _chip)),
                            ),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  ChestBar(state: chests, onClaim: (lv) async {
                    final r = await claimChest(context, widget.cfg.game, lv);
                    if (r != null && mounted) setState(() => _s = {...?_s, 'chests': r});
                  }),
                  const SizedBox(height: 10),
                  _history(),
                ]),
                if (_showPopup && _phase == 'show') Positioned.fill(child: _resultPopup()),
              ]),
      ),
    );
  }

  Widget _wheel() {
    final s = _s!;
    final betUntil = (s['bet_until_ms'] as num).toInt();
    final ends = (s['ends_ms'] as num).toInt();
    final left = math.max(0, ((_phase == 'bet' ? betUntil : ends) - _now) / 1000).ceil();
    final allBets = (s['all_bets'] as Map?) ?? const {};
    return AspectRatio(
      aspectRatio: .95,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final cx = w / 2;
        final cy = h * .44;
        final r = w * .34;
        final item = w * .25;
        return Stack(clipBehavior: Clip.none, children: [
          // spokes
          Positioned.fill(child: CustomPaint(painter: _SpokePainter(Offset(cx, cy), r))),
          for (var i = 0; i < 8; i++)
            Positioned(
              left: cx + r * math.cos(-math.pi / 2 + i * math.pi / 4) - item / 2,
              top: cy + r * math.sin(-math.pi / 2 + i * math.pi / 4) - item / 2,
              width: item,
              height: item,
              child: _FoodButton(
                food: widget.cfg.items[i],
                mine: _mine(widget.cfg.items[i].id),
                total: (allBets[widget.cfg.items[i].id] as num? ?? 0).toInt(),
                lit: _light == i,
                winner: _phase == 'show' && _showPopup && s['result'] == widget.cfg.items[i].id,
                dim: _phase == 'show' && _light != i && _light >= 0,
                onTap: () => _bet(widget.cfg.items[i].id),
              ),
            ),
          // center hub with the countdown
          Positioned(
            left: cx - w * .17,
            top: cy - w * .17,
            width: w * .34,
            height: w * .34,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [Color(0xFFFFE9A8), Color(0xFFE9A92A), Color(0xFF9A5A0A)]),
                  boxShadow: [BoxShadow(color: const Color(0xFFFFD54F).withValues(alpha: .35 + .25 * _pulse.value), blurRadius: 22, spreadRadius: 2)],
                ),
                padding: EdgeInsets.all(w * .012),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _phase == 'bet' ? const Color(0xFFD32F2F) : const Color(0xFFF2B01E)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    art('crown', size: w * .1),
                    Text(_phase == 'bet' ? 'Bet Time' : 'Show Time', style: TextStyle(color: _phase == 'bet' ? Colors.white : const Color(0xFF5A2A00), fontWeight: FontWeight.w800, fontSize: w * .036)),
                    Text('${left}s', style: TextStyle(color: _phase == 'bet' ? Colors.white : const Color(0xFF5A2A00), fontWeight: FontWeight.w900, fontSize: w * .07, height: 1.05)),
                  ]),
                ),
              ),
            ),
          ),
          // group bets
          Positioned(left: 0, bottom: 0, width: w * .25, child: _GroupButton(food: widget.cfg.left, label: widget.cfg.leftLabel, mine: _mine(widget.cfg.left.id), onTap: () => _bet(widget.cfg.left.id))),
          Positioned(right: 0, bottom: 0, width: w * .25, child: _GroupButton(food: widget.cfg.right, label: widget.cfg.rightLabel, mine: _mine(widget.cfg.right.id), onTap: () => _bet(widget.cfg.right.id))),
          Positioned(
            left: 0,
            top: 0,
            child: Row(children: [
              const Icon(Icons.people_alt, color: Colors.white70, size: 16),
              const SizedBox(width: 4),
              Text('${s['players'] ?? 0} playing', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]);
      }),
    );
  }

  Widget _history() {
    final h = (_s?['history'] as List? ?? const []).cast<dynamic>();
    return GoldPanel(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(children: [
        const Text('Result', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 48,
            child: h.isEmpty
                ? const Align(alignment: Alignment.centerLeft, child: Text('No rounds yet', style: TextStyle(color: Colors.white54)))
                : ListView(scrollDirection: Axis.horizontal, children: [
                    for (var i = 0; i < h.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Stack(clipBehavior: Clip.none, children: [
                          Container(
                            width: 44,
                            height: 44,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(10)),
                            child: art(widget.cfg.artFor('${h[i]}')),
                          ),
                          if (i == 0)
                            Positioned(
                              top: -6,
                              left: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(color: const Color(0xFFFFC107), borderRadius: BorderRadius.circular(6)),
                                child: const Text('New', style: TextStyle(color: Color(0xFF5A2A00), fontSize: 9, fontWeight: FontWeight.w900)),
                              ),
                            ),
                        ]),
                      ),
                  ]),
          ),
        ),
      ]),
    );
  }

  Widget _resultPopup() {
    final s = _s!;
    final me = s['me'] as Map?;
    final win = (me?['win'] as num? ?? 0).toInt();
    final top = (s['top'] as List? ?? const []).cast<Map>();
    final result = '${s['result']}';
    final msg = me == null ? 'You did not bet in this round' : (win > 0 ? 'You won ${grouped(win)}!' : 'Better luck next round');
    return GestureDetector(
      onTap: () => setState(() => _showPopup = false),
      child: Container(
        color: Colors.black45,
        alignment: Alignment.center,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: .6, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF8A0E12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFFFC94A), width: 4),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: const BoxDecoration(color: Color(0xFFB0161B), borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
                child: Row(children: [
                  art(widget.cfg.artFor(result), size: 48),
                  Container(width: 1, height: 40, color: Colors.white38, margin: const EdgeInsets.symmetric(horizontal: 12)),
                  Expanded(child: Text(msg, style: TextStyle(color: win > 0 ? const Color(0xFFFFE07A) : Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                ]),
              ),
              if (win > 0) SizedBox(height: 60, child: CountUp(win, size: 30)),
              if (top.isEmpty)
                const Padding(padding: EdgeInsets.all(18), child: Text('No winners this round', style: TextStyle(color: Colors.white70)))
              else
                for (var i = 0; i < top.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0x33FFFFFF)))),
                    child: Row(children: [
                      Icon(Icons.workspace_premium, size: 34, color: [const Color(0xFFFFC94A), const Color(0xFF8FD3FF), const Color(0xFFE8A07A)][i]),
                      const SizedBox(width: 12),
                      Avatar(profile: Map<String, dynamic>.from(top[i]), size: 44),
                      const SizedBox(width: 12),
                      Expanded(child: Text('${top[i]['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700))),
                      art('coin', size: 22),
                      const SizedBox(width: 4),
                      Text(compact(top[i]['win'] as num), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    ]),
                  ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }

  void _help() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('How to play ${widget.cfg.title}', style: serif(22)),
          content: Text(
            'Everyone plays the same round.\n\n'
            '1. Pick a chip, then tap items to bet during Bet Time (25 s). Tap again to add more.\n'
            '2. Show Time: the light runs around the wheel and stops on one item.\n'
            '3. If you bet on it you win your bet × its number (x5 to x45).\n\n'
            '${widget.cfg.help}\n\n'
            'Bet more today to open the five chests. Coins only — no real money.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: C.gold)))],
        ),
      );
}

class _SpokePainter extends CustomPainter {
  _SpokePainter(this.c, this.r);
  final Offset c;
  final double r;
  @override
  void paint(Canvas canvas, Size size) {
    // light beams under the wheel
    final beam = Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: .12), Colors.transparent]).createShader(Offset.zero & size);
    final path = Path()
      ..moveTo(c.dx - r * .25, c.dy)
      ..lineTo(c.dx - r * 1.1, size.height)
      ..lineTo(c.dx + r * 1.1, size.height)
      ..lineTo(c.dx + r * .25, c.dy)
      ..close();
    canvas.drawPath(path, beam);
    final p = Paint()
      ..color = const Color(0xFFB8741A)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * r, p);
    }
    canvas.drawCircle(c, r, Paint()..color = const Color(0x55FFD54F)..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_SpokePainter o) => o.c != c || o.r != r;
}

class _FoodButton extends StatelessWidget {
  const _FoodButton({required this.food, required this.mine, required this.total, required this.lit, required this.winner, required this.dim, required this.onTap});
  final _Food food;
  final int mine;
  final int total;
  final bool lit;
  final bool winner;
  final bool dim;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: LayoutBuilder(builder: (context, box) {
          final s = box.maxWidth;
          return Stack(clipBehavior: Clip.none, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: lit || winner ? const [Color(0xFFFFFFFF), Color(0xFFFFE07A)] : const [Color(0xFFFFE9A0), Color(0xFFF2B01E)]),
                border: Border.all(color: lit || winner ? Colors.white : const Color(0xFFE08A00), width: s * .045),
                boxShadow: [
                  if (lit || winner) BoxShadow(color: const Color(0xFFFFF59D).withValues(alpha: .9), blurRadius: s * .35, spreadRadius: s * .05),
                  const BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
                ],
              ),
              foregroundDecoration: dim ? const BoxDecoration(shape: BoxShape.circle, color: Color(0x66000000)) : null,
              child: Column(children: [
                SizedBox(height: s * .08),
                SizedBox(height: s * .56, child: art(food.art)),
                Text('x${food.mult}', style: TextStyle(color: const Color(0xFF7A3B00), fontWeight: FontWeight.w900, fontSize: s * .17, height: 1)),
              ]),
            ),
            if (mine > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF2E9D3A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 1.5)),
                  child: Text(compact(mine), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              ),
            if (total > 0 && total != mine)
              Positioned(
                left: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Text(compact(total), style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ),
          ]);
        }),
      );
}

class _GroupButton extends StatelessWidget {
  const _GroupButton({required this.food, required this.label, required this.mine, required this.onTap});
  final _Food food;
  final String label;
  final int mine;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            AspectRatio(aspectRatio: 1.3, child: art(food.art)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFFE07A), Color(0xFFE9A92A)]),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8A5A0A)),
              ),
              child: Text('$label x${food.mult}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF5A2A00), fontWeight: FontWeight.w900, fontSize: 13)),
            ),
          ]),
          if (mine > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF2E9D3A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 1.5)),
                child: Text(compact(mine), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
            ),
        ]),
      );
}
