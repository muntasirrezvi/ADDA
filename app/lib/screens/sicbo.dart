import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'casino_kit.dart';
import 'games_kit.dart';

/// Dice: Sic Bo with three dice. Put chips on the table, then roll. Coins only.
class SicBoGame extends StatefulWidget {
  const SicBoGame({super.key, this.minBet = 1000});
  final int minBet;
  @override
  State<SicBoGame> createState() => _SicBoGameState();
}

const _totalPays = {4: 61, 5: 31, 6: 18, 7: 13, 8: 9, 9: 7, 10: 7, 11: 7, 12: 7, 13: 9, 14: 13, 15: 18, 16: 31, 17: 61};

class _SicBoGameState extends State<SicBoGame> {
  final _rnd = math.Random();
  int _chip = 10000;
  Map<String, int> _bets = {};
  Map<String, int> _last = {};
  List<int> _dice = [1, 2, 3];
  Set<String> _winKeys = {};
  bool _rolling = false;
  int _frame = 0;
  int _lastWin = 0;
  Map<String, dynamic>? _chests;
  List _history = [];

  int get _total => _bets.values.fold(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _chip = casinoChips.firstWhere((c) => c >= math.max(widget.minBet, 10000), orElse: () => casinoChips.first);
    App.i.rpc('game_chests_info', {'p_game': 'sicbo'}).then((r) {
      if (mounted) setState(() => _chests = Map<String, dynamic>.from(r as Map));
    }).catchError((_) {});
  }

  void _place(String k) {
    if (_rolling) return;
    if (App.i.coins.value < _total + _chip) {
      toast(context, 'Not enough coins', bad: true);
      return;
    }
    Sfx.play('pop', volume: .5);
    setState(() {
      _bets[k] = (_bets[k] ?? 0) + _chip;
      _winKeys = {};
    });
  }

