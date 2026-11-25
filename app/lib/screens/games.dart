import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/active_room.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'games_kit.dart';
import 'party_games.dart';

/// Games hub: lucky games (coins vs the house, results decided by the server) and,
/// inside a room, party games everyone in the room plays together.
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
        title: Text('Games', style: serif(22)),
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
    isScrollControlled: true,
    backgroundColor: const Color(0xFF110D0A),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      maxChildSize: .94,
      builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 10),
        Row(children: [
          Text('Games', style: serif(24)),
          const Spacer(),
          ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(grouped(c))),
        ]),
        if (roomId != null) ...[
          const SizedBox(height: 14),
          const _Section('Party games', 'Play live with everyone in this room'),
          _grid([
            _GameTile('Lucky Bag', 'luckybag', 'Share coins', const Color(0xFFB0122B), () => _party(ctx, context, roomId, 'luckybag')),
            _GameTile('PK Battle', 'vs', 'Gift battle', const Color(0xFF2A3FB8), () => _party(ctx, context, roomId, 'pk')),
            _GameTile('Ludo', 'pawn_red', '2–4 players', const Color(0xFF1E7A3A), () => _party(ctx, context, roomId, 'ludo')),
            _GameTile('Tic-Tac-Toe', 'piece_x', '1 vs 1', const Color(0xFF7A1E45), () => _party(ctx, context, roomId, 'ttt')),
            _GameTile('Rock Paper Scissors', 'rps_scissors', '1 vs 1', const Color(0xFF4A4A55), () => _party(ctx, context, roomId, 'rps')),
            _GameTile('Spin the Bottle', 'bottle', 'Truth or dare', const Color(0xFF0E5A4A), () => _party(ctx, context, roomId, 'bottle')),
          ]),
        ],
        const SizedBox(height: 14),
        const _Section('Lucky games', 'Results are drawn on our server — fair for everyone'),
        _grid([
          _GameTile('Greedy', 'food_chicken', 'Up to x45', const Color(0xFFB4521A), () => _go(ctx, context, WheelBetGame.greedy(minBet: minBet, roomId: roomId))),
          _GameTile('Fruit Party', 'fruit_watermelon', 'Up to x45', const Color(0xFF2E8B2E), () => _go(ctx, context, WheelBetGame.fruit(minBet: minBet, roomId: roomId))),
          _GameTile('Lucky 777', 'sym_seven', 'Jackpot x50', const Color(0xFF9A1830), () => _go(ctx, context, SlotsGame(minBet: minBet, roomId: roomId))),
          _GameTile('Rocket', 'rocket', 'Cash out to x100', const Color(0xFF3A2A9A), () => _go(ctx, context, CrashGame(minBet: minBet, roomId: roomId))),
          _GameTile('Lucky Wheel', 'wheel', 'Spin up to x5', const Color(0xFF8A5A0A), () => _go(ctx, context, LuckyWheelGame(minBet: minBet, roomId: roomId))),
          _GameTile('Gems', 'gem_diamond', '3 of a kind x40', const Color(0xFF1A4A8A), () => _go(ctx, context, GemsGame(minBet: minBet, roomId: roomId))),
          _GameTile('Dice', 'die_6', 'Big · Small · 7', const Color(0xFF0F6A4A), () => _go(ctx, context, DiceGame(minBet: minBet, roomId: roomId))),
        ]),
      ]),
    ),
  );
}

Widget _grid(List<Widget> tiles) => GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: .82,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      children: tiles,
    );

void _go(BuildContext ctx, BuildContext outer, Widget page) {
  Navigator.pop(ctx);
  Navigator.push(outer, MaterialPageRoute(builder: (_) => page));
}

void _party(BuildContext ctx, BuildContext outer, int roomId, String kind) {
  final room = ActiveRoom.current.value;
  Navigator.pop(ctx);
  startPartyGame(outer, roomId: roomId, kind: kind, room: room);
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.sub);
  final String title, sub;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: serif(19, color: C.gold)),
        Text(sub, style: const TextStyle(fontSize: 11, color: C.mute)),
      ]);
}

class _GameTile extends StatelessWidget {
  const _GameTile(this.title, this.image, this.sub, this.color, this.onTap);
  final String title, image, sub;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          Sfx.play('pop');
          onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(0, -.4), radius: 1.1, colors: [Color.lerp(color, Colors.white, .15)!, color, Color.lerp(color, Colors.black, .7)!]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .12)),
            boxShadow: [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
          child: Column(children: [
            Expanded(child: Floaty(amp: 3, phase: title.length / 10, child: art(image))),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.white)),
            Text(sub, maxLines: 1, style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ]),
        ),
      );
}

// =====================================================================================
// Greedy & Fruit Party: 8 items around a wheel, a light runs round and stops on the winner
// =====================================================================================

class WheelItem {
  const WheelItem(this.key, this.image, this.mult, this.label);
  final String key, image, label;
  final int mult;
}

class WheelBetGame extends StatefulWidget {
  const WheelBetGame({super.key, required this.game, required this.title, required this.items, required this.color, required this.minBet, this.roomId});
  final String game, title;
  final List<WheelItem> items;
  final Color color;
  final int minBet;
  final int? roomId;

  factory WheelBetGame.greedy({required int minBet, int? roomId}) => WheelBetGame(
        game: 'greedy',
        title: 'Greedy',
        color: const Color(0xFF5A2A0F),
        minBet: minBet,
        roomId: roomId,
        items: const [
          WheelItem('tomato', 'food_tomato', 5, 'Tomato'),
          WheelItem('corn', 'food_corn', 5, 'Corn'),
          WheelItem('carrot', 'food_carrot', 5, 'Carrot'),
          WheelItem('lettuce', 'food_lettuce', 5, 'Lettuce'),
          WheelItem('fish', 'food_fish', 10, 'Fish'),
          WheelItem('shrimp', 'food_shrimp', 15, 'Shrimp'),
          WheelItem('steak', 'food_steak', 25, 'Steak'),
          WheelItem('chicken', 'food_chicken', 45, 'Chicken'),
        ],
      );

