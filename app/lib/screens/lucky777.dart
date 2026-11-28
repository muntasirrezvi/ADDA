import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'casino_kit.dart';
import 'games_kit.dart';
import '../widgets/gift_fx.dart' show MetalText;

/// Lucky 777: three reels, three rows, five lines. The result comes from the server. Coins only.
class Lucky777 extends StatefulWidget {
  const Lucky777({super.key, this.minBet = 1000});
  final int minBet;
  @override
  State<Lucky777> createState() => _Lucky777State();
}

const _symArt = {
  'seven': 'sym_seven',
  'bar': 'sym_bar',
  'bell': 'sym_bell',
  'melon': 'fruit_watermelon',
  'grape': 'sym_grape',
  'lemon': 'sym_lemon',
  'cherry': 'sym_cherry',
};
const _syms = ['seven', 'bar', 'bell', 'melon', 'grape', 'lemon', 'cherry'];
const _pays = {'seven': 500, 'bar': 150, 'bell': 90, 'melon': 45, 'grape': 28, 'lemon': 18, 'cherry': 13};
const _bets = [1000, 5000, 10000, 50000, 100000, 500000, 1000000, 5000000, 10000000, 50000000, 100000000, 500000000, 1000000000];

class _Lucky777State extends State<Lucky777> with TickerProviderStateMixin {
  final _rnd = math.Random();
  int _betIx = 0;
  bool _spinning = false;
  bool _auto = false;
  bool _muted = false;
  int _lastWin = 0;
  Map<String, dynamic>? _info;
  Map<String, dynamic>? _chests;
  List<String> _grid = ['bell', 'bell', 'bell', 'seven', 'seven', 'seven', 'grape', 'grape', 'grape'];
  List<Map> _lines = [];
  late List<List<String>> _strips = List.generate(3, (c) => [_grid[c], _grid[3 + c], _grid[6 + c]]);
  late final List<AnimationController> _reels = List.generate(3, (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 1200), animationBehavior: AnimationBehavior.preserve));
  late final AnimationController _big = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600), animationBehavior: AnimationBehavior.preserve);
  Timer? _infoTimer;

  int get _bet => _bets[_betIx];

  @override
  void initState() {
    super.initState();
    App.i.holdCoins(true);
    _betIx = _bets.indexWhere((b) => b >= widget.minBet).clamp(0, _bets.length - 1);
    _loadInfo();
    _infoTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadInfo());
  }

  @override
  void dispose() {
    App.i.holdCoins(false);
    _auto = false;
    _infoTimer?.cancel();
    for (final r in _reels) {
      r.dispose();
    }
    _big.dispose();
    Sfx.muted = false;
    super.dispose();
  }

  Future<void> _loadInfo() async {
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('slot_info') as Map);
      if (!mounted) return;
      final c = r['coins'] as num?;
      if (c != null && !_spinning) App.i.coins.value = c.toInt();
      setState(() {
        _info = r;
        _chests = Map<String, dynamic>.from(r['chests'] as Map);
      });
    } catch (_) {}
  }

  Future<void> _spin() async {
    if (_spinning) return;
    if (App.i.coins.value < _bet) {
      setState(() => _auto = false);
      toast(context, 'Not enough coins', bad: true);
      return;
    }
    setState(() {
      _spinning = true;
      _lines = [];
      _lastWin = 0;
    });
    App.i.coins.value -= _bet;
    Sfx.play('whoosh', volume: .6);
    // start the reels right away; the server answer decides where they stop
    for (var c = 0; c < 3; c++) {
      _strips[c] = [..._strips[c].take(3), for (var i = 0; i < 18 + c * 6; i++) _syms[_rnd.nextInt(_syms.length)]];
    }
    setState(() {});
    Map<String, dynamic> r;
    try {
      r = Map<String, dynamic>.from(await App.i.rpc('slot_spin', {'p_bet': _bet}) as Map);
    } catch (e) {
      App.i.coins.value += _bet;
      if (mounted) {
        toast(context, errText(e), bad: true);
        setState(() {
          _spinning = false;
          _auto = false;
        });
      }
      return;
    }
    if (!mounted) return;
    final grid = [for (final s in r['grid'] as List) '$s'];
    for (var c = 0; c < 3; c++) {
      _strips[c] = [..._strips[c], grid[c], grid[3 + c], grid[6 + c]];
    }
    setState(() {});
    final futures = <Future>[];
    for (var c = 0; c < 3; c++) {
      _reels[c]
        ..duration = Duration(milliseconds: 900 + c * 350)
        ..value = 0;
      futures.add(_reels[c].forward().then((_) => Sfx.play('tick', volume: .7)));
    }
    await Future.wait(futures);
    if (!mounted) return;
    final payout = (r['payout'] as num).toInt();
    setState(() {
      _grid = grid;
      _strips = List.generate(3, (c) => [grid[c], grid[3 + c], grid[6 + c]]);
      for (final rc in _reels) {
        rc.value = 0;
      }
      _lines = (r['lines'] as List).cast<Map>();
      _lastWin = payout;
      _chests = Map<String, dynamic>.from(r['chests'] as Map);
      _spinning = false;
    });
    if (payout > 0) {
      Sfx.play('win');
      Future.delayed(const Duration(milliseconds: 800), () => Sfx.play('coin'));
    }
    coinsAfterReveal((r['coins'] as num).toInt(), delayMs: r['big'] == true ? 1800 : (payout > 0 ? 800 : 0));
    if (r['big'] == true) {
      _big.forward(from: 0);
      _loadInfo();
      await Future.delayed(const Duration(milliseconds: 2200));
    }
    if (_auto && mounted) {
      await Future.delayed(Duration(milliseconds: payout > 0 ? 900 : 350));
      if (_auto && mounted) _spin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayWin = (_chests?['win'] as num? ?? 0).toInt();
    return Scaffold(
      backgroundColor: const Color(0xFF3A0A2A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF4A0E36), Color(0xFF2A0820), Color(0xFF5A3A10)]),
        ),
        child: SafeArea(
          child: Stack(children: [
            ListView(padding: const EdgeInsets.fromLTRB(10, 6, 10, 16), children: [
              _topBar(),
              const SizedBox(height: 8),
              _bigWins(),
              const SizedBox(height: 8),
              _machine(),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _Led(label: 'TOTAL BET', value: grouped(_bet))),
                const SizedBox(width: 6),
                Expanded(child: _Led(label: "TODAY'S WIN", value: grouped(todayWin), gold: true)),
                const SizedBox(width: 6),
                Expanded(child: _Led(label: 'WIN', value: _lastWin > 0 ? grouped(_lastWin) : '', gold: true)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _CabButton(label: 'BET\n−', onTap: _spinning || _auto || _betIx == 0 ? null : () => setState(() => _betIx--))),
                const SizedBox(width: 8),
                Expanded(child: _CabButton(label: 'BET\n+', onTap: _spinning || _auto || _betIx == _bets.length - 1 ? null : () => setState(() => _betIx++))),
                const SizedBox(width: 8),
                Expanded(child: _CabButton(label: _auto ? 'STOP' : 'AUTO', active: _auto, onTap: () {
                  setState(() => _auto = !_auto);
                  if (_auto && !_spinning) _spin();
                })),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: _CabButton(label: 'SPIN', big: true, onTap: _spinning || _auto ? null : _spin)),
              ]),
              const SizedBox(height: 12),
              ChestBar(state: _chests, onClaim: (lv) async {
                final r = await claimChest(context, 'slots777', lv);
                if (r != null && mounted) setState(() => _chests = r);
              }),
            ]),
            if (_big.isAnimating) Positioned.fill(child: IgnorePointer(child: _bigWinOverlay())),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() => Row(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
          decoration: BoxDecoration(color: const Color(0xFF5A1A6A), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE9B949), width: 2)),
          child: Row(children: [
            art('coin', size: 26),
            const SizedBox(width: 8),
            ValueListenableBuilder<int>(
              valueListenable: App.i.coins,
              builder: (_, c, __) => TweenAnimationBuilder<double>(
                tween: Tween(end: c.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(grouped(v.round()), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
              ),
            ),
          ]),
        ),
        const Spacer(),
        _RoundIcon(icon: _muted ? Icons.volume_off : Icons.volume_up, onTap: () => setState(() {
              _muted = !_muted;
              Sfx.muted = _muted;
            })),
        const SizedBox(width: 6),
        _RoundIcon(icon: Icons.question_mark, onTap: _help),
        const SizedBox(width: 6),
        _RoundIcon(icon: Icons.close, onTap: () => Navigator.maybePop(context)),
      ]);

  Widget _bigWins() {
    final wins = (_info?['big_wins'] as List? ?? const []).cast<Map>();
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF8A1E5A), Color(0xFF6A0E46)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9B949), width: 2),
      ),
      child: Row(children: [
        art('crown', size: 46),
        const SizedBox(width: 6),
        Expanded(
          child: wins.isEmpty
              ? const Center(child: Text('Big wins show here', style: TextStyle(color: Colors.white54)))
              : Row(children: [
                  for (final w in wins)
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Stack(alignment: Alignment.center, children: [
                          Avatar(profile: Map<String, dynamic>.from(w), size: 40),
                          Positioned(
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(color: const Color(0xFFD32F2F), borderRadius: BorderRadius.circular(6)),
                              child: const Text('BIG WIN', style: TextStyle(color: Color(0xFFFFE07A), fontSize: 8, fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text('${w['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11)),
                        Text(compact(w['payout'] as num), style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 11, fontWeight: FontWeight.w900)),
                      ]),
                    ),
                ]),
        ),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.circle, color: Color(0xFF6BE675), size: 10),
          Text('Online: ${_info?['online'] ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  Widget _machine() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9A2470), Color(0xFF6A1050)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE9B949), width: 3),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Row(children: [
          _bulbs(),
          const SizedBox(width: 4),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.05,
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFF2B01E), width: 4)),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(builder: (context, box) {
                  final cellH = box.maxHeight / 3;
                  return Stack(children: [
                    Row(children: [
                      for (var c = 0; c < 3; c++) ...[
                        if (c > 0) Container(width: 6, color: const Color(0xFFF2C230)),
                        Expanded(child: _reel(c, cellH)),
                      ],
                    ]),
                    Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _LinePainter(_lines.map((l) => (l['line'] as num).toInt()).toList())))),
                  ]);
                }),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _bulbs(),
        ]),
      );

  Widget _bulbs() => Column(children: [
        for (var i = 0; i < 9; i++)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (_spinning && (i + DateTime.now().second) % 2 == 0) || _lastWin > 0 ? const Color(0xFFFFF59D) : const Color(0xFFE9B949),
              boxShadow: const [BoxShadow(color: Color(0x88FFE07A), blurRadius: 4)],
            ),
          ),
      ]);

  Widget _reel(int c, double cellH) {
    final strip = _strips[c];
    return AnimatedBuilder(
      animation: _reels[c],
      builder: (_, __) {
        final t = Curves.easeOutCubic.transform(_reels[c].value.clamp(0.0, 1.0));
        final travel = (strip.length - 3) * cellH;
        final y = _reels[c].isAnimating || _reels[c].value > 0 ? -travel * t : 0.0;
        final blur = _reels[c].isAnimating && _reels[c].value < .85;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: strip.length * cellH,
            child: Transform.translate(
              offset: Offset(0, y),
              child: Column(children: [
                for (final s in strip)
                  SizedBox(
                    height: cellH,
                    child: Padding(
                      padding: EdgeInsets.all(cellH * .1),
                      child: Opacity(opacity: blur ? .75 : 1, child: art(_symArt[s] ?? 'sym_star')),
                    ),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _bigWinOverlay() => AnimatedBuilder(
        animation: _big,
        builder: (_, __) {
          final t = _big.value;
          final scale = Curves.elasticOut.transform((t * 2).clamp(0.0, 1.0));
          return Stack(children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: .45 * (1 - (t - .8).clamp(0.0, .2) * 5)))),
            Positioned.fill(child: CoinShower(progress: t)),
            Center(
              child: Transform.scale(
                scale: .3 + .7 * scale,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  MetalText('BIG WIN', size: 64, sweep: ((t - .2) / .5).clamp(0.0, 1.0)),
                  CountUp(_lastWin, size: 34),
                ]),
              ),
            ),
          ]);
        },
      );

  void _help() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Lucky 777', style: serif(22)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('5 lines: the three rows and the two diagonals. Your total bet is shared across the 5 lines. Three of a kind on a line pays:'),
            const SizedBox(height: 8),
            for (final s in _syms)
              Row(children: [
                for (var i = 0; i < 3; i++) art(_symArt[s]!, size: 22),
                const SizedBox(width: 8),
                Text('x${_pays[s]} line bet', style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            Row(children: [art('sym_cherry', size: 22), art('sym_cherry', size: 22), const SizedBox(width: 30), const Text('x2 line bet (first two)', style: TextStyle(fontWeight: FontWeight.w700))]),
            const SizedBox(height: 8),
            const Text('Coins only — no real money.', style: TextStyle(color: C.mute)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: C.gold)))],
        ),
      );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.lines);
  final List<int> lines;
  static const _colors = [Color(0xFFE53935), Color(0xFF43A047), Color(0xFF1E88E5), Color(0xFFFB8C00), Color(0xFF8E24AA)];
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Offset cell(int r, int c) => Offset(w * (c + .5) / 3, h * (r + .5) / 3);
    for (final l in lines) {
      final pts = switch (l) {
        0 => [cell(0, 0), cell(0, 2)],
        1 => [cell(1, 0), cell(1, 2)],
        2 => [cell(2, 0), cell(2, 2)],
        3 => [cell(0, 0), cell(2, 2)],
        _ => [cell(2, 0), cell(0, 2)],
      };
      final p = Paint()
        ..color = _colors[l % 5]
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      final ext = l >= 3 ? Offset.zero : Offset(w * .12, 0);
      canvas.drawLine(pts[0] - ext, pts[1] + ext, p..color = p.color.withValues(alpha: .85));
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.lines.join() != lines.join();
}

