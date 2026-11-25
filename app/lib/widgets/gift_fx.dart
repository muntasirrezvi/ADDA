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
  String _theme = 'sparkle';
  bool _big = false;

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
    _ps = List.generate(big ? 110 : 60, (_) => _P(_rnd));
    _theme = _themeFor('${g.gift['id']}');
    _big = big;
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
              if (_big) CustomPaint(painter: _Rays(t, look.$2.first)),
              CustomPaint(painter: _Burst(_ps, t, look.$2, _theme)),
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0018)
                      ..rotateY((1 - Curves.easeOutCubic.transform((t / .4).clamp(0.0, 1.0))) * pi * 1.6 + sin(t * pi * 4) * .12)
                      ..rotateX(sin(t * pi * 3) * .08)
                      ..scale(.2 + .8 * scale),
                    child: Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: look.$2.first.withValues(alpha: .55), blurRadius: 60, spreadRadius: 10)]),
                      child: SizedBox(
                        width: 240,
                        height: 240,
                        child: (anim != null && anim.endsWith('.json'))
                            ? Lottie.network(anim, repeat: false, errorBuilder: (_, __, ___) => GiftIcon(gift: g.gift, size: 200))
                            : (anim != null && (anim.endsWith('.webp') || anim.endsWith('.gif') || anim.endsWith('.png')))
                                ? CachedNetworkImage(imageUrl: anim, errorWidget: (_, __, ___) => GiftIcon(gift: g.gift, size: 200))
                                : ShaderMask(
                                    blendMode: BlendMode.srcATop,
                                    shaderCallback: (r) => LinearGradient(
                                      begin: Alignment(-1 + t * 4 - 1.2, -1),
                                      end: Alignment(-1 + t * 4 - .4, 1),
                                      colors: [Colors.transparent, Colors.white.withValues(alpha: .75), Colors.transparent],
                                    ).createShader(r),
                                    child: GiftIcon(gift: g.gift, size: 200),
                                  ),
                      ),
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

String _themeFor(String id) {
  if (const ['rose', 'kiss', 'perfume', 'teddy', 'ring'].contains(id)) return 'petals';
  if (const ['dragon', 'phoenix'].contains(id)) return 'fire';
  if (id == 'snowflake') return 'snow';
  if (const ['firework', 'moon'].contains(id)) return 'firework';
  return 'sparkle';
}

/// Rotating light rays behind big gifts.
class _Rays extends CustomPainter {
  _Rays(this.t, this.color);
  final double t;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.longestSide;
    canvas.save();
    canvas.translate(c.dx, c.dy - 30);
    canvas.rotate(t * pi * .8);
    final paint = Paint()..shader = RadialGradient(colors: [color.withValues(alpha: .5), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: Offset.zero, radius: r * .6));
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(cos(a - .09) * r, sin(a - .09) * r)
        ..lineTo(cos(a + .09) * r, sin(a + .09) * r)
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Rays old) => true;
}

class _Burst extends CustomPainter {
  _Burst(this.ps, this.t, this.colors, [this.theme = 'sparkle']);
  final List<_P> ps;
  final double t;
  final List<Color> colors;
  final String theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (theme == 'petals') return _petals(canvas, size, const [Color(0xFFFF4D6D), Color(0xFFFF8FA3), Color(0xFFC9184A)]);
    if (theme == 'snow') return _fall(canvas, size, const [Colors.white, Color(0xFFDDF3FF)], round: true);
    if (theme == 'fire') return _embers(canvas, size);
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

  // rose petals drifting down with a sway and spin
  void _petals(Canvas canvas, Size size, List<Color> cs) {
    for (final p in ps) {
      final y = -40 + (size.height + 80) * ((t * (0.6 + p.speed * .6) + p.spin) % 1.0);
      final x = size.width * ((p.angle / (2 * pi)) + .06 * sin(t * 6 + p.angle * 3));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 5 * (p.spin - .5) + p.angle);
      final paint = Paint()..color = cs[p.color % cs.length].withValues(alpha: .9 * (1 - t * .6));
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: p.size * 3.2, height: p.size * 2), paint);
      canvas.drawOval(Rect.fromCenter(center: Offset(p.size * .4, 0), width: p.size * 1.2, height: p.size * .6), Paint()..color = Colors.white.withValues(alpha: .25));
      canvas.restore();
    }
  }

  void _fall(Canvas canvas, Size size, List<Color> cs, {bool round = false}) {
    for (final p in ps) {
      final y = -20 + (size.height + 40) * ((t * (0.4 + p.speed * .5) + p.spin) % 1.0);
      final x = size.width * ((p.angle / (2 * pi)) + .03 * sin(t * 4 + p.angle * 5));
      canvas.drawCircle(Offset(x, y), p.size * .9, Paint()..color = cs[p.color % cs.length].withValues(alpha: .85));
    }
  }

  // glowing embers rising from the bottom
  void _embers(Canvas canvas, Size size) {
    for (final p in ps) {
      final y = size.height + 20 - (size.height + 40) * ((t * (0.5 + p.speed * .7) + p.spin) % 1.0);
      final x = size.width * ((p.angle / (2 * pi)) + .04 * sin(t * 8 + p.angle * 4));
      final c = [const Color(0xFFFFD36B), const Color(0xFFFF7A1A), const Color(0xFFFF3D00)][p.color % 3];
      canvas.drawCircle(Offset(x, y), p.size * 1.6, Paint()
        ..color = c.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(Offset(x, y), p.size * .7, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_Burst old) => true;
}