  factory WheelBetGame.fruit({required int minBet, int? roomId}) => WheelBetGame(
        game: 'fruit',
        title: 'Fruit Party',
        color: const Color(0xFF16461C),
        minBet: minBet,
        roomId: roomId,
        items: const [
          WheelItem('apple', 'fruit_apple', 5, 'Apple'),
          WheelItem('orange', 'fruit_orange', 5, 'Orange'),
          WheelItem('lemon', 'fruit_lemon', 5, 'Lemon'),
          WheelItem('grape', 'fruit_grape', 5, 'Grape'),
          WheelItem('cherry', 'fruit_cherry', 10, 'Cherry'),
          WheelItem('strawberry', 'fruit_strawberry', 15, 'Strawberry'),
          WheelItem('watermelon', 'fruit_watermelon', 25, 'Melon'),
          WheelItem('banana', 'fruit_banana', 45, 'Banana'),
        ],
      );

  @override
  State<WheelBetGame> createState() => _WheelBetGameState();
}

class _WheelBetGameState extends State<WheelBetGame> with TickerProviderStateMixin {
  late int _chip = widget.minBet;
  final Map<String, int> _bets = {};
  final List<String> _history = [];
  int? _lit;
  String? _winner;
  bool _busy = false;
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  int get _total => _bets.values.fold(0, (a, b) => a + b);

  @override
  void dispose() {
    _pop.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _bet(WheelItem it) {
    if (_busy) return;
    Sfx.play('tick');
    setState(() => _bets[it.key] = (_bets[it.key] ?? 0) + _chip);
  }

  Future<void> _go() async {
    if (_total < widget.minBet) return toast(context, 'Tap the items to place at least ${compact(widget.minBet)} coins');
    setState(() {
      _busy = true;
      _winner = null;
    });
    final r = await playGame(context, widget.game, pick: {'bets': _bets}, roomId: widget.roomId);
    if (r == null) return setState(() => _busy = false);
    final winner = r['winner'] as String;
    final target = winner == 'bomb' ? math.Random().nextInt(8) : widget.items.indexWhere((f) => f.key == winner);
    final steps = 8 * 4 + target;
    for (var i = 0; i <= steps; i++) {
      if (!mounted) return;
      setState(() => _lit = i % 8);
      Sfx.play('tick', volume: .6);
      final slow = i / steps;
      await Future.delayed(Duration(milliseconds: (40 + 360 * slow * slow * slow).round()));
    }
    if (!mounted) return;
    setState(() {
      _lit = winner == 'bomb' ? null : target;
      _winner = winner;
      _history.insert(0, winner);
      if (_history.length > 12) _history.removeLast();
    });
    if (winner == 'bomb') {
      Sfx.play('boom');
      _shake.forward(from: 0);
    } else {
      _pop.forward(from: 0);
    }
    settleCoins(r);
    final payout = (r['payout'] as num).toInt();
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    final it = winner == 'bomb' ? null : widget.items[target];
    await resultPopup(context, win: payout > 0, amount: payout, image: it?.image ?? 'bomb', note: it == null ? 'The bomb went off' : 'Winner: ${it.label} x${it.mult}');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: widget.title,
      color: widget.color,
      help: 'Tap items to bet with the chip you picked. When the light stops on an item you bet on, you win your bet times its multiplier. '
          'If it lands on the bomb, all bets are lost.',
      child: Column(children: [
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            const Center(child: Text('Last  ', style: TextStyle(color: C.mute, fontSize: 11))),
            for (final h in _history)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: art(h == 'bomb' ? 'bomb' : widget.items.firstWhere((i) => i.key == h).image, size: 30),
              ),
          ]),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _shake,
            builder: (_, child) => Transform.translate(offset: Offset(math.sin(_shake.value * 40) * 10 * (1 - _shake.value), 0), child: child),
            child: LayoutBuilder(builder: (context, box) {
              final d = math.min(box.maxWidth, box.maxHeight) - 16;
              final plate = d * .23;
              final rr = d / 2 - plate * .62;
              return Center(
                child: SizedBox(
                  width: d,
                  height: d,
                  child: Stack(clipBehavior: Clip.none, children: [
                    // wooden table ring
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [Color.lerp(widget.color, Colors.black, .2)!, Color.lerp(widget.color, Colors.black, .65)!], stops: const [.6, 1]),
                          border: Border.all(color: C.gold2, width: 5),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: .7), blurRadius: 30, offset: const Offset(0, 18)),
                            BoxShadow(color: C.gold.withValues(alpha: .15), blurRadius: 40),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: d * .36,
                        height: d * .36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(colors: [Color(0xFF3A2A18), Color(0xFF120C06)]),
                          border: Border.all(color: C.gold, width: 3),
                          boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 16, spreadRadius: -4)],
                        ),
                        alignment: Alignment.center,
                        child: _winner == null
                            ? Column(mainAxisSize: MainAxisSize.min, children: [
                                const Text('BET', style: TextStyle(color: C.mute, fontSize: 11, letterSpacing: 2)),
                                CoinText(compact(_total), size: 18),
                              ])
                            : AnimatedBuilder(
                                animation: _pop,
                                builder: (_, __) => Transform.scale(
                                  scale: Curves.elasticOut.transform(_pop.value.clamp(0.0, 1.0)) * .9 + (_winner == 'bomb' ? .9 : .1),
                                  child: art(_winner == 'bomb' ? 'bomb' : widget.items.firstWhere((i) => i.key == _winner).image, size: d * .26),
                                ),
                              ),
                      ),
                    ),
                    for (var i = 0; i < widget.items.length; i++)
                      Positioned(
                        left: d / 2 + rr * math.cos(-math.pi / 2 + i * math.pi / 4) - plate / 2,
                        top: d / 2 + rr * math.sin(-math.pi / 2 + i * math.pi / 4) - plate / 2,
                        child: _plate(widget.items[i], plate, i),
                      ),
                  ]),
                ),
              );
            }),
          ),
        ),
        ChipBar(value: _chip, minBet: widget.minBet, onChanged: (c) => setState(() => _chip = c)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy || _bets.isEmpty ? null : () => setState(_bets.clear),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: C.gold2), minimumSize: const Size(0, 54), shape: const StadiumBorder()),
                child: const Text('Clear', style: TextStyle(color: C.gold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: PressButton(label: 'SPIN', busy: _busy, onTap: _go)),
          ]),
        ),
      ]),
    );
  }

  Widget _plate(WheelItem it, double size, int i) {
    final lit = _lit == i;
    final win = _winner == it.key;
    final bet = _bets[it.key] ?? 0;
    return GestureDetector(
      onTap: () => _bet(it),
      child: AnimatedBuilder(
        animation: _pop,
        builder: (_, child) => Transform.scale(scale: win ? 1 + .25 * math.sin(_pop.value * math.pi) : 1, child: child),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-.3, -.4),
                  colors: lit || win ? const [Color(0xFFFFF6D8), Color(0xFFE9C46A), Color(0xFF8A5A12)] : const [Color(0xFFF5EFE6), Color(0xFFCFC4B2), Color(0xFF6F6454)],
                ),
                border: Border.all(color: lit || win ? Colors.white : C.gold2, width: lit || win ? 4 : 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: .6), blurRadius: 10, offset: const Offset(0, 6)),
                  if (lit || win) BoxShadow(color: C.gold.withValues(alpha: .9), blurRadius: 24, spreadRadius: 2),
                ],
              ),
            ),
            Padding(padding: EdgeInsets.all(size * .14), child: art(it.image)),
            Positioned(
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFF8A1020), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.gold, width: 1)),
                child: Text('x${it.mult}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ),
            if (bet > 0)
              Positioned(
                bottom: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(gradient: C.goldGrad, borderRadius: BorderRadius.circular(9)),
                  child: Text(compact(bet), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF1A1206))),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// =====================================================================================
