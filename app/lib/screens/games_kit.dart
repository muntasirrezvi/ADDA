import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'wallet_screen.dart';

/// Rendered 3D game art bundled with the app (assets/games/*.webp).
String gameArt(String name) => 'assets/games/$name.webp';

Widget art(String name, {double? size, double? width, double? height, BoxFit fit = BoxFit.contain}) => Image.asset(
      gameArt(name),
      width: width ?? size,
      height: height ?? size,
      fit: fit,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );

/// Short sound effects. Each sound keeps a small pool of players so quick repeats overlap.
class Sfx {
  static final Map<String, List<AudioPlayer>> _pool = {};
  static final Map<String, int> _next = {};
  static bool muted = false;

  static Future<void> play(String name, {double volume = 1}) async {
    if (muted) return;
    try {
      final list = _pool.putIfAbsent(name, () => []);
      if (list.length < 3) {
        final p = AudioPlayer();
        await p.setAsset('assets/sfx/$name.wav');
        list.add(p);
      }
      final i = (_next[name] ?? 0) % list.length;
      _next[name] = i + 1;
      final p = list[i];
      await p.setVolume(volume);
      await p.seek(Duration.zero);
      unawaited(p.play());
    } catch (_) {
      // sound is a nice-to-have; never break a game over it
    }
  }
}

const gameChips = [10000, 50000, 100000, 500000, 1000000, 5000000];
const _chipArt = {10000: 'chip_10k', 50000: 'chip_50k', 100000: 'chip_100k', 500000: 'chip_500k', 1000000: 'chip_1m', 5000000: 'chip_5m'};

Future<Map<String, dynamic>?> playGame(BuildContext context, String game, {int bet = 0, Map<String, dynamic>? pick, int? roomId}) async {
  try {
    return Map<String, dynamic>.from(await App.i.rpc('play_game', {'p_game': game, 'p_bet': bet, 'p_pick': pick ?? {}, 'p_room': roomId}) as Map);
  } catch (e) {
    if (!context.mounted) return null;
    final msg = errText(e);
    toast(context, msg, bad: true);
    if (msg.toLowerCase().contains('insufficient')) Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
    return null;
  }
}

void settleCoins(Map<String, dynamic> r) => App.i.coins.value = (r['coins'] as num).toInt();

/// Real casino chips to pick the bet with.
class ChipBar extends StatelessWidget {
  const ChipBar({super.key, required this.value, required this.onChanged, required this.minBet});
  final int value;
  final int minBet;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        for (final c in gameChips.where((c) => c >= minBet))
          GestureDetector(
            onTap: () {
              Sfx.play('tick');
              onChanged(c);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              margin: const EdgeInsets.only(right: 6),
              width: 62,
              transform: Matrix4.translationValues(0, value == c ? -6 : 0, 0),
              child: Stack(alignment: Alignment.center, children: [
                if (value == c)
                  Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: C.gold.withValues(alpha: .8), blurRadius: 16)])),
                art(_chipArt[c]!, size: 60),
                Text(compact(c), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF241A0C))),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Dark felt table with a soft spotlight, used behind every game.
class Felt extends StatelessWidget {
  const Felt({super.key, required this.color, required this.child, this.edge = const Color(0xFF070504)});
  final Color color;
  final Color edge;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(center: const Alignment(0, -.35), radius: 1.15, colors: [Color.lerp(color, Colors.white, .08)!, color, edge], stops: const [0, .55, 1]),
        ),
        child: CustomPaint(painter: _GrainPainter(), child: child),
      );
}

class _GrainPainter extends CustomPainter {
  static final _r = math.Random(3);
  static final _pts = List.generate(900, (_) => Offset(_r.nextDouble(), _r.nextDouble()));
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: .025);
    for (final o in _pts) {
      canvas.drawCircle(Offset(o.dx * size.width, o.dy * size.height), .8, p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class GameScaffold extends StatelessWidget {
  const GameScaffold({super.key, required this.title, required this.color, required this.child, this.help});
  final String title;
  final Color color;
  final Widget child;
  final String? help;
  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(title),
          actions: [
            if (help != null)
              IconButton(
                icon: const Icon(Icons.help_outline, color: Colors.white70),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(title: Text(title, style: serif(22)), content: Text(help!), actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: C.gold))),
                  ]),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(compact(c)))),
            ),
          ],
        ),
        body: Felt(color: color, child: SafeArea(child: child)),
      );
}

