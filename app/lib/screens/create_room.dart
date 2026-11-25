import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'room_screen.dart';

const topics = ['Talk', 'Music', 'Friends', 'Gaming', 'Love', 'Poetry', 'Quran', 'Study', 'Party', 'Business'];
const languages = ['English', 'বাংলা', 'العربية', 'हिन्दी', 'اردو', 'Bahasa', 'Tagalog', 'Türkçe', 'Other'];

Future<void> openCreateRoom(BuildContext context) async {
  // one open room per user: reopen it if it exists
  final existing = await db.from('rooms').select('id').eq('owner_id', myId!).eq('status', 'open').maybeSingle();
  if (!context.mounted) return;
  if (existing != null) {
    openRoom(context, (existing['id'] as num).toInt());
    return;
  }
  if (HomeData.feed.isEmpty) {
    try {
      await HomeData.load();
    } catch (_) {}
  }
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => const RoomEditor()));
}

/// Create a room, or edit one you own (pass [room]).
class RoomEditor extends StatefulWidget {
  const RoomEditor({super.key, this.room});
  final Map<String, dynamic>? room;
  @override
  State<RoomEditor> createState() => _RoomEditorState();
}

class _RoomEditorState extends State<RoomEditor> {
  late final _name = TextEditingController(text: widget.room?['name'] as String? ?? '${App.i.me.value?['username'] ?? 'My'}\'s room');
  late final _announce = TextEditingController(text: widget.room?['announcement'] as String? ?? '');
  final _pw = TextEditingController();
  late String _topic = widget.room?['topic'] as String? ?? 'Talk';
  late String _lang = widget.room?['language'] as String? ?? 'English';
  late int _seats = (widget.room?['seats'] as num?)?.toInt() ?? 8;
  late String _template = widget.room?['cover_template'] as String? ?? 'lantern';
  late String? _cover = widget.room?['cover_url'] as String?;
  late String _theme = widget.room?['theme'] as String? ?? 'majlis';
  bool _locked = false;
  bool _busy = false;
  bool _uploading = false;

  bool get _editing => widget.room != null;