  Future<void> _roll() async {
    if (_rolling) return;
    if (_bets.isEmpty) {
      if (_last.isNotEmpty) {
        setState(() => _bets = Map.of(_last));
      } else {
        toast(context, 'Tap the table to place chips first');
        return;
      }
    }
    setState(() {
      _rolling = true;
      _winKeys = {};
      _lastWin = 0;
    });
    Sfx.play('dice');
    final anim = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted) setState(() => _frame = _rnd.nextInt(8));
    });
    Map<String, dynamic>? r;
    try {
      final res = await Future.wait([
        App.i.rpc('sicbo_roll', {'p_bets': _bets}),
        Future.delayed(const Duration(milliseconds: 1300)),
      ]);
      r = Map<String, dynamic>.from(res[0] as Map);
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    anim.cancel();
    if (!mounted) return;
    if (r == null) {
      setState(() => _rolling = false);
      return;
    }
    final res = r;
    final payout = (r['payout'] as num).toInt();
    App.i.coins.value = (r['coins'] as num).toInt();
    setState(() {
      _dice = [for (final d in res['dice'] as List) (d as num).toInt()];
      _winKeys = (res['wins'] as Map).keys.map((e) => '$e').toSet();
      _lastWin = payout;
      _chests = Map<String, dynamic>.from(res['chests'] as Map);
      _history = (res['history'] as List? ?? const []);
      _last = Map.of(_bets);
      _bets = {};
      _rolling = false;
    });
    Sfx.play(payout > 0 ? 'win' : 'lose');
    if (payout > 0) Future.delayed(const Duration(milliseconds: 250), () => Sfx.play('coin'));
  }

  @override
  Widget build(BuildContext context) {
    final sum = _dice.fold(0, (a, b) => a + b);
    final triple = _dice[0] == _dice[1] && _dice[1] == _dice[2];
    return Scaffold(
      backgroundColor: const Color(0xFF07301C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Dice · Sic Bo'),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: _help),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(grouped(c)))),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.6), radius: 1.2, colors: [Color(0xFF1F8A4C), Color(0xFF0D5A30), Color(0xFF052414)])),
        child: ListView(padding: const EdgeInsets.fromLTRB(10, 0, 10, 16), children: [
          // dice bowl
          Container(
            height: 130,
            margin: const EdgeInsets.symmetric(horizontal: 30),
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(70),
              gradient: const RadialGradient(colors: [Color(0xFFF5E6C8), Color(0xFFC9A66B), Color(0xFF7A5A28)]),
              border: Border.all(color: const Color(0xFFE9B949), width: 4),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _rolling
                      ? Transform.rotate(angle: (_frame + i) * .7, child: art('die_roll_${(_frame + i * 3) % 8}', size: 66))
                      : art('die_${_dice[i]}', size: 66),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              _rolling ? 'Rolling…' : (triple ? 'Triple $sum' : '$sum · ${sum >= 11 ? 'BIG' : 'SMALL'} · ${sum.isOdd ? 'ODD' : 'EVEN'}'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
          if (_lastWin > 0) Center(child: SizedBox(height: 44, child: CountUp(_lastWin, size: 28))),
          const SizedBox(height: 8),
          // table
          Row(children: [
            Expanded(child: _cell('small', 'SMALL', '4–10 · x2', h: 70)),
            Expanded(child: _cell('any_triple', 'ANY TRIPLE', 'x31', h: 70)),
            Expanded(child: _cell('big', 'BIG', '11–17 · x2', h: 70)),
          ]),
          Row(children: [
            Expanded(child: _cell('odd', 'ODD', 'x2')),
            Expanded(child: _cell('even', 'EVEN', 'x2')),
          ]),
          for (final row in const [[4, 5, 6, 7, 8, 9, 10], [11, 12, 13, 14, 15, 16, 17]])
            Row(children: [for (final t in row) Expanded(child: _cell('total_$t', '$t', 'x${_totalPays[t]}', h: 58, small: true))]),
          Row(children: [
            for (var n = 1; n <= 6; n++)
              Expanded(child: _cell('single_$n', '', 'x2–4', h: 64, small: true, icon: 'die_$n')),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final c in casinoChips.where((c) => c >= widget.minBet))
                GestureDetector(
                  onTap: () => setState(() => _chip = c),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4), child: PokerChip(value: c, size: 50, selected: c == _chip)),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _rolling || _bets.isEmpty ? null : () => setState(() => _bets = {}),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), minimumSize: const Size(0, 50)),
                child: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: PressButton(
                label: _bets.isEmpty && _last.isNotEmpty ? 'REBET & ROLL ${compact(_last.values.fold(0, (a, b) => a + b))}' : 'ROLL ${_total > 0 ? compact(_total) : ''}',
                busy: _rolling,
                onTap: _roll,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          ChestBar(state: _chests, onClaim: (lv) async {
            final r = await claimChest(context, 'sicbo', lv);
            if (r != null && mounted) setState(() => _chests = r);
          }),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 10),
            GoldPanel(
              color: const Color(0xFF0D4A2A),
              child: Row(children: [
                const Text('Last', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final h in _history)
                        Builder(builder: (_) {
                          final s = ((h as Map)['sum'] as num? ?? 0).toInt();
                          return Container(
                            margin: const EdgeInsets.only(right: 5),
                            width: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: s >= 11 ? const Color(0xFFC62828) : const Color(0xFF1565C0)),
                            child: Text('$s', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                          );
                        }),
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

  Widget _cell(String k, String title, String sub, {double h = 52, bool small = false, String? icon}) {
    final mine = _bets[k] ?? 0;
    final won = _winKeys.contains(k);
    return GestureDetector(
      onTap: () => _place(k),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: h,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: won ? const Color(0xFFFFD54F).withValues(alpha: .35) : const Color(0x22000000),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: won ? const Color(0xFFFFE07A) : const Color(0xFFE9B949).withValues(alpha: .7), width: won ? 2.5 : 1.2),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) art(icon, size: 28),
            if (title.isNotEmpty) Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: small ? 15 : 16)),
            Text(sub, style: TextStyle(color: const Color(0xFFFFE07A), fontSize: small ? 9 : 11, fontWeight: FontWeight.w700)),
          ]),
          if (mine > 0) Positioned(right: 2, top: 2, child: PokerChip(value: mine, size: small ? 22 : 28)),
        ]),
      ),
    );
  }

  void _help() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Sic Bo', style: serif(22)),
          content: const SingleChildScrollView(
            child: Text(
              'Put chips anywhere on the table, then ROLL. Three dice are rolled.\n\n'
              '• Small (4–10) / Big (11–17): x2. Lose on any triple.\n'
              '• Odd / Even: x2. Lose on any triple.\n'
              '• Any triple (all three the same): x31.\n'
              '• Total: x7 to x61 if the three dice add up to it.\n'
              '• Single number: x2 if one die shows it, x3 for two, x4 for three.\n\n'
              'Numbers include your bet. Coins only — no real money.',
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: C.gold)))],
        ),
      );
}