// Lucky 777: three curved reels with motion blur
// =====================================================================================

const _strip = ['sym_seven', 'sym_cherry', 'sym_bell', 'sym_lemon', 'sym_bar', 'sym_grape', 'sym_star', 'sym_cherry', 'sym_lemon', 'sym_bell', 'sym_grape', 'sym_star'];

class SlotsGame extends StatefulWidget {
  const SlotsGame({super.key, required this.minBet, this.roomId});
  final int minBet;
  final int? roomId;
  @override
  State<SlotsGame> createState() => _SlotsGameState();
}

class _SlotsGameState extends State<SlotsGame> with TickerProviderStateMixin {
  late int _chip = widget.minBet;
  bool _busy = false;
  bool _won = false;
  final _pos = [0.0, 3.0, 6.0];
  late final List<AnimationController> _reels = List.generate(3, (i) => AnimationController(vsync: this, duration: Duration(milliseconds: 1600 + i * 450)));
  final List<Tween<double>> _tw = List.generate(3, (i) => Tween(begin: 0, end: 0));
  late final AnimationController _lights = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    for (final c in _reels) {
      c.dispose();
    }
    _lights.dispose();
    super.dispose();
  }

  List<String> _face(String outcome) {
    final r = math.Random();
    switch (outcome) {
      case '777':
        return ['sym_seven', 'sym_seven', 'sym_seven'];
      case 'bar':
        return ['sym_bar', 'sym_bar', 'sym_bar'];
      case 'bell':
        return ['sym_bell', 'sym_bell', 'sym_bell'];
      case 'cherry3':
        return ['sym_cherry', 'sym_cherry', 'sym_cherry'];
      case 'cherry2':
        final o = ['sym_lemon', 'sym_grape', 'sym_star', 'sym_bell', 'sym_bar'][r.nextInt(5)];
        return ['sym_cherry', 'sym_cherry', o];
      default:
        // a losing line: never three alike and never two cherries in front
        while (true) {
          final f = List.generate(3, (_) => _strip[r.nextInt(_strip.length)]);
          if (f[0] == f[1] && f[1] == f[2]) continue;
          if (f[0] == 'sym_cherry' && f[1] == 'sym_cherry') continue;
          return f;
        }
    }
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _won = false;
    });
    final r = await playGame(context, 'slots', bet: _chip, roomId: widget.roomId);
    if (r == null) return setState(() => _busy = false);
    final face = _face('${r['outcome']}');
    Sfx.play('whoosh', volume: .7);
    final done = <Future<void>>[];
    for (var i = 0; i < 3; i++) {
      // land the reel so the chosen symbol sits on the pay line
      final cur = _pos[i] % _strip.length;
      final options = [for (var k = 0; k < _strip.length; k++) if (_strip[k] == face[i]) k];
      final idx = options[math.Random().nextInt(options.length)];
      final end = _pos[i] - cur + _strip.length * (4 + i) + idx;
      _tw[i] = Tween(begin: _pos[i], end: end);
      done.add(_reels[i].forward(from: 0).then((_) {
        _pos[i] = end;
        Sfx.play('tick');
      }));
    }
    await Future.wait(done);
    if (!mounted) return;
    settleCoins(r);
    final payout = (r['payout'] as num).toInt();
    setState(() => _won = payout > 0);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await resultPopup(context, win: payout > 0, amount: payout, image: payout > 0 ? face[0] : null, note: payout > 0 ? 'x${r['mult']}' : null);
    if (mounted) setState(() => _busy = false);
  }

  double _value(int i) {
    final c = _reels[i];
    if (!c.isAnimating && c.value == 0) return _pos[i];
    // fast spin that eases out with a little settle bounce at the end
    final t = c.value;
    final e = t < .85 ? Curves.easeInOutCubic.transform(t / .85) * 1.012 : 1.012 - .012 * Curves.easeOutBack.transform((t - .85) / .15);
    return _tw[i].begin! + (_tw[i].end! - _tw[i].begin!) * e;
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Lucky 777',
      color: const Color(0xFF3A0A14),
      help: 'Three 7s pay x50, three BARs x20, three bells x10, three cherries x5 and two cherries at the start x2.',
      child: Column(children: [
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _lights,
          builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 9; i++)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ((i + (_lights.value * 9).floor()) % 3 == 0) || _won ? const Color(0xFFFFE08A) : const Color(0xFF5A3A10),
                  boxShadow: ((i + (_lights.value * 9).floor()) % 3 == 0) || _won ? [const BoxShadow(color: Color(0xFFFFC94A), blurRadius: 10)] : null,
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(colors: [Color(0xFFF7DFA0), Color(0xFFB8862E), Color(0xFF6A4410), Color(0xFFD9A94A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .8), blurRadius: 30, offset: const Offset(0, 16))],
              ),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: const Color(0xFF120608)),
                child: AspectRatio(
                  aspectRatio: 1.05,
                  child: Stack(children: [
                    Row(children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: AnimatedBuilder(animation: _reels[i], builder: (_, __) => _Reel(position: _value(i), speed: _reels[i].isAnimating ? _speed(i) : 0)),
                          ),
                        ),
                    ]),
                    // pay line
                    Center(
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(color: _won ? const Color(0xFFFFE08A) : Colors.red.withValues(alpha: .7), boxShadow: [BoxShadow(color: _won ? C.gold : Colors.red, blurRadius: 10)]),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 4, children: [
            for (final p in const [('sym_seven', 3, 'x50'), ('sym_bar', 3, 'x20'), ('sym_bell', 3, 'x10'), ('sym_cherry', 3, 'x5'), ('sym_cherry', 2, 'x2')])
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var k = 0; k < p.$2; k++) art(p.$1, size: 18),
                const SizedBox(width: 3),
                Text(p.$3, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.gold)),
              ]),
          ]),
        ),
        ChipBar(value: _chip, minBet: widget.minBet, onChanged: (c) => setState(() => _chip = c)),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: PressButton(label: 'SPIN  ·  ${compact(_chip)}', busy: _busy, onTap: _go)),
      ]),
    );
  }

  double _speed(int i) {
    final t = _reels[i].value;
    return (1 - t).clamp(0.0, 1.0) * (t < .1 ? t * 10 : 1);
  }
}

