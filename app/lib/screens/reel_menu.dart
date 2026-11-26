import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';
import 'reels_screen.dart';

/// What happened in the menu, so the feed can update itself.
enum ReelMenuResult { deleted, hidden, changed }

String reelLink(Map<String, dynamic> r) => 'https://adda.app/reel/${r['id']}';

/// The ⋯ menu on a reel, Instagram style: a row of quick actions on top, a list below.
/// Your own reels: edit, pin, hide likes, comments on/off, gifts on/off, delete.
/// Other people's reels: save, not interested, copy link, about the account, report.
Future<ReelMenuResult?> showReelMenu(BuildContext context, Map<String, dynamic> reel) async {
  final mine = reel['user_id'] == myId;
  var saved = false;
  if (!mine) {
    try {
      saved = await db.from('reel_saves').select('reel_id').eq('user_id', myId!).eq('reel_id', reel['id']).maybeSingle() != null;
    } catch (_) {}
  }
  if (!context.mounted) return null;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF1A1614),
    showDragHandle: true,
    builder: (ctx) {
      Widget round(IconData icon, String label, String id, {Color color = Colors.white}) => Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.pop(ctx, id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),
          );
      Widget item(IconData icon, String title, String id, {String? sub, Color color = Colors.white}) => ListTile(
            leading: Icon(icon, color: color),
            title: Text(title, style: TextStyle(color: color)),
            subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: C.mute, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, id),
          );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: mine
                  ? [
                      round(Icons.edit_outlined, 'Edit', 'edit'),
                      round(reel['pinned'] == true ? Icons.push_pin : Icons.push_pin_outlined, reel['pinned'] == true ? 'Unpin' : 'Pin', 'pin'),
                      round(Icons.link, 'Copy link', 'link'),
                    ]
                  : [
                      round(saved ? Icons.bookmark : Icons.bookmark_border, saved ? 'Saved' : 'Save', 'save'),
                      round(Icons.link, 'Copy link', 'link'),
                      round(Icons.flag_outlined, 'Report', 'report', color: C.ruby),
                    ]),
            ),
            const Divider(height: 18),
            if (mine) ...[
              item(reel['hide_likes'] == true ? Icons.favorite : Icons.heart_broken_outlined, reel['hide_likes'] == true ? 'Show like count' : 'Hide like count', 'likes',
                  sub: 'Only you will see the number of likes'),
              item(reel['comments_off'] == true ? Icons.comment : Icons.comments_disabled_outlined, reel['comments_off'] == true ? 'Turn on commenting' : 'Turn off commenting', 'comments'),
              item(Icons.monetization_on_outlined, reel['allow_donations'] == true ? 'Turn off gifts' : 'Turn on gifts', 'gifts', sub: 'Let viewers send you coins on this reel'),
              item(Icons.delete_outline, 'Delete', 'delete', color: C.ruby),
            ] else ...[
              item(Icons.visibility_off_outlined, 'Not interested', 'hide', sub: 'See fewer reels like this'),
              item(Icons.account_circle_outlined, 'About this account', 'profile'),
            ],
          ]),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return null;

  Future<ReelMenuResult?> update(Map<String, dynamic> patch, String ok) async {
    final done = await attempt(context, () async {
      await db.from('reels').update(patch).eq('id', reel['id']);
      reel.addAll(patch);
    }, ok: ok);
    return done ? ReelMenuResult.changed : null;
  }

  switch (action) {
    case 'edit':
      final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ReelEditScreen(reel: reel)));
      return changed == true ? ReelMenuResult.changed : null;
    case 'pin':
      return update({'pinned': reel['pinned'] != true}, reel['pinned'] == true ? 'Unpinned from your profile' : 'Pinned to your profile');
    case 'likes':
      return update({'hide_likes': reel['hide_likes'] != true}, reel['hide_likes'] == true ? 'Like count is visible' : 'Like count hidden');
    case 'comments':
      return update({'comments_off': reel['comments_off'] != true}, reel['comments_off'] == true ? 'Comments turned on' : 'Comments turned off');
    case 'gifts':
      return update({'allow_donations': reel['allow_donations'] != true}, reel['allow_donations'] == true ? 'Gifts turned off' : 'Gifts turned on');
    case 'delete':
      if (!await confirm(context, 'Delete reel?', 'It will be removed from your profile and everyone\'s feed. This cannot be undone.', yes: 'Delete', danger: true)) return null;
      if (!context.mounted) return null;
      final ok = await attempt(context, () async {
        await db.from('reels').delete().eq('id', reel['id']);
        final url = '${reel['video_url']}';
        final i = url.indexOf('/reels/');
        if (i > 0) {
          try {
            await db.storage.from('reels').remove([url.substring(i + 7)]);
          } catch (_) {}
        }
      }, ok: 'Reel deleted');
      return ok ? ReelMenuResult.deleted : null;
    case 'link':
      await Clipboard.setData(ClipboardData(text: reelLink(reel)));
      if (context.mounted) toast(context, 'Link copied');
      return null;
    case 'save':
      await attempt(context, () async {
        if (saved) {
          await db.from('reel_saves').delete().eq('user_id', myId!).eq('reel_id', reel['id']);
        } else {
          await db.from('reel_saves').insert({'user_id': myId, 'reel_id': reel['id']});
        }
      }, ok: saved ? 'Removed from saved' : 'Saved — find it in Me → Saved reels');
      return null;
    case 'hide':
      final ok = await attempt(context, () => db.from('reel_hidden').upsert({'user_id': myId, 'reel_id': reel['id']}), ok: "Got it. You'll see fewer reels like this.");
      return ok ? ReelMenuResult.hidden : null;
    case 'profile':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: reel['user_id'] as String)));
      return null;
    case 'report':
      final reason = await showDialog<String>(
        context: context,
        builder: (d) => SimpleDialog(title: Text('Why are you reporting this reel?', style: serif(18)), children: [
          for (final r in const ['Spam', 'Nudity or sexual content', 'Hate speech', 'Violence', 'Scam or fraud', 'False information', 'Copyright', 'Other'])
            SimpleDialogOption(onPressed: () => Navigator.pop(d, r), child: Text(r)),
        ]),
      );
      if (reason == null || !context.mounted) return null;
      await attempt(context, () => db.from('reports').insert({'reporter_id': myId, 'target_user': reel['user_id'], 'target_reel': reel['id'], 'reason': reason}), ok: 'Thanks for letting us know. Our team will review it.');
      return null;
  }
  return null;
}

