import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'casino_kit.dart';
import 'games_kit.dart';

/// Lucky Wheel: the casino Big Six wheel. 54 segments; bet on which one the pointer stops on.
class BigSixGame extends StatefulWidget {
  const BigSixGame({super.key, this.minBet = 1000});
  final int minBet;
  @override
  State<BigSixGame> createState() => _BigSixGameState();
}

const _keys = ['1', '2', '5', '10', '20', 'joker', 'logo'];
const _segColor = {
  '1': Color(0xFFF2C230),
  '2': Color(0xFF1E88E5),
  '5': Color(0xFF8E24AA),
  '10': Color(0xFF43A047),
  '20': Color(0xFFE65100),
  'joker': Color(0xFFD32F2F),
  'logo': Color(0xFF111111),
};
String _label(String k) => k == 'joker' ? '★' : (k == 'logo' ? 'A' : k);

class _BigSixGameState extends State<BigSixGame> with SingleTickerProviderStateMixin {
  List<String> _segs = const [];
  Map<String, num> _mults = const {};
  Map<String, dynamic>? _chests;
  List _history = [];
  int _chip = 10000;
  Map<String, int> _bets = {};
  Map<String, int> _last = {};
  bool _spinning = false;
  String? _hit;
  int _lastWin = 0;
  double _angle = 0; // wheel rotation in turns
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  Animation<double>? _spin;

  int get _total => _bets.values.fold(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _chip = casinoChips.firstWhere((c) => c >= math.max(widget.minBet, 10000), orElse: () => casinoChips.first);
    _load();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('bigsix_info') as Map);
      if (!mounted) return;
      setState(() {
        _segs = [for (final s in r['segments'] as List) '$s'];
        _mults = {for (final e in (r['mults'] as Map).entries) '${e.key}': e.value as num};
        _chests = Map<String, dynamic>.from(r['chests'] as Map);
        _history = r['history'] as List? ?? const [];
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
  }

  void _place(String k) {
    if (_spinning) return;
    if (App.i.coins.value < _total + _chip) {
      toast(context, 'Not enough coins', bad: true);
      return;
    }
    Sfx.play('pop', volume: .5);
    setState(() {
      _bets[k] = (_bets[k] ?? 0) + _chip;
      _hit = null;
    });
  }

  Future<void> _go() async {
    if (_spinning || _segs.isEmpty) return;
    if (_bets.isEmpty) {
      if (_last.isEmpty) {
        toast(context, 'Tap a bet below to place chips first');
        return;
      }
      setState(() => _bets = Map.of(_last));
    }
    setState(() {
      _spinning = true;
      _hit = null;
      _lastWin = 0;
    });
    Map<String, dynamic> r;
    try {
      r = Map<String, dynamic>.from(await App.i.rpc('bigsix_spin', {'p_bets': _bets}) as Map);
    } catch (e) {
      if (mounted) {
        toast(context, errText(e), bad: true);
        setState(() => _spinning = false);
      }
      return;
    }
    final idx = (r['index'] as num).toInt();
    // segment idx must end under the pointer at the top: rotation = -(idx + .5) / 54 turns (mod 1)
    final start = _angle;
    var target = -(idx + .5) / _segs.length;
    target = target - target.floorToDouble();
    final base = start.floorToDouble();
    var end = base + 5 + target;
    if (end - start < 4) end += 1;
    _spin = Tween(begin: start, end: end).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutQuart));
    var lastSeg = -1;
    void tick() {
      final seg = (((-_spin!.value) % 1 + 1) % 1 * _segs.length).floor();
      if (seg != lastSeg) {
        lastSeg = seg;
        Sfx.play('tick', volume: .25);
      }
    }