/// One reel drawn as a cylinder: symbols bend away and darken towards the top and bottom.
class _Reel extends StatelessWidget {
  const _Reel({required this.position, required this.speed});
  final double position;
  final double speed;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      final cell = h / 3;
      final base = position.floor();
      final frac = position - base;
      final children = <Widget>[];
      for (var k = -2; k <= 2; k++) {
        final d = k - frac; // distance from the pay line in cells
        final ang = d * .62;
        if (ang.abs() > math.pi / 2) continue;
        final y = h / 2 + math.sin(ang) * h * .52 - cell / 2;
        final idx = ((base + k) % _strip.length + _strip.length) % _strip.length;
        children.add(Positioned(
          left: 0,
          right: 0,
          top: y,
          height: cell,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .002)
              ..rotateX(-ang),
            child: Padding(padding: EdgeInsets.all(cell * .1), child: art(_strip[idx])),
          ),
        ));
      }
      Widget reel = Stack(children: children);
      if (speed > .05) {
        reel = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 0, sigmaY: 10 * speed), child: reel);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF8C8478), Color(0xFFFFFFFF), Color(0xFFF4F0EA), Color(0xFFFFFFFF), Color(0xFF8C8478)], stops: [0, .3, .5, .7, 1], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: Stack(fit: StackFit.expand, children: [
            reel,
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withValues(alpha: .75), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: .75)],
                    stops: const [0, .28, .72, 1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

// =====================================================================================
// Rocket (crash): the rocket climbs, the multiplier grows; it may explode at any time
// =====================================================================================

class CrashGame extends StatefulWidget {
  const CrashGame({super.key, required this.minBet, this.roomId});
  final int minBet;
  final int? roomId;
  @override
  State<CrashGame> createState() => _CrashGameState();
}

class _CrashGameState extends State<CrashGame> with TickerProviderStateMixin {
  late int _chip = widget.minBet;
  double _target = 2.0;
  bool _busy = false;
  double _mult = 1.0;
  double? _crashAt;
  bool _cashed = false;
  bool _exploded = false;
  final List<double> _recent = [];
  late final AnimationController _fly = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  late final AnimationController _boom = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _stars = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _fly.dispose();
    _boom.dispose();
    _stars.dispose();
    super.dispose();
  }

  // multiplier grows exponentially with time; long flights speed up so nobody waits forever
  static double _timeFor(double m) => math.log(m) / .22;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _cashed = false;
      _exploded = false;
      _mult = 1;
      _crashAt = null;
    });
    final r = await playGame(context, 'crash', bet: _chip, pick: {'target': _target}, roomId: widget.roomId);
    if (r == null) return setState(() => _busy = false);
    final crash = (r['crash'] as num).toDouble();
    final secs = math.min(_timeFor(crash), 12.0);
    _fly.duration = Duration(milliseconds: (secs * 1000).round().clamp(400, 12000));
    Sfx.play('whoosh');
    void listener() {
      final p = _fly.value;
      final m = math.exp(math.log(crash) * p);
      if (!_cashed && (r['mult'] as num) > 0 && m >= _target) {
        _cashed = true;
        Sfx.play('coin');
      }
      setState(() => _mult = m);
    }

    _fly.addListener(listener);
    await _fly.forward(from: 0);
    _fly.removeListener(listener);
    if (!mounted) return;
    Sfx.play('boom');
    setState(() {
      _mult = crash;
      _crashAt = crash;
      _exploded = true;
      _recent.insert(0, crash);
      if (_recent.length > 10) _recent.removeLast();
    });
    await _boom.forward(from: 0);
    settleCoins(r);
    final payout = (r['payout'] as num).toInt();
    if (!mounted) return;
    await resultPopup(context, win: payout > 0, amount: payout, image: payout > 0 ? 'rocket' : 'bomb', note: payout > 0 ? 'Cashed out at x${_target.toStringAsFixed(2)} · rocket reached x${crash.toStringAsFixed(2)}' : 'Exploded at x${crash.toStringAsFixed(2)}');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Rocket',
      color: const Color(0xFF0E0A2A),
      help: 'Pick a cash-out target, then launch. If the rocket reaches your target before it explodes, you win your bet times the target.',
      child: Column(children: [
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final c in _recent)
              Container(
                margin: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c >= 2 ? const Color(0xFF1E6A4A) : const Color(0xFF6A1E2A), borderRadius: BorderRadius.circular(12)),
                child: Text('x${c.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF05030F), Color(0xFF1A1050), Color(0xFF3A1A5A)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              border: Border.all(color: Colors.white12),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth, h = box.maxHeight;
              final p = _crashAt != null ? 1.0 : _fly.value;
              // rocket position along a rising curve
              final x = 30 + (w - 110) * p;
              final y = h - 40 - (h - 120) * math.pow(p, 1.6).toDouble();
              final slope = math.atan2(-(h - 120) * 1.6 * math.pow(math.max(p, .02), .6), w - 110);
              return Stack(children: [
                Positioned.fill(child: AnimatedBuilder(animation: _stars, builder: (_, __) => CustomPaint(painter: _StarsPainter(_stars.value, speed: _busy && !_exploded ? 1 : .15)))),
                Positioned.fill(child: CustomPaint(painter: _TrailPainter(p, w, h, exploded: _exploded))),
                if (!_exploded)
                  Positioned(
                    left: x - 50,
                    top: y - 50,
                    child: Transform.rotate(
                      angle: slope + math.pi / 4,
                      child: SizedBox(
                        width: 100,
                        height: 100,
                        child: Stack(alignment: Alignment.center, children: [
                          if (_busy) Transform.translate(offset: const Offset(-34, 34), child: Transform.rotate(angle: math.pi / 4, child: AnimatedBuilder(animation: _stars, builder: (_, __) => CustomPaint(size: const Size(26, 60), painter: _FlamePainter(_stars.value))))),
                          art('rocket', size: 90),
                        ]),
                      ),
                    ),
                  ),
                if (_exploded)
                  Positioned(
                    left: x - 90,
                    top: y - 90,
                    child: AnimatedBuilder(animation: _boom, builder: (_, __) => CustomPaint(size: const Size(180, 180), painter: _BoomPainter(_boom.value))),
                  ),
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      'x${_mult.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        color: _exploded ? const Color(0xFFFF5A5A) : (_cashed ? const Color(0xFF7CFFB2) : Colors.white),
                        shadows: const [Shadow(color: Colors.black, blurRadius: 12)],
                      ),
                    ),
                    if (_cashed) const Text('CASHED OUT', style: TextStyle(color: Color(0xFF7CFFB2), fontWeight: FontWeight.w900, letterSpacing: 2)),
                    if (_exploded && !_cashed) const Text('EXPLODED', style: TextStyle(color: Color(0xFFFF5A5A), fontWeight: FontWeight.w900, letterSpacing: 2)),
                  ]),
                ),
              ]);
            }),
          ),
        ),
        const Text('Auto cash-out at', style: TextStyle(color: C.mute, fontSize: 12)),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final t in const [1.2, 1.5, 2.0, 3.0, 5.0, 10.0, 25.0, 100.0])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('x${t % 1 == 0 ? t.toInt() : t}'),
                  selected: _target == t,
                  selectedColor: C.gold,
                  labelStyle: TextStyle(color: _target == t ? const Color(0xFF1A1206) : Colors.white, fontWeight: FontWeight.w800),
                  onSelected: _busy ? null : (_) => setState(() => _target = t),
                ),
              ),
          ]),
        ),
        ChipBar(value: _chip, minBet: widget.minBet, onChanged: (c) => setState(() => _chip = c)),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: PressButton(label: 'LAUNCH  ·  ${compact(_chip)}', busy: _busy, onTap: _go)),
      ]),
    );
  }
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.t, {required this.speed});
  final double t, speed;
  static final _r = math.Random(5);
  static final _s = List.generate(90, (_) => [_r.nextDouble(), _r.nextDouble(), _r.nextDouble()]);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final s in _s) {
      final depth = .3 + s[2] * .7;
      final x = (s[0] - t * speed * depth * 2) % 1.0;
      final y = (s[1] + t * speed * depth * 1.2) % 1.0;
      p.color = Colors.white.withValues(alpha: .25 + depth * .6);
      canvas.drawCircle(Offset(x * size.width, y * size.height), .6 + depth * 1.3, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter old) => true;
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.p, this.w, this.h, {required this.exploded});
  final double p, w, h;
  final bool exploded;
  @override
  void paint(Canvas canvas, Size size) {
    if (p <= 0) return;
    final path = Path()..moveTo(30, h - 40);
    for (var i = 1; i <= 60; i++) {
      final q = p * i / 60;
      path.lineTo(30 + (w - 110) * q, h - 40 - (h - 120) * math.pow(q, 1.6).toDouble());
    }
    final fill = Path.from(path)
      ..lineTo(30 + (w - 110) * p, h)
      ..lineTo(30, h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(colors: [(exploded ? Colors.red : const Color(0xFFFFB347)).withValues(alpha: .35), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)
            .createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = exploded ? const Color(0xFFFF5A5A) : const Color(0xFFFFC46B),
    );
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) => true;
}