/// Edit your reel: caption and settings.
class ReelEditScreen extends StatefulWidget {
  const ReelEditScreen({super.key, required this.reel});
  final Map<String, dynamic> reel;
  @override
  State<ReelEditScreen> createState() => _ReelEditScreenState();
}

class _ReelEditScreenState extends State<ReelEditScreen> {
  late final _caption = TextEditingController(text: '${widget.reel['caption'] ?? ''}');
  late bool _comments = widget.reel['comments_off'] != true;
  late bool _likes = widget.reel['hide_likes'] != true;
  late bool _gifts = widget.reel['allow_donations'] == true;
  late bool _pinned = widget.reel['pinned'] == true;
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final patch = {
      'caption': _caption.text.trim(),
      'comments_off': !_comments,
      'hide_likes': !_likes,
      'allow_donations': _gifts,
      'pinned': _pinned,
      'edited_at': DateTime.now().toUtc().toIso8601String(),
    };
    final ok = await attempt(context, () async {
      await db.from('reels').update(patch).eq('id', widget.reel['id']);
      widget.reel.addAll(patch);
    }, ok: 'Saved');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cover = widget.reel['cover_url'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit reel'), actions: [
        TextButton(onPressed: _busy ? null : _save, child: const Text('Done', style: TextStyle(color: C.gold, fontWeight: FontWeight.w800))),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 72,
            height: 116,
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(10)),
            clipBehavior: Clip.antiAlias,
            child: cover != null ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover) : const Icon(Icons.play_arrow, color: C.mute, size: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _caption,
              maxLength: 150,
              maxLines: 5,
              minLines: 3,
              decoration: const InputDecoration(hintText: 'Write a caption…', border: InputBorder.none),
            ),
          ),
        ]),
        const Divider(),
        SwitchListTile(value: _pinned, activeColor: C.gold, onChanged: (v) => setState(() => _pinned = v), title: const Text('Pin to my profile'), subtitle: const Text('Shows first on your profile (up to 3)', style: TextStyle(color: C.mute, fontSize: 12))),
        SwitchListTile(value: _comments, activeColor: C.gold, onChanged: (v) => setState(() => _comments = v), title: const Text('Allow comments')),
        SwitchListTile(value: _likes, activeColor: C.gold, onChanged: (v) => setState(() => _likes = v), title: const Text('Show like count'), subtitle: const Text('Off: only you see how many likes it has', style: TextStyle(color: C.mute, fontSize: 12))),
        SwitchListTile(value: _gifts, activeColor: C.gold, onChanged: (v) => setState(() => _gifts = v), title: const Text('Allow gifts'), subtitle: const Text('Viewers can send you coins on this reel', style: TextStyle(color: C.mute, fontSize: 12))),
        const SizedBox(height: 16),
        GoldButton(label: 'Save changes', icon: Icons.check, busy: _busy, onTap: _save),
      ]),
    );
  }
}