    _spin!.addListener(tick);
    await _c.forward(from: 0);
    _spin!.removeListener(tick);
    if (!mounted) return;
    final payout = (r['payout'] as num).toInt();
    App.i.coins.value = (r['coins'] as num).toInt();
    setState(() {
      _angle = end;
      _hit = '${r['segment']}';
      _lastWin = payout;
      _chests = Map<String, dynamic>.from(r['chests'] as Map);
      _history = ['${r['segment']}', ..._history].take(15).toList();
      _last = Map.of(_bets);
      _bets = {};
      _spinning = false;
    });
    Sfx.play(payout > 0 ? 'win' : 'lose');
    if (payout > 0) Future.delayed(const Duration(milliseconds: 250), () => Sfx.play('coin'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A1406),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Lucky Wheel'),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: _help),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(grouped(c)))),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.4), radius: 1.2, colors: [Color(0xFF7A3A10), Color(0xFF3A1A06), Color(0xFF140802)])),
        child: _segs.isEmpty
            ? const Center(child: CircularProgressIndicator(color: C.gold))
            : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Stack(alignment: Alignment.center, children: [
                    AnimatedBuilder(
                      animation: _c,
                      builder: (_, __) => Transform.rotate(
                        angle: (_spin?.value ?? _angle) * 2 * math.pi,
                        child: CustomPaint(size: Size.infinite, painter: _WheelPainter(_segs)),
                      ),
                    ),
                    // hub
                    Container(
                      width: 70,
                      height: 70,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xFFFFF3B0), Color(0xFFE9A92A), Color(0xFF8A5A0A)]), boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)]),
                      child: Center(child: art('crown', size: 40)),
                    ),
                    // pointer
                    Positioned(top: 0, child: CustomPaint(size: const Size(34, 40), painter: _PointerPainter())),
                    if (_hit != null)
                      Positioned(
                        bottom: 18,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: _segColor[_hit]!, width: 2)),
                          child: Text(_lastWin > 0 ? '${_label(_hit!)}  ·  +${grouped(_lastWin)}' : '${_label(_hit!)}  ·  no win',
                              style: TextStyle(color: _lastWin > 0 ? const Color(0xFFFFE07A) : Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 1.05,
                  children: [for (final k in _keys) _betCell(k)],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 60,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final c in casinoChips.where((c) => c >= widget.minBet))
                      GestureDetector(
                        onTap: () => setState(() => _chip = c),
                        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4), child: PokerChip(value: c, size: 48, selected: c == _chip)),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _spinning || _bets.isEmpty ? null : () => setState(() => _bets = {}),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), minimumSize: const Size(0, 50)),
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: PressButton(
                      label: _bets.isEmpty && _last.isNotEmpty ? 'REBET & SPIN' : 'SPIN ${_total > 0 ? compact(_total) : ''}',
                      busy: _spinning,
                      onTap: _go,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                ChestBar(state: _chests, onClaim: (lv) async {
                  final r = await claimChest(context, 'bigsix', lv);
                  if (r != null && mounted) setState(() => _chests = r);
                }),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GoldPanel(
                    color: const Color(0xFF4A2408),
                    child: Row(children: [
                      const Text('Result', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 30,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            for (final h in _history)
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                width: 30,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: _segColor['$h'] ?? Colors.grey),
                                child: Text(_label('$h'), style: TextStyle(color: '$h' == '1' ? Colors.black : Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                              ),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ],
              ]),
      ),
    );
  }

  Widget _betCell(String k) {
    final mine = _bets[k] ?? 0;
    final won = _hit == k;
    final count = _segs.where((s) => s == k).length;
    final c = _segColor[k]!;
    return GestureDetector(
      onTap: () => _place(k),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(c, Colors.white, .2)!, c]),
          border: Border.all(color: won ? Colors.white : const Color(0xFFE9B949), width: won ? 3 : 1.5),
          boxShadow: [if (won) const BoxShadow(color: Color(0xAAFFE07A), blurRadius: 14)],
        ),
        child: Stack(alignment: Alignment.center, children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_label(k), style: TextStyle(color: k == '1' ? Colors.black : Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            Text('x${_mults[k] ?? ''}', style: TextStyle(color: k == '1' ? Colors.black87 : Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
            Text('$count/54', style: TextStyle(color: (k == '1' ? Colors.black : Colors.white).withValues(alpha: .6), fontSize: 9)),
          ]),
          if (mine > 0) Positioned(right: 2, top: 2, child: PokerChip(value: mine, size: 26)),
        ]),
      ),
    );
  }

  void _help() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Lucky Wheel (Big Six)', style: serif(22)),
          content: const Text(
            'The wheel has 54 segments: 24 × "1", 15 × "2", 7 × "5", 4 × "10", 2 × "20", one ★ and one A.\n\n'
            'Put chips on one or more values, then SPIN. If the pointer stops on a value you bet on, you win your bet × its number.\n\n'
            'Numbers include your bet. Coins only — no real money.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: C.gold)))],
        ),
      );
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.segs);
  final List<String> segs;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 6;
    final n = segs.length;
    final sweep = 2 * math.pi / n;
    // rim
    canvas.drawCircle(c, r + 6, Paint()..shader = const RadialGradient(colors: [Color(0xFFFFE9A8), Color(0xFFB8741A)]).createShader(Rect.fromCircle(center: c, radius: r + 6)));
    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * sweep;
      final col = _segColor[segs[i]] ?? Colors.grey;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, true, Paint()..color = col);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, true, Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 1);
      // label
      final mid = start + sweep / 2;
      canvas.save();
      canvas.translate(c.dx + math.cos(mid) * r * .82, c.dy + math.sin(mid) * r * .82);
      canvas.rotate(mid + math.pi / 2);
      final tp = TextPainter(
        text: TextSpan(text: _label(segs[i]), style: TextStyle(color: segs[i] == '1' ? Colors.black : Colors.white, fontWeight: FontWeight.w900, fontSize: r * .085)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    // pegs
    final peg = Paint()..color = const Color(0xFFFFF3B0);
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * sweep;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * (r + 1), 2.6, peg);
    }
    canvas.drawCircle(c, r * .55, Paint()..color = const Color(0x33000000));
  }

  @override
  bool shouldRepaint(_WheelPainter o) => o.segs != segs;
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close();
    canvas.drawShadow(p, Colors.black, 4, false);
    canvas.drawPath(p, Paint()..shader = const LinearGradient(colors: [Color(0xFFFFF3B0), Color(0xFFE9A92A)]).createShader(Offset.zero & s));
    canvas.drawPath(p, Paint()..color = const Color(0xFF8A5A0A)..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_) => false;
}
