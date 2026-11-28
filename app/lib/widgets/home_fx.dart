import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';

/// One shared clock for every light home-screen effect (seconds since start).
/// Painters listen to it directly, so nothing rebuilds — only small canvases repaint.
/// The ticker stops by itself when another screen covers the home screen (TickerMode).
class FxClock extends InheritedWidget {
  const FxClock({super.key, required this.time, required super.child});
  final ValueNotifier<double> time;

  static ValueNotifier<double>? of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<FxClock>()?.time;

  @override
  bool updateShouldNotify(FxClock old) => old.time != time;
}

class FxClockHost extends StatefulWidget {
  const FxClockHost({super.key, required this.child});
  final Widget child;
  @override
  State<FxClockHost> createState() => _FxClockHostState();
}

class _FxClockHostState extends State<FxClockHost> with SingleTickerProviderStateMixin {
  final _t = ValueNotifier<double>(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      // ~30 fps is plenty for ambient effects and halves the work
      if (++_frame % 2 == 1) return;
      final dt = (d - _last).inMicroseconds / 1e6;
      _last = d;
      _t.value += dt.clamp(0, .1);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FxClock(time: _t, child: widget.child);
}

/// Slow drifting gold dust and soft glows behind the home screen.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});
  @override
  Widget build(BuildContext context) {
    final t = FxClock.of(context);
    if (t == null) return const SizedBox.shrink();
    return IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _DustPainter(t), size: Size.infinite)));
  }
}

class _DustPainter extends CustomPainter {
  _DustPainter(this.t) : super(repaint: t);
  final ValueNotifier<double> t;
  static final _seeds = List.generate(26, (i) {
    final r = math.Random(i * 7919 + 13);
    return [r.nextDouble(), r.nextDouble(), .4 + r.nextDouble() * 1.8, .02 + r.nextDouble() * .05, r.nextDouble() * 6.28];
  });
  final _p = Paint();

  @override
  void paint(Canvas canvas, Size s) {
    final time = t.value;
    // two big soft glows that breathe slowly
    for (final g in const [(.15, .12, 0xFF6B2E8F), (.9, .55, 0xFF8F5E1E)]) {
      final pulse = .5 + .5 * math.sin(time * .5 + g.$1 * 10);
      final c = Offset(s.width * g.$1, s.height * g.$2);
      final rad = s.width * (.45 + .05 * pulse);
      _p.shader = RadialGradient(colors: [Color(g.$3).withValues(alpha: .10 + .05 * pulse), Colors.transparent]).createShader(Rect.fromCircle(center: c, radius: rad));
      canvas.drawCircle(c, rad, _p);
    }
    _p.shader = null;
    for (final d in _seeds) {
      final y = (d[1] - time * d[3]) % 1.0;
      final x = d[0] + .02 * math.sin(time * .6 + d[4]);
      final tw = .35 + .65 * (.5 + .5 * math.sin(time * 1.7 + d[4]));
      _p.color = C.gold.withValues(alpha: .28 * tw);
      canvas.drawCircle(Offset(x * s.width, y * s.height), d[2], _p);
    }
  }

  @override
  bool shouldRepaint(_DustPainter old) => false;
}

/// Gold text with a bright light sweep passing over it every few seconds.
class ShimmerText extends StatelessWidget {
  const ShimmerText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final t = FxClock.of(context);
    Widget paint(double time) {
      final p = (time % 4.0) / 4.0; // one sweep every 4 s, visible in the first 40%
      final x = -1.5 + (p / .4).clamp(0.0, 1.0) * 3.5;
      return ShaderMask(
        shaderCallback: (r) => LinearGradient(
          begin: Alignment(x - .6, -.4),
          end: Alignment(x + .6, .4),
          colors: const [Color(0xFFF0D9A6), Color(0xFFB8924F), Color(0xFFFFF6DD), Color(0xFFB8924F), Color(0xFFF0D9A6)],
          stops: const [0, .35, .5, .65, 1],
          tileMode: TileMode.clamp,
        ).createShader(r),
        child: Text(text, style: style.copyWith(color: Colors.white)),
      );
    }

    if (t == null) return paint(0);
    return RepaintBoundary(child: ValueListenableBuilder<double>(valueListenable: t, builder: (_, v, __) => paint(v)));
  }
}

