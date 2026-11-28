import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import 'common.dart';

/// "X joined the room": a golden banner flies across the top of the room, and people with a
/// higher level get a big metallic "Lv.N" entrance in the middle of the room.
class EntryShow extends StatefulWidget {
  const EntryShow({super.key, required this.row, required this.onDone});
  final Map<String, dynamic> row;
  final VoidCallback onDone;
  @override
  State<EntryShow> createState() => _EntryShowState();
}

class _EntryShowState extends State<EntryShow> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200), animationBehavior: AnimationBehavior.preserve);
  static final _sparks = List.generate(26, (i) {
    final r = math.Random(i * 13 + 5);
    return [r.nextDouble(), r.nextDouble(), r.nextDouble(), r.nextDouble()];
  });

  @override
  void initState() {
    super.initState();
    _a.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Profiles.get(widget.row['user_id'] as String?);
    final lv = (p?['wealth_level'] as num?)?.toInt() ?? 1;
    final tier = lv >= 30 ? 3 : (lv >= 15 ? 2 : (lv >= 5 ? 1 : 0));
    const frames = [
      [Color(0xFF1E8C6E), Color(0xFF0B3D33), Color(0xFF7CF5B5)],
      [Color(0xFF4A2BC2), Color(0xFF1A0E52), Color(0xFFB9A6FF)],
      [Color(0xFFB0122B), Color(0xFF4A0611), Color(0xFFFFC94A)],
      [Color(0xFFE9B949), Color(0xFF6B4A12), Color(0xFFFFF3B0)],
    ];
    final f = frames[tier];
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        return AnimatedBuilder(
          animation: _a,
          builder: (_, __) {
            final t = _a.value;
            // banner: fly in from the right, hold, fly out to the left
            final inT = Curves.easeOutCubic.transform((t / .18).clamp(0.0, 1.0));
            final outT = Curves.easeInCubic.transform(((t - .8) / .2).clamp(0.0, 1.0));
            final x = w * (1 - inT) - w * 1.1 * outT;
            final shine = ((t - .15) / .5).clamp(0.0, 1.0);
            return Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: x + 10,
                top: 0,
                width: w - 20,
                child: _banner(p, lv, f, shine),
              ),
              if (tier >= 1) Positioned.fill(top: 80, child: _levelShow(lv, f, t)),
            ]);
          },
        );
      }),
    );
  }

  Widget _banner(Map<String, dynamic>? p, int lv, List<Color> f, double shine) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: LinearGradient(colors: [f[0], f[1], f[1].withValues(alpha: .0)], stops: const [0, .6, 1]),
        border: Border.all(color: f[2].withValues(alpha: .9), width: 1.5),
        boxShadow: [BoxShadow(color: f[0].withValues(alpha: .6), blurRadius: 16)],
      ),
      child: ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment(-1.6 + shine * 3.2, 0),
          end: Alignment(-1.1 + shine * 3.2, 0),
          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .55), Colors.white.withValues(alpha: 0)],
        ).createShader(r),
        child: Row(children: [
          const SizedBox(width: 3),
          Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: f[2], width: 2)),
            child: Avatar(profile: p, size: 38),
          ),
          const SizedBox(width: 8),
          LevelBadge(lv),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${p?['username'] ?? 'Someone'}', style: TextStyle(color: f[2], fontWeight: FontWeight.w900)),
                const TextSpan(text: '  joined the room', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
            ),
          ),
          const SizedBox(width: 30),
        ]),
      ),
    );
  }

  /// Big metallic "Lv.N" with light sweep and sparks.
  Widget _levelShow(int lv, List<Color> f, double t) {
    final appear = Curves.elasticOut.transform(((t - .05) / .35).clamp(0.0, 1.0));
    final fade = 1 - ((t - .75) / .25).clamp(0.0, 1.0);
    final sweep = ((t - .2) / .5).clamp(0.0, 1.0);
    return Opacity(
      opacity: fade,
      child: Align(
        alignment: const Alignment(0, .35),
        child: Transform.scale(
          scale: .4 + .6 * appear,
          child: SizedBox(
            width: 260,
            height: 120,
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              // glow plate
              Container(
                width: 220,
                height: 70,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  gradient: RadialGradient(colors: [f[2].withValues(alpha: .45), f[0].withValues(alpha: 0)]),
                ),
              ),
              CustomPaint(size: const Size(260, 120), painter: _SparkPainter(_sparks, t, f[2])),
              // dark outline for depth
              Text('Lv.$lv',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 1,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 7
                      ..color = const Color(0xFF2A1A05),
                  )),
              ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (r) => LinearGradient(
                  begin: Alignment(-1.5 + sweep * 3, -.4),
                  end: Alignment(-1 + sweep * 3, .4),
                  colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .85), Colors.white.withValues(alpha: 0)],
                ).createShader(r),
                child: ShaderMask(
                  shaderCallback: (r) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [const Color(0xFFFFFDF0), f[2], const Color(0xFFB8741A), const Color(0xFFFFE9A8), const Color(0xFF8A5A0A)],
                    stops: const [0, .35, .55, .7, 1],
                  ).createShader(r),
                  child: Text('Lv.$lv', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: 1, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.sparks, this.t, this.color);
  final List<List<double>> sparks;
  final double t;
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    for (final p in sparks) {
      final life = ((t - p[2] * .4) / .6).clamp(0.0, 1.0);
      if (life <= 0 || life >= 1) continue;
      final a = p[0] * math.pi * 2;
      final d = 20 + life * (60 + p[1] * 90);
      final pos = c + Offset(math.cos(a) * d * 1.4, math.sin(a) * d * .6);
      final r = (1 - life) * (2 + p[3] * 3);
      canvas.drawCircle(pos, r * 2.2, Paint()..color = color.withValues(alpha: .25 * (1 - life)));
      canvas.drawCircle(pos, r, Paint()..color = Colors.white.withValues(alpha: 1 - life));
    }
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.t != t;
}