  Future<void> _pickCover() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 85);
    if (x == null) return;
    setState(() => _uploading = true);
    await attempt(context, () async {
      final ext = x.name.split('.').last.toLowerCase();
      _cover = await App.i.upload('room-covers', await x.readAsBytes(), ext == 'png' || ext == 'webp' ? ext : 'jpg');
    });
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2 || name.length > 30) return toast(context, 'Room name must be 2 to 30 characters', bad: true);
    if (_locked && !_editing && !RegExp(r'^\d{4,8}$').hasMatch(_pw.text)) return toast(context, 'Password must be 4 to 8 digits', bad: true);
    final theme = HomeData.themes.where((t) => t['id'] == _theme).firstOrNull;
    if (theme != null && theme['owned'] != true) return toast(context, 'Buy the ${theme['name']} theme first', bad: true);
    setState(() => _busy = true);
    final ok = await attempt(context, () async {
      if (_editing) {
        await db.from('rooms').update({
          'name': name,
          'topic': _topic,
          'language': _lang,
          'announcement': _announce.text.trim(),
          'cover_url': _cover,
          'cover_template': _template,
          'theme': _theme,
        }).eq('id', widget.room!['id']);
      } else {
        final r = await App.i.rpc('create_room', {
          'p_name': name,
          'p_topic': _topic,
          'p_language': _lang,
          'p_seats': _seats,
          'p_cover_url': _cover,
          'p_cover_template': _template,
          'p_theme': _theme,
          'p_password': _locked ? _pw.text : null,
        });
        final id = ((r as Map)['id'] as num).toInt();
        if (mounted) {
          Navigator.pop(context);
          openRoom(context, id);
        }
      }
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && _editing) Navigator.pop(context, true);
  }

  Future<void> _buyTheme(Map<String, dynamic> t) async {
    final yes = await confirm(context, 'Buy ${t['name']}?', 'This theme costs ${grouped(t['price'] as num)} coins. You keep it forever for all your rooms.', yes: 'Buy');
    if (!yes || !mounted) return;
    await attempt(context, () async {
      await App.i.rpc('buy_theme', {'p_theme': t['id']});
      await HomeData.load();
      await App.i.refreshWallet();
      setState(() => _theme = t['id'] as String);
    }, ok: 'Theme unlocked');
  }

  @override
  Widget build(BuildContext context) {
    final templates = HomeData.templates.where((t) => (t['price'] as num? ?? 0) == 0).toList();
    final themes = HomeData.themes;
    final previewImg = _cover ?? HomeData.templateImage(_template);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit room' : 'New voice room')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            CoverArt(imageUrl: previewImg, template: _template, radius: 20, iconSize: 60),
            Positioned(
              right: 10,
              bottom: 10,
              child: Row(children: [
                if (_cover != null)
                  _pill('Use template', Icons.close, () => setState(() => _cover = null)),
                const SizedBox(width: 8),
                _pill(_uploading ? 'Uploading…' : (_cover == null ? 'Upload cover' : 'Change photo'), Icons.photo_camera, _uploading ? null : _pickCover),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        const Text('This image shows on the homepage. Upload your own or pick a template.', style: TextStyle(color: C.mute, fontSize: 12)),
        const Section('Cover template'),
        SizedBox(
          height: 82,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final t in (templates.isEmpty ? coverTemplates.keys.map((k) => <String, dynamic>{'id': k, 'name': k, 'image_url': null}) : templates))
              GestureDetector(
                onTap: () => setState(() {
                  _template = t['id'] as String;
                  _cover = null;
                }),
                child: Container(
                  width: 108,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: _template == t['id'] && _cover == null ? C.gold : Colors.transparent, width: 2)),
                  child: Stack(fit: StackFit.expand, children: [
                    CoverArt(imageUrl: t['image_url'] as String?, template: t['id'] as String, radius: 11, iconSize: 26),
                    Positioned(left: 6, bottom: 4, child: Text('${t['name']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 4)]))),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        TextField(controller: _name, maxLength: 30, decoration: const InputDecoration(labelText: 'Room name')),
        if (_editing) TextField(controller: _announce, maxLength: 120, maxLines: 2, decoration: const InputDecoration(labelText: 'Announcement')),
        const Section('Topic'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in topics) ChoiceChip(label: Text(t), selected: _topic == t, onSelected: (_) => setState(() => _topic = t)),
        ]),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: languages.contains(_lang) ? _lang : 'Other',
          decoration: const InputDecoration(labelText: 'Language'),
          items: [for (final l in languages) DropdownMenuItem(value: l, child: Text(l))],
          onChanged: (v) => setState(() => _lang = v ?? _lang),
        ),
        if (!_editing) ...[
          const Section('Seats'),
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 8, label: Text('8')), ButtonSegment(value: 12, label: Text('12')), ButtonSegment(value: 16, label: Text('16'))],
            selected: {_seats},
            onSelectionChanged: (s) => setState(() => _seats = s.first),
          ),
        ],
        const Section('Room theme'),
        SizedBox(
          height: 96,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final t in themes)
              GestureDetector(
                onTap: () => t['owned'] == true ? setState(() => _theme = t['id'] as String) : _buyTheme(t),
                child: Container(
                  width: 84,
                  margin: const EdgeInsets.only(right: 8),
                  child: Column(children: [
                    Container(
                      height: 64,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _theme == t['id'] ? C.gold : C.line, width: 2)),
                      child: Stack(fit: StackFit.expand, children: [
                        ClipRRect(borderRadius: BorderRadius.circular(10), child: RoomBackground(themeId: t['id'] as String, image: t['image_url'] as String?)),
                        if (t['owned'] != true) const Center(child: Icon(Icons.lock, size: 18, color: C.gold)),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(t['owned'] == true ? '${t['name']}' : compact(t['price'] as num), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: t['owned'] == true ? C.text : C.gold)),
                  ]),
                ),
              ),
          ]),
        ),
        if (!_editing) ...[
          SwitchListTile(
            value: _locked,
            onChanged: (v) => setState(() => _locked = v),
            contentPadding: EdgeInsets.zero,
            activeColor: C.gold,
            title: const Text('Private room (password)'),
          ),
          if (_locked) TextField(controller: _pw, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: '4 to 8 digit password')),
        ],
        const SizedBox(height: 16),
        GoldButton(label: _editing ? 'Save changes' : 'Go live', icon: _editing ? Icons.check : Icons.mic, busy: _busy, onTap: _uploading ? null : _save),
      ]),
    );
  }

  Widget _pill(String text, IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: .65), borderRadius: BorderRadius.circular(20), border: Border.all(color: C.gold.withValues(alpha: .5))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: C.gold), const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 12))]),
        ),
      );
}
