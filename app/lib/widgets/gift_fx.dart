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

/// Gifts with bundled 3D art (assets/gifts/<id>.webp) and full-screen animations (anim_<id>.webp).
const _bundledGifts = {'rose', 'coffee', 'kiss', 'perfume', 'teddy', 'snowflake', 'moon', 'firework', 'ring', 'crown', 'car', 'falcon', 'yacht', 'jet', 'palace', 'dragon', 'phoenix'};
const _animatedGifts = {'ring', 'crown', 'car', 'falcon', 'yacht', 'jet', 'palace', 'dragon', 'phoenix'};

class GiftIcon extends StatelessWidget {
  const GiftIcon({super.key, required this.gift, this.size = 44});
  final Map<String, dynamic> gift;
  final double size;
  @override
  Widget build(BuildContext context) {
    final url = gift['icon_url'] as String?;
    final id = '${gift['id']}';
    final look = giftLook[id] ?? (Icons.card_giftcard, const [C.gold, C.gold2]);
    final fallback = ShaderMask(
      shaderCallback: (r) => LinearGradient(colors: look.$2, begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(r),
      child: Icon(look.$1, size: size, color: Colors.white),
    );
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(imageUrl: url, width: size, height: size, fit: BoxFit.contain, errorWidget: (_, __, ___) => fallback);
    }
    if (_bundledGifts.contains(id)) {
      return Image.asset('assets/gifts/$id.webp', width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.medium, errorBuilder: (_, __, ___) => fallback);
    }
    return fallback;
  }
}

class GiftShow {
  GiftShow({required this.gift, required this.from, required this.to, required this.qty, this.fromId, this.toId});
  final Map<String, dynamic> gift;
  final String from;
  final String to;
  final String? fromId;
  final String? toId;
  final int qty;
}

/// Gift animations, played one after another: small gifts fly to the person who receives them;
/// big gifts take over the room with a 3D animation.
class GiftStage extends StatefulWidget {
  const GiftStage({super.key, required this.controller});
  final GiftStageController controller;
  @override
  State<GiftStage> createState() => _GiftStageState();
}

class GiftStageController {
  _GiftStageState? _s;
  final _queue = <GiftShow>[];

  /// Where a person sits on screen (global coordinates), if they are on a seat.
  Offset? Function(String uid)? seatPos;

  void play(GiftShow g) {
    if (_queue.length > 20) return; // drop floods
    _queue.add(g);
    _s?._next();
  }
}

