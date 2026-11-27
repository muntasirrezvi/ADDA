import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../widgets/common.dart';
import 'games_kit.dart';

/// Chip values for the live games (no maximum: the big chips go up to 100M).
const casinoChips = [1000, 5000, 10000, 50000, 100000, 500000, 1000000, 5000000, 10000000, 50000000, 100000000];

Color chipColor(int v) {
  if (v >= 100000000) return const Color(0xFF111111);
  if (v >= 50000000) return const Color(0xFF0E7C86);
  if (v >= 10000000) return const Color(0xFFB8860B);
  if (v >= 5000000) return const Color(0xFF6A1B9A);
  if (v >= 1000000) return const Color(0xFF1565C0);
  if (v >= 500000) return const Color(0xFFE65100);
  if (v >= 100000) return const Color(0xFF8E24AA);
  if (v >= 50000) return const Color(0xFFC62828);
  if (v >= 10000) return const Color(0xFFEF6C00);
  if (v >= 5000) return const Color(0xFF1E88E5);
  return const Color(0xFF2E9D3A);
}

/// A casino chip drawn in code, so any value has one.
class PokerChip extends StatelessWidget {
  const PokerChip({super.key, required this.value, this.size = 56, this.selected = false});
  final int value;
  final double size;
  final bool selected;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: size,
        height: size,
        transform: Matrix4.translationValues(0, selected ? -6 : 0, 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            if (selected) const BoxShadow(color: Color(0xCCFFE07A), blurRadius: 14, spreadRadius: 2),
            const BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 3)),
          ],
        ),
        child: CustomPaint(painter: _ChipPainter(chipColor(value)), child: Center(
          child: Padding(
            padding: EdgeInsets.all(size * .2),
            child: FittedBox(child: Text(compact(value), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black54, blurRadius: 3)]))),
          ),
        )),
      );
}

class _ChipPainter extends CustomPainter {
  _ChipPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [Color.lerp(color, Colors.white, .25)!, color, Color.lerp(color, Colors.black, .35)!], stops: const [0, .7, 1]).createShader(Rect.fromCircle(center: c, radius: r)));
    final edge = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = r * .2;
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * .88), a, math.pi / 9, false, edge);
    }
    canvas.drawCircle(c, r * .66, Paint()..color = Colors.white.withValues(alpha: .9)..style = PaintingStyle.stroke..strokeWidth = r * .05);
    canvas.drawCircle(c, r * .62, Paint()..color = Color.lerp(color, Colors.black, .15)!);
  }

  @override
  bool shouldRepaint(_ChipPainter o) => o.color != color;
}

/// Rounded gold-trimmed panel used by the casino games.
class GoldPanel extends StatelessWidget {
  const GoldPanel({super.key, required this.child, this.color = const Color(0xFF5A2A3A), this.padding = const EdgeInsets.all(10)});
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(color, Colors.white, .08)!, color]),
          border: Border.all(color: const Color(0xFFE9B949), width: 2),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: child,
      );
}

/// Five treasure chests that open as you bet more today. Tap a glowing chest to collect it.
class ChestBar extends StatelessWidget {
  const ChestBar({super.key, required this.state, required this.onClaim});
  final Map<String, dynamic>? state;
  final void Function(int level) onClaim;
  @override
  Widget build(BuildContext context) {
    final s = state;
    final bet = (s?['bet'] as num? ?? 0).toInt();
    final levels = [for (final l in (s?['levels'] as List? ?? const [5000000, 50000000, 250000000, 500000000, 2500000000])) (l as num).toInt()];
    final rewards = [for (final r in (s?['rewards'] as List? ?? const [])) (r as num).toInt()];
    final opened = {for (final o in (s?['opened'] as List? ?? const [])) (o as num).toInt()};
    // progress across equal steps, so the small chests are easy to see
    var progress = 0.0;
    for (var i = 0; i < levels.length; i++) {
      final lo = i == 0 ? 0 : levels[i - 1];
      if (bet >= levels[i]) {
        progress = (i + 1) / levels.length;
      } else {
        progress += ((bet - lo) / (levels[i] - lo)).clamp(0.0, 1.0) / levels.length;
        break;
      }
    }
    return GoldPanel(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: SizedBox(
        height: 92,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          return Stack(children: [
            Positioned(
              left: w * .06,
              right: w * .06,
              top: 34,
              child: Container(
                height: 10,
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(6)),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), gradient: const LinearGradient(colors: [Color(0xFFFFE07A), Color(0xFFE9A92A)]))),
                ),
              ),
            ),
            for (var i = 0; i < levels.length; i++)
              Positioned(
                left: w * (.1 + i * .2) - 30,
                top: 0,
                width: 60,
                child: GestureDetector(
                  onTap: () {
                    if (opened.contains(i + 1)) {
                      toast(context, 'Already collected today');
                    } else if (bet >= levels[i]) {
                      onClaim(i + 1);
                    } else {
                      toast(context, 'Bet ${compact(levels[i] - bet)} more today to open it${i < rewards.length ? ' (${compact(rewards[i])} coins)' : ''}');
                    }
                  },
                  child: Column(children: [
                    _ChestIcon(level: i + 1, ready: bet >= levels[i] && !opened.contains(i + 1), opened: opened.contains(i + 1)),
                    const SizedBox(height: 4),
                    Text(compact(levels[i]), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  ]),
                ),
              ),
          ]);
        }),
      ),
    );
  }
}

class _ChestIcon extends StatefulWidget {
  const _ChestIcon({required this.level, required this.ready, required this.opened});
  final int level;
  final bool ready;
  final bool opened;
  @override
  State<_ChestIcon> createState() => _ChestIconState();
}

class _ChestIconState extends State<_ChestIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget img = art('chest_${widget.level}', size: 52);
    if (widget.opened) img = Opacity(opacity: .45, child: img);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.scale(
        scale: widget.ready ? 1 + .08 * _c.value : 1,
        child: Container(
          decoration: widget.ready ? BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFFFE07A).withValues(alpha: .5 + .4 * _c.value), blurRadius: 18)]) : null,
          child: child,
        ),
      ),
      child: Stack(alignment: Alignment.center, children: [
        img,
        if (widget.opened) const Icon(Icons.check_circle, color: Color(0xFF6BE675), size: 22),
      ]),
    );
  }
}

/// Collect a chest and show the reward.
Future<Map<String, dynamic>?> claimChest(BuildContext context, String game, int level) async {
  try {
    final r = Map<String, dynamic>.from(await App.i.rpc('game_chest_claim', {'p_game': game, 'p_level': level}) as Map);
    App.i.coins.value = (r['coins'] as num).toInt();
    Sfx.play('coin');
    if (context.mounted) toast(context, 'Chest opened: +${compact(r['reward'] as num)} coins');
    return Map<String, dynamic>.from(r['chests'] as Map);
  } catch (e) {
    if (context.mounted) toast(context, errText(e), bad: true);
    return null;
  }
}