class _FlamePainter extends CustomPainter {
  _FlamePainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final flick = 1 + .18 * math.sin(t * 2 * math.pi * 14) + .1 * math.sin(t * 2 * math.pi * 23);
    final w = size.width, h = size.height * flick;
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(w * .1, h * .6, w / 2, h)
      ..quadraticBezierTo(w * .9, h * .6, w, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(colors: [Colors.white, Color(0xFFFFE08A), Color(0xFFFF8A1E), Color(0x00FF3A00)], stops: [0, .2, .55, 1], begin: Alignment.topCenter, end: Alignment.bottomCenter)
            .createShader(Rect.fromLTWH(0, 0, w, h))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant _FlamePainter old) => true;
}

class _BoomPainter extends CustomPainter {
  _BoomPainter(this.t);
  final double t;
  static final _r = math.Random(9);
  static final _parts = List.generate(36, (_) => [_r.nextDouble() * 2 * math.pi, .4 + _r.nextDouble() * .6, _r.nextDouble()]);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final fade = (1 - t).clamp(0.0, 1.0);
    canvas.drawCircle(
      c,
      20 + t * 70,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: fade), const Color(0xFFFFB347).withValues(alpha: fade * .8), const Color(0xFFFF3A1E).withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: 20 + t * 70)),
    );
    for (final p in _parts) {
      final d = t * 90 * p[1];
      final o = c + Offset(math.cos(p[0]), math.sin(p[0])) * d + Offset(0, t * t * 30);
      canvas.drawCircle(o, 2 + p[2] * 4 * fade, Paint()..color = Color.lerp(const Color(0xFFFFE08A), const Color(0xFF5A1A0A), t)!.withValues(alpha: fade));
    }
  }

  @override
  bool shouldRepaint(covariant _BoomPainter old) => true;
}