/// Reels you saved from the ⋯ menu.
class SavedReelsScreen extends StatefulWidget {
  const SavedReelsScreen({super.key});
  @override
  State<SavedReelsScreen> createState() => _SavedReelsScreenState();
}

class _SavedReelsScreenState extends State<SavedReelsScreen> {
  List<Map<String, dynamic>>? _reels;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await db.from('reel_saves').select('created_at, reel:reels($reelSelect)').eq('user_id', myId!).order('created_at', ascending: false).limit(120);
      final list = <Map<String, dynamic>>[
        for (final r in rows)
          if (r['reel'] != null && (r['reel'] as Map)['status'] == 'active') Map<String, dynamic>.from(r['reel'] as Map),
      ];
      if (mounted) setState(() => _reels = list);
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
      if (mounted) setState(() => _reels = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _reels;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved reels')),
      body: list == null
          ? const Center(child: CircularProgressIndicator(color: C.gold))
          : list.isEmpty
              ? const EmptyState('Nothing saved yet. Tap ⋯ on a reel and choose Save.', icon: Icons.bookmark_border)
              : RefreshIndicator(
                  color: C.gold,
                  onRefresh: _load,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: .62, mainAxisSpacing: 4, crossAxisSpacing: 4),
                    itemCount: list.length,
                    itemBuilder: (_, i) => ReelTile(reel: list[i], onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => ReelsScreen(active: true, initial: list, startIndex: i)));
                      _load();
                    }),
                  ),
                ),
    );
  }
}

/// A reel thumbnail for grids (profile, saved).
class ReelTile extends StatelessWidget {
  const ReelTile({super.key, required this.reel, required this.onTap});
  final Map<String, dynamic> reel;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            if (reel['cover_url'] != null) CachedNetworkImage(imageUrl: reel['cover_url'] as String, fit: BoxFit.cover) else const Icon(Icons.play_arrow, color: C.mute, size: 36),
            if (reel['pinned'] == true) const Positioned(right: 6, top: 6, child: Icon(Icons.push_pin, size: 16, shadows: [Shadow(blurRadius: 6)])),
            Positioned(left: 6, bottom: 4, child: Row(children: [const Icon(Icons.play_arrow, size: 14), Text(compact(reel['views'] as num? ?? 0), style: const TextStyle(fontSize: 11))])),
          ]),
        ),
      );
}