/// Gentle up-down float, driven by the shared clock.
class FxFloat extends StatelessWidget {
  const FxFloat({super.key, required this.child, this.amp = 3, this.speed = 1.6, this.phase = 0});
  final Widget child;
  final double amp, speed, phase;
  @override
  Widget build(BuildContext context) {
    final t = FxClock.of(context);
    if (t == null) return child;
    return ValueListenableBuilder<double>(
      valueListenable: t,
      child: child,
      builder: (_, v, c) => Transform.translate(offset: Offset(0, amp * math.sin(v * speed + phase)), child: c),
    );
  }
}

/// Three tiny bouncing bars: "people are talking here".
class LiveBars extends StatelessWidget {
  const LiveBars({super.key, this.color = Colors.white, this.size = 12, this.seed = 0});
  final Color color;
  final double size;
  final int seed;
  @override
  Widget build(BuildContext context) {
    final t = FxClock.of(context);
    return SizedBox(width: size, height: size, child: t == null ? Icon(Icons.graphic_eq, size: size, color: color) : CustomPaint(painter: _BarsPainter(t, color, seed)));
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.t, this.color, this.seed) : super(repaint: t);
  final ValueNotifier<double> t;
  final Color color;
  final int seed;
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color;
    final w = s.width / 5;
    for (var i = 0; i < 3; i++) {
      final h = s.height * (.3 + .7 * (.5 + .5 * math.sin(t.value * (6 + i * 1.7) + seed + i * 2.1)).abs());
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(i * 2 * w, s.height - h, w, h), Radius.circular(w / 2)), p);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color;
}

/// Soft breathing gold border for featured rooms.
class GlowBorder extends StatelessWidget {
  const GlowBorder({super.key, required this.radius});
  final double radius;
  @override
  Widget build(BuildContext context) {
    final t = FxClock.of(context);
    if (t == null) return const SizedBox.shrink();
    return IgnorePointer(child: CustomPaint(painter: _GlowPainter(t, radius), size: Size.infinite));
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.t, this.radius) : super(repaint: t);
  final ValueNotifier<double> t;
  final double radius;
  @override
  void paint(Canvas canvas, Size s) {
    final a = .35 + .45 * (.5 + .5 * math.sin(t.value * 2.2));
    final rr = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(radius)).deflate(.75);
    canvas.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = SweepGradient(
        transform: GradientRotation(t.value * .8),
        colors: [C.gold.withValues(alpha: a), const Color(0xFFFFF1C9).withValues(alpha: a), C.gold2.withValues(alpha: a * .4), C.gold.withValues(alpha: a)],
      ).createShader(Offset.zero & s));
  }

  @override
  bool shouldRepaint(_GlowPainter old) => false;
}

/// Diagonal light streak sweeping across a banner every few seconds.
class LightSweep extends StatelessWidget {
  const LightSweep({super.key, this.period = 5, this.offset = 0});
  final double period, offset;
  @override
  Widget build(BuildContext context) {
    final t = FxClock.of(context);
    if (t == null) return const SizedBox.shrink();
    return IgnorePointer(child: CustomPaint(painter: _SweepPainter(t, period, offset), size: Size.infinite));
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.t, this.period, this.offset) : super(repaint: t);
  final ValueNotifier<double> t;
  final double period, offset;
  @override
  void paint(Canvas canvas, Size s) {
    final p = ((t.value + offset) % period) / period;
    if (p > .3) return;
    final x = -s.width * .4 + (p / .3) * s.width * 1.8;
    final band = s.width * .22;
    final rect = Rect.fromLTWH(x - band, 0, band * 2, s.height);
    canvas.save();
    canvas.translate(x, s.height / 2);
    canvas.skew(-.35, 0);
    canvas.translate(-x, -s.height / 2);
    canvas.drawRect(rect, Paint()
      ..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .22), Colors.white.withValues(alpha: 0)]).createShader(rect));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SweepPainter old) => false;
}

/// Fades and slides a child in once, with a small delay based on its position.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420), animationBehavior: AnimationBehavior.preserve);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 55 * math.min(widget.index, 8)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (_, c) => Opacity(
          opacity: _a.value,
          child: Transform.translate(offset: Offset(0, 24 * (1 - _a.value)), child: Transform.scale(scale: .96 + .04 * _a.value, child: c)),
        ),
      );
}

/// Press feedback: the card dips slightly while touched.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(scale: _down ? .96 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
      );
}