// =====================================================================================
// Lucky Wheel
// =====================================================================================

const _wheelMults = [0, 1.5, 0, 2, .5, 0, 3, 0, 1.5, 0, 5, 0, .5, 0, 1.2, 0];

class LuckyWheelGame extends StatefulWidget {
  const LuckyWheelGame({super.key, required this.minBet, this.roomId});
  final int minBet;
  final int? roomId;
  @override
  State<LuckyWheelGame> createState() => _LuckyWheelGameState();
}

class _LuckyWheelGameState extends State<LuckyWheelGame> with TickerProviderStateMixin {
  late int _chip = widget.minBet;
  bool _busy = false;
  double _angle = 0;
  int? _slot;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  late final AnimationController _bulbs = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat();
  late final AnimationController _flap = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));

  @override
  void dispose() {
    _spin.dispose();
    _bulbs.dispose();
    _flap.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _slot = null;
    });
    final r = await playGame(context, 'wheel', bet: _chip, roomId: widget.roomId);
    if (r == null) return setState(() => _busy = false);
    final slot = (r['slot'] as num).toInt();
    const seg = 2 * math.pi / 16;
    final start = _angle % (2 * math.pi);
    final jitter = (math.Random().nextDouble() - .5) * seg * .6;
    var end = -slot * seg + jitter;
    while (end < start + 2 * math.pi * 6) {
      end += 2 * math.pi;
    }
    final tween = Tween(begin: start, end: end);
    var lastSeg = (start / seg).floor();
    void tick() {
      final a = tween.transform(Curves.easeOutQuart.transform(_spin.value));
      final s = ((a + seg / 2) / seg).floor();
      if (s != lastSeg) {
        lastSeg = s;
        Sfx.play('tick', volume: .5);
        _flap.forward(from: 0);
      }
      setState(() => _angle = a);
    }

    _spin.addListener(tick);
    await _spin.forward(from: 0);
    _spin.removeListener(tick);
    if (!mounted) return;
    setState(() => _slot = slot);
    settleCoins(r);
    final payout = (r['payout'] as num).toInt();
    await resultPopup(context, win: payout > 0, amount: payout, note: 'Landed on ${_wheelMults[slot] == 0 ? 'no prize' : 'x${_wheelMults[slot]}'}');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Lucky Wheel',
      color: const Color(0xFF3A1A06),
      help: 'Spin the wheel. You win your bet times the number the pointer stops on.',
      child: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final d = math.min(box.maxWidth - 24, box.maxHeight - 40);
            return Center(
              child: SizedBox(
                width: d,
                height: d + 30,
                child: Stack(alignment: Alignment.topCenter, children: [
                  Positioned(top: 30 + d * .9, child: GroundShadow(width: d * .9, opacity: .6)),
                  Positioned(
                    top: 30,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, .0008)
                        ..rotateX(.28),
                      child: SizedBox(
                        width: d,
                        height: d,
                        child: Transform.rotate(
                          angle: _angle,
                          child: Stack(children: [
                            Positioned.fill(child: art('wheel')),
                            for (var i = 0; i < 16; i++)
                              Positioned.fill(
                                child: Transform.rotate(
                                  angle: i * 2 * math.pi / 16,
                                  child: Align(
                                    alignment: const Alignment(0, -.66),
                                    child: Text(
                                      _wheelMults[i] == 0 ? '✕' : 'x${_wheelMults[i]}',
                                      style: TextStyle(
                                        fontSize: d * .052,
                                        fontWeight: FontWeight.w900,
                                        color: _wheelMults[i] == 0 ? Colors.white54 : Colors.white,
                                        shadows: const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1))],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 30,
                    child: AnimatedBuilder(
                      animation: _bulbs,
                      builder: (_, __) => IgnorePointer(
                        child: Container(
                          width: d,
                          height: d,
                          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFFFC94A).withValues(alpha: .15 + .2 * math.sin(_bulbs.value * math.pi)), blurRadius: 30, spreadRadius: -6)]),
                        ),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _flap,
                    builder: (_, child) => Transform.rotate(angle: math.sin(_flap.value * math.pi) * .25, alignment: Alignment.topCenter, child: child),
                    child: art('wheel_pointer', size: d * .16),
                  ),
                  if (_slot != null)
                    Positioned(
                      bottom: 0,
                      child: Text(_wheelMults[_slot!] == 0 ? 'No prize this time' : 'x${_wheelMults[_slot!]}', style: serif(22, color: C.gold)),
                    ),
                ]),
              ),
            );
          }),
        ),
        ChipBar(value: _chip, minBet: widget.minBet, onChanged: (c) => setState(() => _chip = c)),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: PressButton(label: 'SPIN  ·  ${compact(_chip)}', busy: _busy, onTap: _go)),
      ]),
    );
  }
}

