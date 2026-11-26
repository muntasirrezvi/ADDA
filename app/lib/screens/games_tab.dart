import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'games.dart';
import 'games_kit.dart';
import 'wallet_screen.dart';

/// The Games tab: lucky games anyone can play on their own, any time.
/// Party games need friends, so they live inside rooms.
class GamesTab extends StatelessWidget {
  const GamesTab({super.key, required this.openRooms});
  final VoidCallback openRooms;

  Future<void> _play(BuildContext context, LuckyGame g) async {
    final minBet = await gamesGate(context);
    if (minBet == null || !context.mounted) return;
    Sfx.play('pop');
    await Navigator.push(context, MaterialPageRoute(builder: (_) => g.build(minBet, null)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Games'),
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.gold2)),
              child: Row(children: [
                ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(compact(c), size: 14)),
                const SizedBox(width: 4),
                const Icon(Icons.add_circle, color: C.gold, size: 18),
              ]),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 30), children: [
        const Text('Play solo — no room needed. Results are drawn on our server, fair for everyone.', style: TextStyle(color: C.mute, fontSize: 12)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: .9,
          children: [for (final g in luckyGames) _Card(game: g, onTap: () => _play(context, g))],
        ),
        const Section('Party games'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2A1F5A), Color(0xFF120D24)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (final a in const ['lk_pin_red', 'piece_x', 'rps_scissors', 'luckybag', 'bottle', 'vs']) Padding(padding: const EdgeInsets.only(right: 4), child: art(a, size: 40)),
            ]),
            const SizedBox(height: 10),
            const Text('Ludo, Tic-Tac-Toe, Rock Paper Scissors, Lucky Bag, PK Battle and Spin the Bottle', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('These are played live with other people, so they start inside a voice room. Join or create a room, then tap the games button.', style: TextStyle(color: C.mute, fontSize: 12)),
            const SizedBox(height: 10),
            GoldButton(label: 'Find a room to play', icon: Icons.mic_external_on, onTap: openRooms),
          ]),
        ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.game, required this.onTap});
  final LuckyGame game;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = game.color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(center: const Alignment(0, -.5), radius: 1.1, colors: [Color.lerp(c, Colors.white, .18)!, c, Color.lerp(c, Colors.black, .72)!]),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
          boxShadow: [BoxShadow(color: c.withValues(alpha: .35), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Center(child: Floaty(amp: 4, phase: game.title.length / 9, child: art(game.image)))),
          Text(game.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          Text(game.about, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70, height: 1.2)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
            child: Text(game.short, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.gold)),
          ),
        ]),
      ),
    );
  }
}