class _GiftStageState extends State<GiftStage> with TickerProviderStateMixin {
  GiftShow? _now;
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200), animationBehavior: AnimationBehavior.preserve);
  final _rnd = Random();
  List<_P> _ps = [];
  String _theme = 'sparkle';
  bool _big = false;
  Offset? _target;
  int _playId = 0;

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
    final id = '${g.gift['id']}';
    final price = (g.gift['price'] as num?)?.toInt() ?? 0;
    final big = price >= 1000000 || (g.gift['animation_url'] as String? ?? '').isNotEmpty;
    _ps = List.generate(big ? 120 : 40, (_) => _P(_rnd));
    _theme = _themeFor(id);
    _big = big;
    _playId++;
    // where the small gift flies to (local coordinates of this stage)
    _target = null;
    final box = context.findRenderObject() as RenderBox?;
    final pos = g.toId == null ? null : widget.controller.seatPos?.call(g.toId!);
    if (box != null && pos != null) _target = box.globalToLocal(pos);
    _a.duration = Duration(milliseconds: big ? (_animatedGifts.contains(id) ? 4200 : 3600) : 1900);
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
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        return AnimatedBuilder(
          animation: _a,
          builder: (context, _) => _big ? _bigShow(g, box.biggest) : _flyShow(g, box.biggest),
        );
      }),
    );
  }

  // ---------------------------------------------------------------- small gifts: fly to the receiver
  Widget _flyShow(GiftShow g, Size size) {
    final t = _a.value;
    final start = Offset(size.width / 2, size.height - 90);
    final end = _target ?? Offset(size.width / 2, size.height * .42);
    final mid = Offset((start.dx + end.dx) / 2 + (end.dx > start.dx ? -60 : 60), min(start.dy, end.dy) - 120);
    // 0-.15 pop up · .15-.7 fly along an arc · .7-1 burst at the receiver
    final fly = Curves.easeInOutCubic.transform(((t - .15) / .55).clamp(0.0, 1.0));
    Offset bez(double u) => start * ((1 - u) * (1 - u)) + mid * (2 * u * (1 - u)) + end * (u * u);
    final p = bez(fly);
    final pop = Curves.elasticOut.transform((t / .22).clamp(0.0, 1.0));
    final scale = t < .15 ? .3 + 1.2 * pop : (t < .7 ? 1.5 - .7 * fly : .8 * (1 - ((t - .7) / .3).clamp(0.0, 1.0)));
    final burst = ((t - .66) / .34).clamp(0.0, 1.0);
    const size0 = 90.0;
    return Stack(children: [
      // glowing trail
      if (t > .15 && t < .75)
        CustomPaint(size: size, painter: _Trail([for (var k = 0; k < 10; k++) bez((fly - k * .035).clamp(0.0, 1.0))], _colorFor(g))),
      if (burst > 0) Positioned.fill(child: CustomPaint(painter: _Burst.at(_ps, burst, giftLook[g.gift['id']]?.$2 ?? const [C.gold, C.gold2], 'sparkle', center: end, radius: 110))),
      Positioned(
        left: p.dx - size0 / 2,
        top: p.dy - size0 / 2,
        child: Transform.scale(scale: scale.clamp(0.0, 2.0), child: SizedBox(width: size0, height: size0, child: GiftIcon(gift: g.gift, size: size0))),
      ),
      // combo bar on the left like a live stream
      Positioned(left: 8, top: size.height * .52, child: _comboBar(g, t)),
    ]);
  }

  Widget _comboBar(GiftShow g, double t) {
    final inT = Curves.easeOutBack.transform((t / .2).clamp(0.0, 1.0));
    final outT = ((t - .85) / .15).clamp(0.0, 1.0);
    return Opacity(
      opacity: (1 - outT).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(-260 * (1 - inT), 0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(colors: [Color(0xEE6A1B9A), Color(0x006A1B9A)]),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(g.from, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                Text('to ${g.to}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFFE07A), fontSize: 11)),
              ]),
            ),
            const SizedBox(width: 6),
            GiftIcon(gift: g.gift, size: 36),
            const SizedBox(width: 4),
            Transform.scale(
              scale: 1 + .4 * (1 - Curves.easeOut.transform(((t - .2) / .2).clamp(0.0, 1.0))),
              child: Text('×${g.qty}', style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- big gifts: the whole room
  Widget _bigShow(GiftShow g, Size size) {
    final t = _a.value;
    final id = '${g.gift['id']}';
    final colors = giftLook[id]?.$2 ?? const [C.gold, C.gold2];
    final fadeIn = Curves.easeOut.transform((t / .1).clamp(0.0, 1.0));
    final fadeOut = 1 - Curves.easeIn.transform(((t - .86) / .14).clamp(0.0, 1.0));
    final anim = g.gift['animation_url'] as String?;
    final title = Curves.elasticOut.transform(((t - .08) / .4).clamp(0.0, 1.0));
    Widget hero;
    if (anim != null && anim.endsWith('.json')) {
      hero = Lottie.network(anim, repeat: false, errorBuilder: (_, __, ___) => GiftIcon(gift: g.gift, size: 260));
    } else if (anim != null && anim.isNotEmpty) {
      hero = CachedNetworkImage(imageUrl: anim, errorWidget: (_, __, ___) => GiftIcon(gift: g.gift, size: 260));
    } else if (_animatedGifts.contains(id)) {
      // pre-rendered 3D animation; a new key restarts it every time
      hero = Image.asset('assets/gifts/anim_$id.webp', key: ValueKey('anim$_playId'), fit: BoxFit.contain, gaplessPlayback: false, errorBuilder: (_, __, ___) => GiftIcon(gift: g.gift, size: 260));
    } else {
      final scale = Curves.elasticOut.transform((t / .45).clamp(0.0, 1.0));
      hero = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0018)
          ..rotateY((1 - Curves.easeOutCubic.transform((t / .4).clamp(0.0, 1.0))) * pi * 1.6 + sin(t * pi * 4) * .12)
          ..scale(.2 + .8 * scale),
        child: GiftIcon(gift: g.gift, size: 260),
      );
    }
    final heroSize = min(size.width * .95, size.height * .55);
    return Opacity(
      opacity: (fadeIn * fadeOut).clamp(0.0, 1.0),
      child: Stack(fit: StackFit.expand, children: [
        Container(decoration: BoxDecoration(gradient: RadialGradient(colors: [colors.first.withValues(alpha: .38), Colors.black.withValues(alpha: .7)], radius: .95))),
        CustomPaint(painter: _Rays(t, colors.first)),
        CustomPaint(painter: _Burst(_ps, t, colors, _theme)),
        Align(
          alignment: const Alignment(0, -.12),
          child: Container(
            width: heroSize,
            height: heroSize,
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: colors.first.withValues(alpha: .35), blurRadius: 90, spreadRadius: 10)]),
            child: hero,
          ),
        ),
        // gift name in metallic letters
        Align(
          alignment: const Alignment(0, .5),
          child: Transform.scale(scale: .3 + .7 * title, child: _metalTitle('${g.gift['name']}', t)),
        ),
        // who sent it to whom
        Align(
          alignment: const Alignment(0, .7),
          child: Container(
            constraints: BoxConstraints(maxWidth: size.width - 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xCC3A0A12), Color(0xCC8A0E12), Color(0xCC3A0A12)]),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFFFC94A), width: 1.5),
            ),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: g.from, style: const TextStyle(color: Color(0xFFFFE07A), fontWeight: FontWeight.w800)),
                const TextSpan(text: '  sent  '),
                TextSpan(text: '${g.gift['name']} ×${g.qty}', style: const TextStyle(fontWeight: FontWeight.w800)),
                const TextSpan(text: '  to  '),
                TextSpan(text: g.to, style: const TextStyle(color: Color(0xFFFFE07A), fontWeight: FontWeight.w800)),
              ]),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _metalTitle(String text, double t) {
    final sweep = ((t - .25) / .5).clamp(0.0, 1.0);
    const style = TextStyle(fontSize: 46, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: .5, height: 1);
    return FittedBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(children: [
          Text(text, style: style.copyWith(foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = const Color(0xFF3A1A00))),
          ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment(-1.5 + sweep * 3, -.4),
              end: Alignment(-1 + sweep * 3, .4),
              colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .9), Colors.white.withValues(alpha: 0)],
            ).createShader(r),
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFDF0), Color(0xFFFFD54F), Color(0xFFB8741A), Color(0xFFFFE9A8), Color(0xFF8A5A0A)],
                stops: [0, .35, .55, .7, 1],
              ).createShader(r),
              child: Text(text, style: style.copyWith(color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  Color _colorFor(GiftShow g) => (giftLook[g.gift['id']]?.$2 ?? const [C.gold]).first;
}

class _Trail extends CustomPainter {
  _Trail(this.pts, this.color);
  final List<Offset> pts;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < pts.length; i++) {
      final f = 1 - i / pts.length;
      canvas.drawCircle(pts[i], 16 * f, Paint()..color = color.withValues(alpha: .25 * f)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(pts[i], 4 * f, Paint()..color = Colors.white.withValues(alpha: .8 * f));
    }
  }

  @override
  bool shouldRepaint(_Trail o) => true;
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
  _Burst(this.ps, this.t, this.colors, [this.theme = 'sparkle', this.center, this.radius]);
  _Burst.at(this.ps, this.t, this.colors, this.theme, {this.center, this.radius});
  final List<_P> ps;
  final double t;
  final List<Color> colors;
  final String theme;
  final Offset? center;
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (theme == 'petals') return _petals(canvas, size, const [Color(0xFFFF4D6D), Color(0xFFFF8FA3), Color(0xFFC9184A)]);
    if (theme == 'snow') return _fall(canvas, size, const [Colors.white, Color(0xFFDDF3FF)], round: true);
    if (theme == 'fire') return _embers(canvas, size);
    final c = center ?? size.center(Offset.zero);
    final maxR = radius ?? size.shortestSide * .75;
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
