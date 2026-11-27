import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'casino_kit.dart';
import 'games_kit.dart';

/// Gems (Mines): 25 tiles hide gems and bombs. Each gem you find raises the multiplier.
/// Cash out any time; hit a bomb and the bet is lost. Coins only.
class MinesGame extends StatefulWidget {
  const MinesGame({super.key, this.minBet = 1000});
  final int minBet;
  @override
  State<MinesGame> createState() => _MinesGameState();
}

const _gemArts = ['gem_diamond', 'gem_ruby', 'gem_emerald', 'gem_sapphire', 'gem_amethyst', 'gem_topaz'];

class _MinesGameState extends State<MinesGame> {
  Map<String, dynamic>? _g; // current or last game
  Map<String, dynamic>? _chests;
  List _history = [];
  int _bet = 10000;
  int _bombs = 3;
  bool _busy = false;
  bool _loaded = false;
  int? _boomTile;

  bool get _playing => _g?['status'] == 'playing';
  Set<int> get _picks => {for (final p in (_g?['picks'] as List? ?? const [])) (p as num).toInt()};
  Set<int> get _board => {for (final p in (_g?['board'] as List? ?? const [])) (p as num).toInt()};

  @override
  void initState() {
    super.initState();
    _bet = math.max(widget.minBet, 10000);
    _load();
  }

