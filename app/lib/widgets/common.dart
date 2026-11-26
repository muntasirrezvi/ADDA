import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';

void toast(BuildContext context, String msg, {bool bad = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bad ? const Color(0xFF3C1520) : C.card,
      duration: const Duration(seconds: 3),
    ));
}

/// Runs an action, showing errors as a snack bar. Returns true on success.
Future<bool> attempt(BuildContext context, Future<void> Function() fn, {String? ok, String Function(Object)? err}) async {
  try {
    await fn();
    if (ok != null && context.mounted) toast(context, ok);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, err != null ? err(e) : errText(e), bad: true);
    return false;
  }
}

/// User avatar: uploaded photo, otherwise a preset illustrated avatar, otherwise initials.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.profile, this.size = 44, this.ring});
  final Map<String, dynamic>? profile;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final url = p?['avatar_url'] as String?;
    final preset = (p?['avatar_preset'] as num?)?.toInt() ?? 0;
    final name = (p?['username'] as String?) ?? '?';
    final src = (url != null && url.isNotEmpty) ? url : 'https://api.dicebear.com/9.x/notionists/png?size=128&backgroundColor=d8b77a,c9506c,2a9d7f,3a2e17&seed=adda$preset${preset == 0 ? name : ''}';
    final fallback = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: C.goldGrad, shape: BoxShape.circle),
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.w700, color: const Color(0xFF1A1206))),
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring != null ? 2 : 0),
      decoration: BoxDecoration(shape: BoxShape.circle, border: ring != null ? Border.all(color: ring!, width: 2) : null),
      child: ClipOval(
        child: p == null
            ? Container(color: C.card, child: Icon(Icons.person, color: C.mute, size: size * .5))
            : CachedNetworkImage(imageUrl: src, fit: BoxFit.cover, placeholder: (_, __) => fallback, errorWidget: (_, __, ___) => fallback),
      ),
    );
  }
}

/// Built-in cover templates (used when a room has no uploaded image and the template has no image).
const coverTemplates = <String, (List<Color>, IconData)>{
  'lantern': ([Color(0xFF6B3A12), Color(0xFF1A0E06)], Icons.light),
  'dunes': ([Color(0xFFC98A4B), Color(0xFF3A1E0C)], Icons.landscape),
  'lotus': ([Color(0xFFC9506C), Color(0xFF3D0C1C)], Icons.local_florist),
  'neon': ([Color(0xFF6A3DE8), Color(0xFF120A2E)], Icons.nightlife),
  'mic': ([Color(0xFFD8B77A), Color(0xFF3A2A12)], Icons.mic),
  'stars': ([Color(0xFF1F3B73), Color(0xFF070B1A)], Icons.auto_awesome),
  'waves': ([Color(0xFF2A9D7F), Color(0xFF07261E)], Icons.waves),
  'garden': ([Color(0xFF4F8A3B), Color(0xFF0F2108)], Icons.park),
};

class CoverArt extends StatelessWidget {
  const CoverArt({super.key, this.imageUrl, this.template = 'lantern', this.radius = 16, this.iconSize = 40});
  final String? imageUrl;
  final String template;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final t = coverTemplates[template] ?? coverTemplates['lantern']!;
    final art = Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: t.$1, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      alignment: Alignment.center,
      child: Icon(t.$2, size: iconSize, color: Colors.white.withValues(alpha: .35)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: (imageUrl == null || imageUrl!.isEmpty)
          ? art
          : CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover, placeholder: (_, __) => art, errorWidget: (_, __, ___) => art),
    );
  }
}

class GoldButton extends StatelessWidget {
  const GoldButton({super.key, required this.label, this.onTap, this.busy = false, this.icon, this.expand = true});
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(gradient: C.goldGrad, borderRadius: BorderRadius.circular(14)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Container(
              height: 50,
              width: expand ? double.infinity : null,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF1A1206)))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Icon(icon, color: const Color(0xFF1A1206), size: 20), const SizedBox(width: 8)],
                      Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF1A1206), fontWeight: FontWeight.w700, fontSize: 15))),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

class CoinText extends StatelessWidget {
  const CoinText(this.text, {super.key, this.size = 14, this.diamond = false});
  final String text;
  final double size;
  final bool diamond;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(diamond ? Icons.diamond : Icons.monetization_on, size: size + 2, color: diamond ? const Color(0xFF8FD3FF) : C.gold),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700)),
      ]);
}

class LevelBadge extends StatelessWidget {
  const LevelBadge(this.level, {super.key});
  final int level;
  @override
  Widget build(BuildContext context) {
    final colors = level >= 50
        ? const [Color(0xFFF0D9A6), Color(0xFFB8924F)]
        : level >= 20
            ? const [Color(0xFFC9506C), Color(0xFF6E1F35)]
            : level >= 10
                ? const [Color(0xFF6A3DE8), Color(0xFF2E1A6E)]
                : const [Color(0xFF2A9D7F), Color(0xFF145244)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(20)),
      child: Text('Lv $level', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: level >= 50 ? const Color(0xFF1A1206) : Colors.white)),
    );
  }
}

class Section extends StatelessWidget {
  const Section(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
        child: Row(children: [
          Expanded(child: Text(title, style: serif(19))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!, style: const TextStyle(color: C.gold))),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: C.mute),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.mute)),
          ]),
        ),
      );
}

Future<String?> askText(BuildContext context, String title, {String hint = '', bool number = false, bool obscure = false, String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: serif(20)),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: obscure,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: C.mute))),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK', style: TextStyle(color: C.gold))),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body, {String yes = 'Yes', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: serif(20)),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: C.mute))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes, style: TextStyle(color: danger ? C.ruby : C.gold))),
      ],
    ),
  );
  return r ?? false;
}

/// Gold "HOST" pill shown next to the room owner's name inside their room.
class HostTag extends StatelessWidget {
  const HostTag({super.key, this.small = false});
  final bool small;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: small ? 1 : 2),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFE7A0), Color(0xFFE0A93A), Color(0xFFB37514)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFF3C8), width: .8),
          boxShadow: const [BoxShadow(color: Color(0x66E0A93A), blurRadius: 6)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/games/crown.webp', width: small ? 10 : 13, height: small ? 10 : 13),
          const SizedBox(width: 2),
          Text('HOST', style: TextStyle(fontSize: small ? 8.5 : 10, fontWeight: FontWeight.w900, letterSpacing: .6, color: const Color(0xFF3A2406))),
        ]),
      );
}