// =====================================================================================
// Gems: pick your gem, three gems drop into the mine slots
// =====================================================================================

const _gems = ['ruby', 'sapphire', 'emerald', 'amethyst', 'topaz', 'diamond'];

class GemsGame extends StatefulWidget {
  const GemsGame({super.key, required this.minBet, this.roomId});
  final int minBet;
  final int? roomId;
  @override
  State<GemsGame> createState() => _GemsGameState();
}

class _GemsGameState extends State<GemsGame> with TickerProviderStateMixin {
  late int _chip = widget.minBet;
  String _pick = 'diamond';
  bool _busy = false;
  List<String> _drops = const [];
  late final List<AnimationController> _fall = List.generate(3, (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 900)));
  late final AnimationController _glint = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    for (final c in _fall) {
      c.dispose();
    }
    _glint.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _drops = const [];
    });
    for (final c in _fall) {
      c.value = 0;
    }
    final r = await playGame(context, 'gems', bet: _chip, pick: {'gem': _pick}, roomId: widget.roomId);
    if (r == null) return setState(() => _busy = false);
    setState(() => _drops = List<String>.from(r['drops'] as List));
    for (var i = 0; i < 3; i++) {
      Future.delayed(const Duration(milliseconds: 420), () => Sfx.play(_drops[i] == _pick ? 'coin' : 'pop'));
      await _fall[i].forward(from: 0);
    }
    if (!mounted) return;
    settleCoins(r);
    final payout = (r['payout'] as num).toInt();
    final hits = (r['hits'] as num).toInt();
    await resultPopup(context, win: payout > 0, amount: payout, image: 'gem_$_pick', note: hits == 0 ? 'No ${_pick}s this time' : '$hits $_pick${hits > 1 ? 's' : ''} · x${r['mult']}');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Gems',
      color: const Color(0xFF0A1A3A),
      help: 'Pick a gem. Three gems drop. One match pays x1.4, two pay x4 and three pay x40.',
      child: Column(children: [
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final p in const [(1, 'x1.4'), (2, 'x4'), (3, 'x40')])
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.gold2)),
              child: Row(children: [
                for (var k = 0; k < p.$1; k++) art('gem_$_pick', size: 18),
                const SizedBox(width: 4),
                Text(p.$2, style: const TextStyle(fontWeight: FontWeight.w900, color: C.gold, fontSize: 12)),
              ]),
            ),
        ]),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            final slot = math.min((w - 60) / 3, box.maxHeight * .5);
            return Stack(alignment: Alignment.center, children: [
              // rock wall with three carved holes
              Positioned(
                left: 12,
                right: 12,
                top: box.maxHeight * .25,
                height: slot + 40,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(colors: [Color(0xFF4A4238), Color(0xFF2A241E), Color(0xFF1A1612)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .7), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: slot,
                        height: slot,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [const Color(0xFF050403), const Color(0xFF15110D), Colors.brown.shade900]),
                          border: Border.all(color: Colors.black54, width: 3),
                          boxShadow: [if (_drops.length == 3 && _fall[i].isCompleted && _drops[i] == _pick) BoxShadow(color: C.gold.withValues(alpha: .7), blurRadius: 24)],
                        ),
                      ),
                  ]),
                ),
              ),
              for (var i = 0; i < 3; i++)
                if (_drops.length == 3)
                  AnimatedBuilder(
                    animation: _fall[i],
                    builder: (_, __) {
                      final t = _fall[i].value;
                      final b = Curves.bounceOut.transform(t);
                      final x = 12 + (w - 24) * (i + .5) / 3 - slot / 2;
                      final y = -slot + (box.maxHeight * .25 + 20 + slot) * b;
                      return Positioned(
                        left: x,
                        top: y,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, .002)
                            ..rotateY((1 - t) * 6)
                            ..rotateZ((1 - t) * 1.5),
                          child: SizedBox(width: slot, height: slot, child: Padding(padding: EdgeInsets.all(slot * .1), child: art('gem_${_drops[i]}'))),
                        ),
                      );
                    },
                  ),
            ]);
          }),
        ),
        const Text('Choose your gem', style: TextStyle(color: C.mute, fontSize: 12)),
        SizedBox(
          height: 84,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            for (final g in _gems)
              GestureDetector(
                onTap: _busy
                    ? null
                    : () {
                        Sfx.play('tick');
                        setState(() => _pick = g);
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 66,
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: _pick == g ? Colors.white.withValues(alpha: .12) : Colors.transparent,
                    border: Border.all(color: _pick == g ? C.gold : Colors.white12, width: _pick == g ? 2 : 1),
                    boxShadow: _pick == g ? [BoxShadow(color: C.gold.withValues(alpha: .4), blurRadius: 14)] : null,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: _pick == g ? Floaty(amp: 2, tilt: .12, child: art('gem_$g')) : art('gem_$g'),
                ),
              ),
          ]),
        ),
        ChipBar(value: _chip, minBet: widget.minBet, onChanged: (c) => setState(() => _chip = c)),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: PressButton(label: 'DIG  ·  ${compact(_chip)}', busy: _busy, onTap: _go)),
      ]),
    );
  }
}