  Future<void> _load() async {
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('mines_active') as Map);
      if (!mounted) return;
      setState(() {
        _g = r['game'] == null ? null : Map<String, dynamic>.from(r['game'] as Map);
        if (_g != null) {
          _bet = (_g!['bet'] as num).toInt();
          _bombs = (_g!['bombs'] as num).toInt();
        }
        _chests = Map<String, dynamic>.from(r['chests'] as Map);
        _history = r['history'] as List? ?? const [];
        _loaded = true;
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    if (App.i.coins.value < _bet) {
      toast(context, 'Not enough coins', bad: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('mines_start', {'p_bet': _bet, 'p_bombs': _bombs}) as Map);
      App.i.coins.value = (r['coins'] as num).toInt();
      Sfx.play('whoosh', volume: .5);
      setState(() {
        _g = Map<String, dynamic>.from(r['game'] as Map);
        _chests = Map<String, dynamic>.from(r['chests'] as Map);
        _boomTile = null;
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pick(int t) async {
    if (_busy || !_playing || _picks.contains(t)) return;
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('mines_pick', {'p_game': _g!['id'], 'p_tile': t}) as Map);
      App.i.coins.value = (r['coins'] as num).toInt();
      final g = Map<String, dynamic>.from(r['game'] as Map);
      if (r['boom'] == true) {
        Sfx.play('boom');
        _boomTile = t;
        _history = [{'mult': 0}, ..._history].take(15).toList();
      } else {
        Sfx.play(g['status'] == 'cashed' ? 'win' : 'coin', volume: .7);
        if (g['status'] == 'cashed') _history = [{'mult': g['mult']}, ..._history].take(15).toList();
      }
      setState(() {
        _g = g;
        if (r['chests'] != null) _chests = Map<String, dynamic>.from(r['chests'] as Map);
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cashout() async {
    if (_busy || !_playing) return;
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('mines_cashout', {'p_game': _g!['id']}) as Map);
      App.i.coins.value = (r['coins'] as num).toInt();
      Sfx.play('win');
      Future.delayed(const Duration(milliseconds: 250), () => Sfx.play('coin'));
      final g = Map<String, dynamic>.from(r['game'] as Map);
      setState(() {
        _g = g;
        _chests = Map<String, dynamic>.from(r['chests'] as Map);
        _history = [{'mult': g['mult']}, ..._history].take(15).toList();
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    final mult = (g?['mult'] as num? ?? 1).toDouble();
    final next = g?['next'] as num?;
    final status = '${g?['status'] ?? ''}';
    return Scaffold(
      backgroundColor: const Color(0xFF0A1830),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Gems'),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: _help),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(grouped(c)))),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.5), radius: 1.2, colors: [Color(0xFF1E4A8A), Color(0xFF0E2650), Color(0xFF050C1C)])),
        child: !_loaded
            ? const Center(child: CircularProgressIndicator(color: C.gold))
            : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
                // status bar
                Row(children: [
                  Expanded(child: _Stat(label: 'Multiplier', value: '${mult.toStringAsFixed(2)}x', gold: true)),
                  const SizedBox(width: 6),
                  Expanded(child: _Stat(label: 'Next gem', value: next == null ? '—' : '${next.toStringAsFixed(2)}x')),
                  const SizedBox(width: 6),
                  Expanded(child: _Stat(label: _playing ? 'Cash out' : 'Won', value: _playing ? compact((_bet * mult).floor()) : compact(g?['win'] as num? ?? 0), gold: true)),
                ]),
                const SizedBox(height: 10),
                AspectRatio(
                  aspectRatio: 1,
                  child: GridView.count(
                    crossAxisCount: 5,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [for (var i = 0; i < 25; i++) _tile(i)],
                  ),
                ),
                if (status == 'boom') const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: Text('BOOM! The bet is lost', style: TextStyle(color: Color(0xFFFF5252), fontSize: 18, fontWeight: FontWeight.w900)))),
                if (status == 'cashed') Center(child: SizedBox(height: 44, child: CountUp((g?['win'] as num? ?? 0).toInt(), size: 28))),
                const SizedBox(height: 10),
                GoldPanel(
                  color: const Color(0xFF13305E),
                  child: Column(children: [
                    Row(children: [
                      const Text('Bet', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      _Mini(icon: Icons.remove, onTap: _playing ? null : () => setState(() => _bet = math.max(widget.minBet, _bet ~/ 2))),
                      SizedBox(width: 110, child: Text(grouped(_bet), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                      _Mini(icon: Icons.add, onTap: _playing ? null : () => setState(() => _bet *= 2)),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Text('Bombs', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            for (final b in const [1, 3, 5, 10, 15, 20, 24])
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: ChoiceChip(
                                  label: Text('$b'),
                                  selected: _bombs == b,
                                  onSelected: _playing ? null : (_) => setState(() => _bombs = b),
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    _playing
                        ? PressButton(
                            label: _picks.isEmpty ? 'Pick a tile' : 'CASH OUT ${compact((_bet * mult).floor())}',
                            color: const Color(0xFFFF8F00),
                            busy: _busy,
                            onTap: _picks.isEmpty ? null : _cashout,
                          )
                        : PressButton(label: 'START · ${compact(_bet)}', color: const Color(0xFF2E9D3A), busy: _busy, onTap: _start),
                  ]),
                ),
                const SizedBox(height: 10),
                ChestBar(state: _chests, onClaim: (lv) async {
                  final r = await claimChest(context, 'mines', lv);
                  if (r != null && mounted) setState(() => _chests = r);
                }),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 30,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final h in _history)
                        Builder(builder: (_) {
                          final m = ((h as Map)['mult'] as num? ?? 0).toDouble();
                          return Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: m > 0 ? const Color(0x332E9D3A) : const Color(0x33C62828), borderRadius: BorderRadius.circular(15)),
                            child: Text(m > 0 ? '${m.toStringAsFixed(2)}x' : 'boom', style: TextStyle(color: m > 0 ? const Color(0xFF6BE675) : const Color(0xFFFF8A80), fontWeight: FontWeight.w900)),
                          );
                        }),
                    ]),
                  ),
                ],
              ]),
      ),
    );
  }

  Widget _tile(int i) {
    final picked = _picks.contains(i);
    final over = _g != null && !_playing;
    final bomb = over && _board.contains(i);
    final revealed = picked || over;
    Widget? content;
    if (revealed) {
      content = bomb ? art('bomb') : art(_gemArts[i % _gemArts.length]);
    }
    return GestureDetector(
      onTap: () => _pick(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: revealed
              ? LinearGradient(colors: bomb ? (_boomTile == i ? const [Color(0xFFFF5252), Color(0xFF8A0E12)] : const [Color(0xFF3A1A2A), Color(0xFF200A14)]) : const [Color(0xFF1B3A6A), Color(0xFF0E2248)])
              : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A6FB0), Color(0xFF2A4A86)]),
          border: Border.all(color: picked ? const Color(0xFFFFE07A) : Colors.white24, width: picked ? 2 : 1),
          boxShadow: revealed ? null : const [BoxShadow(color: Colors.black45, offset: Offset(0, 3), blurRadius: 3)],
        ),
        child: content == null
            ? null
            : Opacity(opacity: picked || bomb ? 1 : .45, child: TweenAnimationBuilder<double>(
                tween: Tween(begin: .3, end: 1),
                duration: const Duration(milliseconds: 300),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: content,
              )),
      ),
    );
  }

  void _help() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('How to play Gems', style: serif(22)),
          content: const Text(
            '25 tiles hide gems and bombs.\n\n'
            '1. Choose your bet and how many bombs (more bombs = bigger multipliers).\n'
            '2. Tap START, then tap tiles. Every gem raises the multiplier.\n'
            '3. Tap CASH OUT any time to take bet × multiplier.\n'
            '4. Hit a bomb and the bet is lost.\n\n'
            'Coins only — no real money.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: C.gold)))],
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.gold = false});
  final String label;
  final String value;
  final bool gold;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
        child: Column(children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          Text(value, style: TextStyle(color: gold ? const Color(0xFFFFD54F) : Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        ]),
      );
}

class _Mini extends StatelessWidget {
  const _Mini({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: onTap == null ? Colors.white10 : const Color(0xFF2A4A86),
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, color: Colors.white, size: 18))),
      );
}
