import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme.dart';

/// Built-in look for each gift when the admin has not uploaded an icon or animation.
const giftLook = <String, (IconData, List<Color>)>{
  'rose': (Icons.local_florist, [Color(0xFFFF6B8B), Color(0xFFB0123C)]),
  'coffee': (Icons.coffee, [Color(0xFFD9A066), Color(0xFF6B3A12)]),
  'kiss': (Icons.favorite, [Color(0xFFFF7AA2), Color(0xFFC9184A)]),
  'perfume': (Icons.spa, [Color(0xFFE9C9FF), Color(0xFF7B3FB8)]),
  'teddy': (Icons.toys, [Color(0xFFD9A066), Color(0xFF8A5A2B)]),
  'ring': (Icons.diamond, [Color(0xFFBFEFFF), Color(0xFF3D8BD9)]),
  'crown': (Icons.workspace_premium, [Color(0xFFF0D9A6), Color(0xFFB8924F)]),
  'car': (Icons.directions_car, [Color(0xFFFF5E5E), Color(0xFF8A0F0F)]),
  'falcon': (Icons.flutter_dash, [Color(0xFFF0D9A6), Color(0xFF8A6A2B)]),
  'yacht': (Icons.sailing, [Color(0xFFBFEFFF), Color(0xFF1F5FA8)]),
  'jet': (Icons.flight, [Color(0xFFE6E6E6), Color(0xFF5A6B80)]),
  'palace': (Icons.castle, [Color(0xFFF0D9A6), Color(0xFF8A2B4F)]),
  'dragon': (Icons.whatshot, [Color(0xFF7CF5B5), Color(0xFF0F6B45)]),
  'phoenix': (Icons.local_fire_department, [Color(0xFFFFC46B), Color(0xFFC9300F)]),
  'snowflake': (Icons.ac_unit, [Color(0xFFE6F7FF), Color(0xFF5AB2E6)]),
  'moon': (Icons.nightlight_round, [Color(0xFFFFF3C4), Color(0xFFC9A23A)]),
  'firework': (Icons.celebration, [Color(0xFFFFD36B), Color(0xFFE6398F)]),
};

class GiftIcon extends StatelessWidget {
  const GiftIcon({super.key, required this.gift, this.size = 44});
  final Map<String, dynamic> gift;
  final double size;
  @override
  Widget build(BuildContext context) {
    final url = gift['icon_url'] as String?;
    final look = giftLook[gift['id']] ?? (Icons.card_giftcard, const [C.gold, C.gold2]);
    final art = ShaderMask(
      shaderCallback: (r) => LinearGradient(colors: look.$2, begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(r),
      child: Icon(look.$1, size: size, color: Colors.white),
    );
    if (url == null || url.isEmpty) return art;
    return CachedNetworkImage(imageUrl: url, width: size, height: size, fit: BoxFit.contain, errorWidget: (_, __, ___) => art);
  }
}

class GiftShow {
  GiftShow({required this.gift, required this.from, required this.to, required this.qty});
  final Map<String, dynamic> gift;
  final String from;
  final String to;
  final int qty;
}

/// Full-screen gift animations, played one after another.
class GiftStage extends StatefulWidget {
  const GiftStage({super.key, required this.controller});
  final GiftStageController controller;
  @override
  State<GiftStage> createState() => _GiftStageState();
}

class GiftStageController {
  _GiftStageState? _s;
  final _queue = <GiftShow>[];
  void play(GiftShow g) {
    if (_queue.length > 20) return; // drop floods
    _queue.add(g);
    _s?._next();
  }
}

class _GiftStageState extends State<GiftStage> with TickerProviderStateMixin {
  GiftShow? _now;
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  final _rnd = Random();
  List<_P> _ps = [];

  @override
  void initState() {
    super.initState();
    widget.controller._s = this;
    _a.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _now = null);
        _next();
      }
    });
    _next();
  }

  void _next() {
    if (!mounted || _now != null || widget.controller._queue.isEmpty) return;
    final g = widget.controller._queue.removeAt(0);
    final price = (g.gift['price'] as num?)?.toInt() ?? 0;
    final big = price >= 1000000;
    _ps = List.generate(big ? 90 : 40, (_) => _P(_rnd));
    _a.duration = Duration(milliseconds: big ? 4200 : 2800);
    setState(() => _now = g);
    _a.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller._s = null;
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = _now;
    if (g == null) return const SizedBox.shrink();
    final anim = g.gift['animation_url'] as String?;
    final look = giftLook[g.gift['id']] ?? (Icons.card_giftcard, const [C.gold, C.gold2]);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, _) {
          final t = _a.value;
          final fadeIn = Curves.easeOut.transform((t / .15).clamp(0.0, 1.0));
          final fadeOut = 1 - Curves.easeIn.transform(((t - .82) / .18).clamp(0.0, 1.0));
          final scale = Curves.elasticOut.transform((t / .45).clamp(0.0, 1.0));
          return Opacity(
            opacity: (fadeIn * fadeOut).clamp(0.0, 1.0),
            child: Stack(fit: StackFit.expand, children: [
              Container(decoration: BoxDecoration(gradient: RadialGradient(colors: [look.$2.first.withValues(alpha: .35), Colors.black.withValues(alpha: .55)], radius: .9))),
              CustomPaint(painter: _Burst(_ps, t, look.$2)),
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Transform.scale(
                    scale: .2 + .8 * scale,
                    child: SizedBox(
                      width: 240,
                      height: 240,
                      child: (anim != null && anim.endsWith('.json'))
                          ? Lottie.network(anim, repeat: false, errorBuilder: (_, __, ___) => GiftIcon(gift: g.gift, size: 200))
                          : (anim != null && (anim.endsWith('.webp') || anim.endsWith('.gif')))
                              ? CachedNetworkImage(imageUrl: anim, errorWidget: (_, __, ___) => GiftIcon(gift: g.gift, size: 200))
                              : Transform.rotate(angle: sin(t * pi * 6) * .06, child: GiftIcon(gift: g.gift, size: 200)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30), border: Border.all(color: C.gold.withValues(alpha: .6))),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: g.from, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700)),
                        const TextSpan(text: '  sent  '),
                        TextSpan(text: '${g.gift['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' ×${g.qty}', style: serif(18, color: C.gold)),
                        const TextSpan(text: '  to  '),
                        TextSpan(text: g.to, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700)),
                      ]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _P {
  _P(Random r)
      : angle = r.nextDouble() * pi * 2,
        speed = .25 + r.nextDouble() * .75,
        size = 2 + r.nextDouble() * 5,
        spin = r.nextDouble(),
        color = r.nextInt(3);
  final double angle, speed, size, spin;
  final int color;
}

class _Burst extends CustomPainter {
  _Burst(this.ps, this.t, this.colors);
  final List<_P> ps;
  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide * .75;
    final palette = [...colors, C.gold];
    for (final p in ps) {
      final d = Curves.easeOutCubic.transform(t) * maxR * p.speed;
      final pos = c + Offset(cos(p.angle), sin(p.angle)) * d + Offset(0, t * t * 120);
      final paint = Paint()..color = palette[p.color % palette.length].withValues(alpha: (1 - t).clamp(0.0, 1.0));
      if (p.spin > .5) {
        canvas.drawCircle(pos, p.size, paint);
      } else {
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(t * 8 * p.spin);
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size * 2, height: p.size), paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_Burst old) => true;
}