/// Big gold action button with a press-down 3D feel.
class PressButton extends StatefulWidget {
  const PressButton({super.key, required this.label, required this.onTap, this.busy = false, this.color = C.gold, this.height = 54});
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final Color color;
  final double height;
  @override
  State<PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<PressButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final off = widget.onTap == null || widget.busy;
    final base = off ? Colors.grey.shade700 : widget.color;
    final dark = Color.lerp(base, Colors.black, .45)!;
    return GestureDetector(
      onTapDown: off ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: off
          ? null
          : (_) {
              setState(() => _down = false);
              widget.onTap!();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: widget.height,
        margin: EdgeInsets.only(top: _down ? 5 : 0, bottom: _down ? 0 : 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.height / 2),
          gradient: LinearGradient(colors: [Color.lerp(base, Colors.white, .35)!, base, dark], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          boxShadow: [
            BoxShadow(color: dark, offset: Offset(0, _down ? 0 : 5)),
            BoxShadow(color: base.withValues(alpha: off ? 0 : .4), blurRadius: 18, offset: const Offset(0, 8)),
          ],
        ),
        alignment: Alignment.center,
        child: widget.busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 1, color: Color(0xFF1A1206))),
      ),
    );
  }
}

/// Win/lose pop-up with a burst of 3D coins on a win.
Future<void> resultPopup(BuildContext context, {required bool win, required int amount, String? note, String? image}) async {
  Sfx.play(win ? 'win' : 'lose');
  if (win) Future.delayed(const Duration(milliseconds: 250), () => Sfx.play('coin'));
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'result',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 520),
    pageBuilder: (_, __, ___) => const SizedBox(),
    transitionBuilder: (ctx, a, _, __) {
      final t = Curves.elasticOut.transform(a.value);
      return Stack(alignment: Alignment.center, children: [
        if (win) Positioned.fill(child: IgnorePointer(child: CoinShower(progress: a.value))),
        Transform.scale(
          scale: .4 + .6 * t,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: 280,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: win ? const [Color(0xFF4A3412), Color(0xFF15100A)] : const [Color(0xFF2A2026), Color(0xFF120D10)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: win ? C.gold : Colors.white24, width: 2),
                  boxShadow: win ? [BoxShadow(color: C.gold.withValues(alpha: .5), blurRadius: 34)] : null,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (image != null) art(image, size: 96) else art(win ? 'coins_pile' : 'coin', size: 96),
                  const SizedBox(height: 6),
                  Text(win ? 'You won!' : 'So close!', style: serif(26, color: win ? C.gold : Colors.white)),
                  const SizedBox(height: 6),
                  if (win) CountUp(amount, size: 24) else const Text('Luck changes fast — try again', style: TextStyle(color: C.mute)),
                  if (note != null) ...[const SizedBox(height: 6), Text(note, textAlign: TextAlign.center, style: const TextStyle(color: C.mute, fontSize: 12))],
                ]),
              ),
            ),
          ),
        ),
      ]);
    },
  );
}

/// Number that counts up to [value].
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, this.size = 20, this.prefix = '+'});
  final int value;
  final double size;
  final String prefix;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => CoinText('$prefix${grouped(v.round())}', size: size),
      );
}

/// Rendered gold coins raining down with spin (scaleX flip gives the 3D turn).
class CoinShower extends StatelessWidget {
  const CoinShower({super.key, required this.progress, this.count = 26});
  final double progress;
  final int count;
  static final _r = math.Random(11);
  static final _seeds = List.generate(40, (_) => [_r.nextDouble(), _r.nextDouble(), _r.nextDouble(), _r.nextDouble()]);
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return Stack(children: [
        for (var i = 0; i < count; i++)
          () {
            final s = _seeds[i];
            final t = ((progress * 1.4) - s[1] * .4).clamp(0.0, 1.0);
            final x = s[0] * box.maxWidth;
            final y = -60 + t * (box.maxHeight * (.55 + s[2] * .5));
            final size = 26 + s[3] * 26;
            return Positioned(
              left: x,
              top: y,
              child: Opacity(
                opacity: (1 - (t - .8).clamp(0.0, 1.0) * 5).clamp(0.0, 1.0),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .002)
                    ..rotateY(t * 14 + s[3] * 6)
                    ..rotateZ(s[2]),
                  child: art('coin', size: size),
                ),
              ),
            );
          }(),
      ]);
    });
  }
}

/// Gentle idle float so rendered objects never look like flat stickers.
class Floaty extends StatefulWidget {
  const Floaty({super.key, required this.child, this.amp = 4, this.period = 2200, this.phase = 0, this.tilt = .04});
  final Widget child;
  final double amp;
  final int period;
  final double phase;
  final double tilt;
  @override
  State<Floaty> createState() => _FloatyState();
}

class _FloatyState extends State<Floaty> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.period))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) {
          final a = (_c.value + widget.phase) * 2 * math.pi;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0015)
              ..translate(0.0, math.sin(a) * widget.amp)
              ..rotateY(math.sin(a) * widget.tilt * 3)
              ..rotateX(math.cos(a) * widget.tilt),
            child: child,
          );
        },
      );
}

/// Soft elliptical contact shadow under a floating object.
class GroundShadow extends StatelessWidget {
  const GroundShadow({super.key, required this.width, this.opacity = .45});
  final double width;
  final double opacity;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: width * .22,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.elliptical(width, width * .22)),
          gradient: RadialGradient(colors: [Colors.black.withValues(alpha: opacity), Colors.transparent]),
        ),
      );
}
