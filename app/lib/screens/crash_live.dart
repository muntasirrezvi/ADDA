import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'casino_kit.dart';
import 'games_kit.dart';

/// Rocket: live crash rounds for everyone. Bet in the 7 s window, the rocket takes off and the
/// multiplier climbs. Cash out before it explodes. Coins only.
class CrashLive extends StatefulWidget {
  const CrashLive({super.key, this.minBet = 1000});
  final int minBet;
  @override
  State<CrashLive> createState() => _CrashLiveState();
}

class _CrashLiveState extends State<CrashLive> {
  Map<String, dynamic>? _s;
  int _offset = 0;
  int _amount = 10000;
  bool _autoOn = false;
  double _auto = 2.0;
  bool _busy = false;
  bool _loading = false;
  int? _boomRound;
  Timer? _frame;
  Timer? _poll;

  int get _now => DateTime.now().millisecondsSinceEpoch + _offset;
  String get _phase => '${_s?['phase'] ?? 'bet'}';
  double get _k => (_s?['k'] as num? ?? .09).toDouble();
  double get _t => math.max(0, (_now - ((_s?['fly_ms'] as num?) ?? _now).toInt()) / 1000);
  double get _mult => _phase == 'crashed' ? (_s?['crash'] as num? ?? 1).toDouble() : (_phase == 'fly' ? (math.exp(_k * _t) * 100).floor() / 100 : 1.0);
  Map? get _me => _s?['me'] as Map?;

