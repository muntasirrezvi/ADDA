import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _styles = [
  ('3d', '3D Cartoon', Icons.face_retouching_natural, [Color(0xFFFF8A5B), Color(0xFFE0485A)]),
  ('anime', 'Anime', Icons.auto_awesome, [Color(0xFF8A7BFF), Color(0xFF4A3AE0)]),
  ('comic', 'Comic Hero', Icons.bolt, [Color(0xFFFFC94A), Color(0xFFE07A1A)]),
  ('royal', 'Royal', Icons.workspace_premium, [Color(0xFFE9C46A), Color(0xFF7A4A10)]),
];

/// Upload a photo and get a fancy cartoon avatar of yourself. Returns the chosen image URL
/// when the person decides to use it as their profile picture.
class AvatarStudio extends StatefulWidget {
  const AvatarStudio({super.key});
  @override
  State<AvatarStudio> createState() => _AvatarStudioState();
}

class _AvatarStudioState extends State<AvatarStudio> with SingleTickerProviderStateMixin {
  Uint8List? _photo;
  String _style = '3d';
  String? _result;
  bool _busy = false;
  Map<String, dynamic>? _quota;
  List<Map<String, dynamic>> _mine = [];
  late final AnimationController _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final q = Map<String, dynamic>.from(await App.i.rpc('ai_avatar_quota') as Map);
      final m = await db.from('ai_avatars').select().eq('user_id', myId!).order('id', ascending: false).limit(24);
      if (mounted) setState(() {
        _quota = q;
        _mine = List<Map<String, dynamic>>.from(m);
      });
    } catch (_) {}
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 512, maxHeight: 512, imageQuality: 88, preferredCameraDevice: CameraDevice.front);
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() {
      _photo = b;
      _result = null;
    });
  }

  Future<void> _make() async {
    if (_photo == null) return toast(context, 'Add a clear photo of your face first');
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await App.i.fn('make-avatar', {'image': base64Encode(_photo!), 'style': _style}) as Map);
      if (r['error'] != null) throw Exception(r['error']);
      if (mounted) setState(() => _result = r['url'] as String);
      await _load();
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _use(String url) async {
    final ok = await attempt(context, () async {
      await db.from('profiles').update({'avatar_url': url}).eq('id', myId!);
      await App.i.loadMe();
    }, ok: 'Profile picture updated');
    if (ok && mounted) Navigator.pop(context, url);
  }

  Future<void> _useOwnPhoto() async {
    if (_photo == null) return;
    final ok = await attempt(context, () async {
      final url = await App.i.upload('avatars', _photo!, 'jpg');
      await db.from('profiles').update({'avatar_url': url}).eq('id', myId!);
      await App.i.loadMe();
    }, ok: 'Using your photo');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final q = _quota;
    final left = q == null ? null : ((q['limit'] as num) - (q['used'] as num)).clamp(0, 99).toInt();
    return Scaffold(
      appBar: AppBar(title: const Text('AI avatar studio')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Turn your photo into a fancy cartoon avatar that still looks like you. Use a clear, front-facing photo with good light.', style: TextStyle(color: C.mute)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _frame(child: _photo == null ? _placeholder() : Image.memory(_photo!, fit: BoxFit.cover), label: 'Your photo')),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, color: C.gold)),
          Expanded(
            child: _frame(
              label: 'Your avatar',
              child: _busy
                  ? _painting()
                  : _result == null
                      ? Center(child: Icon(_styles.firstWhere((s) => s.$1 == _style).$3, size: 46, color: Colors.white24))
                      : CachedNetworkImage(imageUrl: _result!, fit: BoxFit.cover),
              glow: _result != null,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library, color: C.gold, size: 18), label: const Text('Gallery'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera, color: C.gold, size: 18), label: const Text('Selfie'))),
        ]),
        const Section('Style'),
        SizedBox(
          height: 92,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final s in _styles)
              GestureDetector(
                onTap: _busy ? null : () => setState(() => _style = s.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 96,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: s.$4, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _style == s.$1 ? Colors.white : Colors.transparent, width: 2.5),
                    boxShadow: _style == s.$1 ? [BoxShadow(color: s.$4.first.withValues(alpha: .6), blurRadius: 14)] : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(s.$3, color: Colors.white, size: 30),
                    const SizedBox(height: 6),
                    Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        if (q != null && q['enabled'] != true)
          const Text('The avatar studio is switched off right now.', style: TextStyle(color: C.mute))
        else ...[
          GoldButton(label: _result == null ? 'Create my avatar' : 'Make another', icon: Icons.auto_awesome, busy: _busy, onTap: _photo == null || left == 0 ? null : _make),
          if (left != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('$left left today', textAlign: TextAlign.center, style: const TextStyle(color: C.mute, fontSize: 12))),
        ],
        if (_result != null) ...[
          const SizedBox(height: 10),
          GoldButton(label: 'Use as my profile picture', icon: Icons.check_circle, onTap: () => _use(_result!)),
        ],
        if (_photo != null)
          TextButton(onPressed: _busy ? null : _useOwnPhoto, child: const Text('Use my real photo instead', style: TextStyle(color: C.mute))),
        if (_mine.isNotEmpty) ...[
          const Section('My avatars'),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final a in _mine)
                GestureDetector(
                  onTap: () => _use(a['image_url'] as String),
                  child: ClipRRect(borderRadius: BorderRadius.circular(14), child: CachedNetworkImage(imageUrl: a['image_url'] as String, fit: BoxFit.cover)),
                ),
            ],
          ),
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('Tap one to use it as your profile picture.', style: TextStyle(color: C.mute, fontSize: 12))),
        ],
      ]),
    );
  }

  Widget _frame({required Widget child, required String label, bool glow = false}) => Column(children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: glow ? C.gold : C.line, width: glow ? 2 : 1),
              boxShadow: glow ? [BoxShadow(color: C.gold.withValues(alpha: .4), blurRadius: 20)] : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: C.mute, fontSize: 12)),
      ]);

  Widget _placeholder() => const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.add_a_photo, color: C.gold, size: 36),
        SizedBox(height: 6),
        Text('Add a photo', style: TextStyle(fontSize: 12)),
      ]);

  Widget _painting() => AnimatedBuilder(
        animation: _shimmer,
        builder: (_, __) => Stack(fit: StackFit.expand, children: [
          if (_photo != null) Opacity(opacity: .35, child: Image.memory(_photo!, fit: BoxFit.cover)),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1 + 2 * _shimmer.value - .5, -1),
                end: Alignment(-1 + 2 * _shimmer.value + .5, 1),
                colors: [Colors.transparent, Colors.white.withValues(alpha: .35), Colors.transparent],
              ),
            ),
          ),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Transform.rotate(angle: _shimmer.value * 2 * math.pi, child: const Icon(Icons.auto_awesome, color: C.gold, size: 30)),
              const SizedBox(height: 6),
              const Text('Painting…', style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      );
}