// =====================================================================================
// Dice: two real dice tumble across the felt
// =====================================================================================

class DiceGame extends StatefulWidget {
  const DiceGame({super.key, required this.minBet, this.roomId});
  final int minBet;
  final int? roomId;
  @override
  State<DiceGame> createState() => _DiceGameState();
}

class _DiceGameState extends State<DiceGame> with SingleTickerProviderStateMixin {
  late int _chip = widget.minBet;
  String _side = 'big';
  bool _busy = false;
  List<int> _faces = const [5, 2];
  late final AnimationController _roll = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    final r = await playGame(context, 'dice', bet: _chip, pick: {'side': _side}, roomId: widget.roomId);
    if (r == null) return setState(() => _busy = false);
    final d = List<int>.from((r['dice'] as List).map((e) => (e as num).toInt()));
    setState(() => _faces = d);
    Sfx.play('dice');
    await _roll.forward(from: 0);
    if (!mounted) return;
    settleCoins(r);
    final payout = (r['payout'] as num).toInt();
    final sum = d[0] + d[1];
    await resultPopup(context, win: payout > 0, amount: payout, image: 'die_${d[0]}', note: 'Total $sum · ${sum == 7 ? 'Seven' : sum >= 8 ? 'Big' : 'Small'}');
    if (mounted) setState(() => _busy = false);
  }

  Widget _die(int i, Size box) {
    final t = _roll.value;
    final rolling = _roll.isAnimating;
    final size = box.width * .3;
    // each die flies in from the bottom corner, bounces three times and settles
    final restX = box.width * (i == 0 ? .3 : .62) - size / 2;
    final restY = box.height * .45 - size / 2 + (i == 0 ? 0 : 14);
    final startX = i == 0 ? -size : box.width;
    final startY = box.height;
    final p = rolling ? Curves.easeOutCubic.transform(t) : 1.0;
    final x = startX + (restX - startX) * p;
    final bounce = rolling ? (math.sin(t * math.pi * 3.2).abs() * (1 - t) * box.height * .22) : 0.0;
    final y = startY + (restY - startY) * p - bounce;
    final frame = rolling && t < .9 ? 'die_roll_${((t * 40).floor() + i * 3) % 8}' : 'die_${_faces[i]}';
    final spin = rolling ? (1 - t) * (i == 0 ? 7 : -8) : 0.0;
    return Stack(children: [
      Positioned(left: x + size * .1, top: y + size * .78 + bounce, child: GroundShadow(width: size * (.8 - bounce / box.height), opacity: .55)),
      Positioned(left: x, top: y, child: Transform.rotate(angle: spin, child: art(frame, size: size))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final sum = _faces[0] + _faces[1];
    return GameScaffold(
      title: 'Dice',
      color: const Color(0xFF0B4A33),
      help: 'Bet on the total of two dice. Big (8–12) and Small (2–6) pay x2.25. Seven pays x5.5.',
      child: Column(children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF5A3214), width: 10),
              gradient: const RadialGradient(colors: [Color(0xFF18805A), Color(0xFF0A4A32)]),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .7), blurRadius: 24, offset: const Offset(0, 12)), const BoxShadow(color: Color(0xFF8A5A2A), spreadRadius: -2)],
            ),
            child: LayoutBuilder(builder: (context, c) {
              final box = Size(c.maxWidth, c.maxHeight);
              return AnimatedBuilder(
                animation: _roll,
                builder: (_, __) => Stack(clipBehavior: Clip.hardEdge, children: [
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(_busy && _roll.isAnimating ? '' : '$sum', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white.withValues(alpha: .85))),
                    ),
                  ),
                  _die(0, box),
                  _die(1, box),
                ]),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final s in const [('small', 'SMALL', '2–6 · x2.25'), ('seven', 'SEVEN', '7 · x5.5'), ('big', 'BIG', '8–12 · x2.25')])
              Expanded(
                child: GestureDetector(
                  onTap: _busy
                      ? null
                      : () {
                          Sfx.play('tick');
                          setState(() => _side = s.$1);
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 72,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(colors: _side == s.$1 ? const [Color(0xFF1FA874), Color(0xFF0A5A3A)] : const [Color(0xFF14523A), Color(0xFF0A2E20)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                      border: Border.all(color: _side == s.$1 ? C.gold : Colors.white24, width: _side == s.$1 ? 2.5 : 1),
                      boxShadow: _side == s.$1 ? [BoxShadow(color: C.gold.withValues(alpha: .35), blurRadius: 14)] : null,
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                      Text(s.$3, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        ChipBar(value: _chip, minBet: widget.minBet, onChanged: (c) => setState(() => _chip = c)),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: PressButton(label: 'ROLL  ·  ${compact(_chip)}', busy: _busy, onTap: _go)),
      ]),
    );
  }
}