class _Led extends StatelessWidget {
  const _Led({required this.label, required this.value, this.gold = false});
  final String label;
  final String value;
  final bool gold;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(height: 3),
        Container(
          height: 40,
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(color: const Color(0xFF2A0A20), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF6A2A50), width: 2)),
          child: FittedBox(child: Text(value, style: TextStyle(color: gold ? const Color(0xFFFFD54F) : Colors.white, fontSize: 22, fontWeight: FontWeight.w900, fontFamily: 'monospace'))),
        ),
      ]);
}

class _CabButton extends StatefulWidget {
  const _CabButton({required this.label, required this.onTap, this.big = false, this.active = false});
  final String label;
  final VoidCallback? onTap;
  final bool big;
  final bool active;
  @override
  State<_CabButton> createState() => _CabButtonState();
}

class _CabButtonState extends State<_CabButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final off = widget.onTap == null;
    return GestureDetector(
      onTapDown: off ? null : (_) => setState(() => _down = true),
      onTapUp: off
          ? null
          : (_) {
              setState(() => _down = false);
              Sfx.play('pop', volume: .5);
              widget.onTap!();
            },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        height: 64,
        margin: EdgeInsets.only(top: _down ? 5 : 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF14707A),
          boxShadow: [if (!_down) const BoxShadow(color: Color(0xFF0A3A40), offset: Offset(0, 5))],
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: off ? const [Color(0xFF9E9E9E), Color(0xFF757575)] : (widget.active ? const [Color(0xFFFFE07A), Color(0xFFE9A92A)] : const [Color(0xFFFFFFFF), Color(0xFFCFD8DC)]),
            ),
            border: Border.all(color: const Color(0xFF4DD0E1), width: 2),
          ),
          child: Text(widget.label,
              textAlign: TextAlign.center,
              style: TextStyle(color: const Color(0xFF37474F), fontWeight: FontWeight.w900, fontSize: widget.big ? 26 : 14, height: 1.1, fontStyle: FontStyle.italic)),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF5A1A6A), border: Border.all(color: const Color(0xFFE9B949), width: 2)),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );
}