  @override
  void initState() {
    super.initState();
    App.i.holdCoins(true);
    _amount = math.max(widget.minBet, 10000);
    _load();
    _frame = Timer.periodic(const Duration(milliseconds: 50), (_) => _onFrame());
    _poll = Timer.periodic(const Duration(milliseconds: 900), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    App.i.holdCoins(false);
    _frame?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (_loading) return;
    _loading = true;
    try {
      final s = Map<String, dynamic>.from(await App.i.rpc('crash_state') as Map);
      if (!mounted) return;
      _offset = (s['now_ms'] as num).toInt() - DateTime.now().millisecondsSinceEpoch;
      final c = s['coins'] as num?;
      if (c != null && !_busy) App.i.coins.value = c.toInt();
      if (s['phase'] == 'crashed' && _boomRound != s['round']) {
        _boomRound = (s['round'] as num).toInt();
        final me = s['me'] as Map?;
        if (me != null && me['cashed'] == null) Sfx.play('boom');
        if (me != null && me['cashed'] != null && (me['auto'] != null)) Sfx.play('coin');
      }
      setState(() => _s = s);
    } catch (e) {
      if (!quiet && mounted) toast(context, errText(e), bad: true);
    } finally {
      _loading = false;
    }
  }

  void _onFrame() {
    if (_s == null) return;
    if (_phase == 'fly') {
      final me = _me;
      // auto cash out is done by the server; show it the moment the multiplier passes the target
      if (me != null && me['cashed'] == null && me['auto'] != null && _mult >= (me['auto'] as num).toDouble()) {
        Sfx.play('coin');
        setState(() => _s = {..._s!, 'me': {...me, 'cashed': me['auto'], 'win': ((me['amount'] as num) * (me['auto'] as num)).floor()}});
        return;
      }
    }
    setState(() {});
  }

  Future<void> _bet() async {
    if (_busy) return;
    if (App.i.coins.value < _amount) {
      toast(context, 'Not enough coins', bad: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('crash_bet', {'p_amount': _amount, 'p_auto': _autoOn ? _auto : null}) as Map);
      App.i.coins.value = (r['coins'] as num).toInt();
      Sfx.play('pop');
      await _load(quiet: true);
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cashout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('crash_cashout') as Map);
      App.i.coins.value = (r['coins'] as num).toInt();
      Sfx.play('win');
      Future.delayed(const Duration(milliseconds: 200), () => Sfx.play('coin'));
      if (mounted) {
        setState(() => _s = {...?_s, 'me': {...?_me, 'cashed': r['cashed'], 'win': r['win']}, 'chests': r['chests']});
      }
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
      _load(quiet: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0820),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Rocket'),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: _help),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: const Center(child: LiveCoins()),
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator(color: C.gold))
          : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
              _historyRow(),
              const SizedBox(height: 8),
              _sky(),
              const SizedBox(height: 10),
              _betPanel(),
              const SizedBox(height: 10),
              ChestBar(state: s['chests'] as Map<String, dynamic>?, onClaim: (lv) async {
                final r = await claimChest(context, 'crash', lv);
                if (r != null && mounted) setState(() => _s = {...?_s, 'chests': r});
              }),
              const SizedBox(height: 10),
              _players(),
            ]),
    );
  }

  Color _cpColor(num v) => v >= 10 ? const Color(0xFFE040FB) : (v >= 2 ? const Color(0xFF7C4DFF) : const Color(0xFF29B6F6));

  Widget _historyRow() {
    final h = (_s?['history'] as List? ?? const []);
    return SizedBox(
      height: 30,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final v in h)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15)),
            child: Text('${(v as num).toStringAsFixed(2)}x', style: TextStyle(color: _cpColor(v), fontWeight: FontWeight.w900)),
          ),
      ]),
    );
  }

  Widget _sky() {
    final phase = _phase;
    final m = _mult;
    final flyMs = ((_s!['fly_ms'] as num?) ?? 0).toInt();
    final wait = math.max(0, (flyMs - _now) / 1000);
    final nextMs = (_s!['next_ms'] as num?)?.toInt();
    return AspectRatio(
      aspectRatio: 1.25,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const RadialGradient(center: Alignment(-.6, .9), radius: 1.4, colors: [Color(0xFF3B1E7A), Color(0xFF160E3A), Color(0xFF0A0620)]),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final t = phase == 'fly' ? _t : (phase == 'crashed' ? math.log(m) / _k : 0.0);
          final tMax = math.max(8.0, t * 1.15);
          final mMax = math.max(2.0, math.exp(_k * t) * 1.2);
          Offset pt(double tt) => Offset(w * .06 + (w * .86) * (tt / tMax), h * .9 - (h * .78) * ((math.exp(_k * tt) - 1) / (mMax - 1)));
          final tip = pt(t);
          final before = pt(math.max(0, t - .3));
          final ang = math.atan2(tip.dy - before.dy, tip.dx - before.dx);
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _SkyPainter(t: t, pt: pt, crashed: phase == 'crashed', show: phase != 'bet'))),
            if (phase != 'bet' && phase != 'crashed')
              Positioned(
                left: tip.dx - 32,
                top: tip.dy - 32,
                width: 64,
                height: 64,
                child: Transform.rotate(angle: ang + math.pi / 4 + .2, child: art('rocket')),
              ),
            if (phase == 'crashed')
              Positioned(left: tip.dx - 40, top: tip.dy - 40, width: 80, height: 80, child: art('bomb')),
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (phase == 'bet') ...[
                  const Text('Next round in', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                  Text('${wait.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  SizedBox(width: w * .5, child: LinearProgressIndicator(value: (wait / 7).clamp(0.0, 1.0), color: C.gold, backgroundColor: Colors.white12)),
                ] else if (phase == 'crashed') ...[
                  const Text('FLEW AWAY!', style: TextStyle(color: Color(0xFFFF5252), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  Text('${m.toStringAsFixed(2)}x', style: const TextStyle(color: Color(0xFFFF5252), fontSize: 54, fontWeight: FontWeight.w900)),
                  if (nextMs != null) Text('Next round in ${math.max(0, (nextMs - _now) / 1000).toStringAsFixed(0)}s', style: const TextStyle(color: Colors.white54)),
                ] else
                  Text('${m.toStringAsFixed(2)}x', style: const TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.w900, shadows: [Shadow(color: Color(0xFF7C4DFF), blurRadius: 24)])),
              ]),
            ),
            Positioned(
              right: 10,
              top: 8,
              child: Row(children: [
                const Icon(Icons.people_alt, size: 15, color: Colors.white60),
                const SizedBox(width: 4),
                Text('${_s!['count'] ?? 0}', style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _betPanel() {
    final me = _me;
    final phase = _phase;
    Widget button;
    if (me == null) {
      button = PressButton(
        label: phase == 'bet' ? 'BET ${compact(_amount)}' : 'Wait for the next round',
        color: const Color(0xFF2E9D3A),
        busy: _busy,
        onTap: phase == 'bet' ? _bet : null,
      );
    } else if (me['cashed'] != null) {
      button = PressButton(label: 'WON ${compact(me['win'] as num)} at ${(me['cashed'] as num).toStringAsFixed(2)}x', color: const Color(0xFF2E9D3A), onTap: null);
    } else if (phase == 'fly') {
      button = PressButton(label: 'CASH OUT ${compact(((me['amount'] as num) * _mult).floor())}', color: const Color(0xFFFF8F00), busy: _busy, onTap: _cashout);
    } else if (phase == 'bet') {
      button = PressButton(label: 'BET PLACED · ${compact(me['amount'] as num)}', color: const Color(0xFF455A64), onTap: null);
    } else {
      button = PressButton(label: 'LOST ${compact(me['amount'] as num)}', color: const Color(0xFFC62828), onTap: null);
    }
    final canEdit = me == null;
    return GoldPanel(
      color: const Color(0xFF1C1440),
      child: Column(children: [
        Row(children: [
          _Step(icon: Icons.remove, onTap: canEdit ? () => setState(() => _amount = math.max(widget.minBet, _amount ~/ 2)) : null),
          Expanded(
            child: Column(children: [
              const Text('Bet', style: TextStyle(color: Colors.white54, fontSize: 12)),
              Text(grouped(_amount), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            ]),
          ),
          _Step(icon: Icons.add, onTap: canEdit ? () => setState(() => _amount = _amount * 2) : null),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final c in casinoChips.where((c) => c >= widget.minBet))
              GestureDetector(
                onTap: canEdit ? () => setState(() => _amount = c) : null,
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: PokerChip(value: c, size: 42, selected: c == _amount)),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Switch(value: _autoOn, activeThumbColor: C.gold, onChanged: canEdit ? (v) => setState(() => _autoOn = v) : null),
          const Text('Auto cash out', style: TextStyle(color: Colors.white)),
          const Spacer(),
          _Step(icon: Icons.remove, small: true, onTap: canEdit && _autoOn ? () => setState(() => _auto = math.max(1.1, ((_auto - (_auto > 5 ? 1 : .1)) * 10).round() / 10)) : null),
          SizedBox(width: 64, child: Text('${_auto.toStringAsFixed(1)}x', textAlign: TextAlign.center, style: TextStyle(color: _autoOn ? C.gold : Colors.white38, fontWeight: FontWeight.w900, fontSize: 16))),
          _Step(icon: Icons.add, small: true, onTap: canEdit && _autoOn ? () => setState(() => _auto = math.min(1000, ((_auto + (_auto >= 5 ? 1 : .1)) * 10).round() / 10)) : null),
        ]),
        const SizedBox(height: 6),
        button,
      ]),
    );
  }

  Widget _players() {
    final ps = (_s?['players'] as List? ?? const []).cast<Map>();
    return GoldPanel(
      color: const Color(0xFF1C1440),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Players this round (${_s?['count'] ?? 0})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (ps.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No bets yet — be the first', style: TextStyle(color: Colors.white54))),
        for (final p in ps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Avatar(profile: Map<String, dynamic>.from(p), size: 30),
              const SizedBox(width: 8),
              Expanded(child: Text('${p['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
              Text(compact(p['amount'] as num), style: const TextStyle(color: Colors.white70)),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: Text(
                  p['cashed'] != null ? '${(p['cashed'] as num).toStringAsFixed(2)}x  +${compact(p['win'] as num)}' : (_phase == 'crashed' ? 'lost' : '—'),
                  textAlign: TextAlign.right,
                  style: TextStyle(color: p['cashed'] != null ? const Color(0xFF6BE675) : Colors.white38, fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  void _help() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('How to play Rocket', style: serif(22)),
          content: const Text(
            'Everyone plays the same flight.\n\n'
            '1. Place your bet in the 7 second window before take-off.\n'
            '2. The rocket climbs and the multiplier grows: 1.5x, 2x, 10x, 100x…\n'
            '3. Tap CASH OUT any time to win your bet × the multiplier.\n'
            '4. If the rocket explodes before you cash out, the bet is lost.\n\n'
            'Auto cash out takes your winnings for you at the multiplier you set.\n\n'
            'Coins only — no real money.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: C.gold)))],
        ),
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap, this.small = false});
  final IconData icon;
  final VoidCallback? onTap;
  final bool small;
  @override
  Widget build(BuildContext context) => Material(
        color: onTap == null ? Colors.white10 : const Color(0xFF3A2C7A),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: EdgeInsets.all(small ? 6 : 10), child: Icon(icon, color: Colors.white, size: small ? 16 : 22)),
        ),
      );
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({required this.t, required this.pt, required this.crashed, required this.show});
  final double t;
  final Offset Function(double) pt;
  final bool crashed;
  final bool show;
  static final _stars = List.generate(50, (i) => Offset(math.Random(i).nextDouble(), math.Random(i * 7 + 1).nextDouble()));
  @override
  void paint(Canvas canvas, Size s) {
    final sp = Paint()..color = Colors.white24;
    for (final o in _stars) {
      canvas.drawCircle(Offset(o.dx * s.width, o.dy * s.height), 1.2, sp);
    }
    final grid = Paint()..color = Colors.white10..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(Offset(0, s.height * i / 5), Offset(s.width, s.height * i / 5), grid);
    }
    if (!show || t <= 0) return;
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    const n = 60;
    for (var i = 1; i <= n; i++) {
      final p = pt(t * i / n);
      path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(pt(t).dx, pt(0).dy)
      ..close();
    final col = crashed ? const Color(0xFFFF5252) : const Color(0xFFE040FB);
    canvas.drawPath(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [col.withValues(alpha: .45), col.withValues(alpha: .02)]).createShader(Offset.zero & s));
    canvas.drawPath(path, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_SkyPainter o) => true;
}
