import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api.dart';
import '../services/background.dart';
import '../services/calls.dart';
import '../services/presence.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'avatar_studio.dart';
import 'games_tab.dart';
import 'inbox_screen.dart';
import 'leaderboard_screen.dart';
import 'reel_menu.dart';
import 'reels_screen.dart';
import 'rewards.dart';
import 'wallet_screen.dart';
import 'wallet_tools.dart';
import 'history_screen.dart';

/// Your own profile tab.
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: App.i.me,
      builder: (context, me, _) => me == null ? const SizedBox() : ProfileScreen(userId: me['id'] as String, isTab: true),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.userId, this.isTab = false});
  final String userId;
  final bool isTab;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _p;
  int _followers = 0, _following = 0;
  bool _iFollow = false;
  bool _blocked = false;
  List<Map<String, dynamic>> _reels = [];

  bool get _mine => widget.userId == myId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final id = widget.userId;
      _p = await Profiles.fetch(id, fresh: true);
      final a = await db.from('user_follows').select('follower_id').eq('followee_id', id).count();
      final b = await db.from('user_follows').select('followee_id').eq('follower_id', id).count();
      _followers = a.count;
      _following = b.count;
      if (!_mine) {
        _iFollow = await db.from('user_follows').select('follower_id').eq('follower_id', myId!).eq('followee_id', id).maybeSingle() != null;
        _blocked = await db.from('blocks').select('blocked_id').eq('blocker_id', myId!).eq('blocked_id', id).maybeSingle() != null;
      }
      final r = await db
          .from('reels')
          .select('*, user:profiles!reels_user_id_fkey(id, username, avatar_url, avatar_preset), track:music_tracks(id, title, artist, audio_url)')
          .eq('user_id', id)
          .eq('status', 'active')
          .order('pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(60);
      _reels = List<Map<String, dynamic>>.from(r);
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleFollow() async {
    await attempt(context, () async {
      if (_iFollow) {
        await db.from('user_follows').delete().eq('follower_id', myId!).eq('followee_id', widget.userId);
      } else {
        await db.from('user_follows').insert({'follower_id': myId, 'followee_id': widget.userId});
      }
      setState(() {
        _iFollow = !_iFollow;
        _followers += _iFollow ? 1 : -1;
      });
    });
  }

  void _more() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy, color: C.gold),
            title: Text('Copy ID ${_p?['public_id'] ?? ''}'),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: '${_p?['public_id']}'));
              toast(context, 'ID copied');
            },
          ),
          ListTile(
            leading: Icon(_blocked ? Icons.lock_open : Icons.block, color: C.ruby),
            title: Text(_blocked ? 'Unblock' : 'Block'),
            onTap: () async {
              Navigator.pop(ctx);
              await attempt(context, () async {
                if (_blocked) {
                  await db.from('blocks').delete().eq('blocker_id', myId!).eq('blocked_id', widget.userId);
                } else {
                  await db.from('blocks').insert({'blocker_id': myId, 'blocked_id': widget.userId});
                }
                setState(() => _blocked = !_blocked);
              }, ok: _blocked ? 'Unblocked' : 'Blocked. They can no longer message, call or gift you.');
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag, color: C.ruby),
            title: const Text('Report'),
            onTap: () async {
              Navigator.pop(ctx);
              final reason = await showDialog<String>(
                context: context,
                builder: (d) => SimpleDialog(title: Text('Why are you reporting?', style: serif(19)), children: [
                  for (final r in const ['Harassment', 'Hate speech', 'Sexual content', 'Scam or fraud', 'Underage user', 'Other'])
                    SimpleDialogOption(onPressed: () => Navigator.pop(d, r), child: Text(r)),
                ]),
              );
              if (reason == null || !mounted) return;
              await attempt(context, () => db.from('reports').insert({'reporter_id': myId, 'target_user': widget.userId, 'reason': reason}), ok: 'Thanks. Our team will review this.');
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return Scaffold(appBar: widget.isTab ? null : AppBar(), body: const Center(child: CircularProgressIndicator(color: C.gold)));
    final cover = p['cover_url'] as String?;
    return Scaffold(
      body: RefreshIndicator(
        color: C.gold,
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            expandedHeight: 230,
            pinned: true,
            automaticallyImplyLeading: !widget.isTab,
            actions: [
              if (_mine) IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
              if (!_mine) IconButton(icon: const Icon(Icons.more_vert), onPressed: _more),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                if (cover != null && cover.isNotEmpty)
                  CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover)
                else
                  const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF4A2A12), Color(0xFF1A0910), C.bg], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, C.bg], stops: [.4, 1]))),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 8,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Avatar(profile: p, size: 84, ring: C.gold),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text('${p['username']}', overflow: TextOverflow.ellipsis, style: serif(24))),
                          if (p['verified'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, color: C.gold, size: 18)),
                        ]),
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          LevelBadge((p['wealth_level'] as num?)?.toInt() ?? 1),
                          if (p['vip_tier'] != null) _tag('${p['vip_tier']}'.toUpperCase(), C.gold),
                          if (p['role'] == 'host') _tag('HOST', C.ruby),
                          if (p['role'] == 'agent') _tag('COIN AGENT', C.emerald),
                          Text('ID ${p['public_id']}${p['country'] != null ? ' · ${p['country']}' : ''}', style: const TextStyle(color: C.mute, fontSize: 12)),
                        ]),
                        const SizedBox(height: 4),
                        PresenceText(widget.userId),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ('${p['bio'] ?? ''}'.isNotEmpty) Text('${p['bio']}', style: const TextStyle(height: 1.4)),
                const SizedBox(height: 14),
                Row(children: [
                  _stat(compact(_followers), 'Followers'),
                  _stat(compact(_following), 'Following'),
                  _stat(compact(p['charm_xp'] as num? ?? 0), 'Charm'),
                ]),
                const SizedBox(height: 14),
                if (_mine)
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
                        _load();
                      },
                      icon: const Icon(Icons.edit, color: C.gold, size: 18),
                      label: const Text('Edit profile', style: TextStyle(color: C.text)),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: GoldButton(label: 'Wallet', icon: Icons.account_balance_wallet, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())))),
                  ])
                else if (!_blocked)
                  Row(children: [
                    Expanded(child: GoldButton(label: _iFollow ? 'Following' : 'Follow', icon: _iFollow ? Icons.check : Icons.add, onTap: _toggleFollow)),
                    const SizedBox(width: 8),
                    _circle(Icons.chat_bubble, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(userId: widget.userId)))),
                    _circle(Icons.call, () => CallService.i.call(context, widget.userId, video: false)),
                    _circle(Icons.videocam, () => CallService.i.call(context, widget.userId, video: true)),
                  ])
                else
                  const Text('You blocked this person.', style: TextStyle(color: C.ruby)),
                if (_mine) ...[
                  const SizedBox(height: 14),
                  _MyMenu(onChanged: _load),
                ],
                const Section('Reels'),
              ]),
            ),
          ),
          if (_reels.isEmpty)
            const SliverToBoxAdapter(child: EmptyState('No reels yet', icon: Icons.videocam_off))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: .62, mainAxisSpacing: 4, crossAxisSpacing: 4),
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    return ReelTile(reel: _reels[i], onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => ReelsScreen(active: true, initial: _reels, startIndex: i)));
                      _load();
                    });
                  },
                  childCount: _reels.length,
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: .2), borderRadius: BorderRadius.circular(6), border: Border.all(color: c.withValues(alpha: .6))),
        child: Text(t, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: c)),
      );

  Widget _stat(String v, String l) => Expanded(
        child: Column(children: [Text(v, style: serif(20)), Text(l, style: const TextStyle(color: C.mute, fontSize: 12))]),
      );

  Widget _circle(IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(color: C.card, shape: const CircleBorder(side: BorderSide(color: C.line)), child: IconButton(onPressed: onTap, icon: Icon(icon, color: C.gold))),
      );
}

class _MyMenu extends StatelessWidget {
  const _MyMenu({required this.onChanged});
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final me = App.i.me.value ?? {};
    final agent = me['role'] == 'agent' || me['role'] == 'admin';
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => onChanged());
    Widget tile(IconData icon, Color color, String title, String sub, VoidCallback onTap) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 20)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub, style: const TextStyle(color: C.mute, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: C.mute),
          onTap: onTap,
        );
    Widget group(String title, List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text(title.toUpperCase(), style: const TextStyle(color: C.mute, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w700))),
          Container(
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
            child: Column(children: children),
          ),
        ]);
    Widget quick(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .16)), child: Icon(icon, color: color, size: 20)),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // wallet at a glance
      GestureDetector(
        onTap: () => go(const WalletScreen()),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF3A2A12), Color(0xFF15100A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: C.gold2.withValues(alpha: .5)),
          ),
          child: Column(children: [
            Row(children: [
              const Text('MY WALLET', style: TextStyle(color: C.mute, letterSpacing: 2, fontSize: 11)),
              const Spacer(),
              const Text('Open', style: TextStyle(color: C.gold, fontSize: 12)),
              const Icon(Icons.chevron_right, color: C.gold, size: 18),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(grouped(c), size: 20))),
              Expanded(child: ValueListenableBuilder<int>(valueListenable: App.i.diamonds, builder: (_, d, __) => CoinText(grouped(d), size: 20, diamond: true))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              quick(Icons.add_card, 'Recharge', C.gold, () => go(const WalletScreen())),
              quick(Icons.send, 'Send', const Color(0xFF3DDC84), () => go(const SendScreen())),
              quick(Icons.swap_vert, 'Exchange', const Color(0xFF7FB0FF), () => go(const ExchangeScreen())),
              quick(Icons.receipt_long, 'History', const Color(0xFFE0485A), () => go(const HistoryScreen())),
            ]),
          ]),
        ),
      ),
      group('Rewards & fun', [
        tile(Icons.card_giftcard, C.gold, 'Daily reward', 'Collect free coins every day — more each day for 7 days', () => showDailyRewards(context)),
        tile(Icons.emoji_events, const Color(0xFFFFB347), 'Leaderboard', 'Top gifters and most-loved people', () => go(const LeaderboardScreen())),
        tile(Icons.sports_esports, const Color(0xFF8A7BFF), 'Games', 'Play lucky games on your own, any time', () => go(GamesTab(openRooms: () => Navigator.pop(context)))),
      ]),
      if (agent)
        group(me['role'] == 'admin' ? 'Admin tools' : 'Agent tools', [
          tile(Icons.storefront, C.emerald, me['role'] == 'admin' ? 'Admin store' : 'My agent store',
              me['role'] == 'admin' ? 'Send any amount of coins or diamonds to anyone' : 'Send coins and diamonds from your store to users', () => go(const SendScreen(fromStore: true))),
        ]),
      group('Account', [
        tile(Icons.edit, const Color(0xFF7FB0FF), 'Edit profile', 'Name, photo, cover and bio', () => go(const EditProfileScreen())),
        tile(Icons.auto_awesome, const Color(0xFFE0485A), 'AI avatar', 'Turn a photo into a fancy cartoon you', () => go(const AvatarStudio())),
        if (me['verified'] != true) tile(Icons.verified_user, C.emerald, 'Verify my identity', 'Get the verified badge on your profile', () => go(const VerifyScreen())),
        tile(Icons.bookmark, const Color(0xFFFFB347), 'Saved reels', 'Reels you saved from the ⋯ menu', () => go(const SavedReelsScreen())),
        tile(Icons.receipt_long, C.mute, 'Coin & diamond history', 'Purchases, gifts, games and transfers', () => go(const HistoryScreen())),
        tile(Icons.settings, C.mute, 'Settings & privacy', 'Last seen, background voice, help, sign out', () => go(const SettingsScreen())),
      ]),
    ]);
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final Map<String, dynamic> _p = Map<String, dynamic>.from(App.i.me.value ?? {});
  late final _name = TextEditingController(text: '${_p['username'] ?? ''}');
  late final _bio = TextEditingController(text: '${_p['bio'] ?? ''}');
  bool _busy = false;

  Future<String?> _pick(String bucket, int maxWidth) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: maxWidth.toDouble(), imageQuality: 85);
    if (x == null) return null;
    final ext = x.name.split('.').last.toLowerCase();
    return App.i.upload(bucket, await x.readAsBytes(), ext == 'png' || ext == 'webp' ? ext : 'jpg');
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 3 || name.length > 20) return toast(context, 'Username must be 3 to 20 characters', bad: true);
    setState(() => _busy = true);
    final ok = await attempt(context, () async {
      await db.from('profiles').update({
        'username': name,
        'bio': _bio.text.trim(),
        'avatar_url': _p['avatar_url'],
        'avatar_preset': _p['avatar_preset'] ?? 0,
        'cover_url': _p['cover_url'],
      }).eq('id', myId!);
      await App.i.loadMe();
    }, ok: 'Profile saved');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GestureDetector(
          onTap: () => attempt(context, () async {
            final u = await _pick('covers', 1600);
            if (u != null) setState(() => _p['cover_url'] = u);
          }),
          child: AspectRatio(
            aspectRatio: 2.4,
            child: Container(
              decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                if (_p['cover_url'] != null) CachedNetworkImage(imageUrl: _p['cover_url'] as String, fit: BoxFit.cover),
                const Center(child: Chip(avatar: Icon(Icons.photo, size: 16, color: C.gold), label: Text('Change cover photo'))),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Avatar(profile: _p, size: 80, ring: C.gold),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              OutlinedButton.icon(
                onPressed: () => attempt(context, () async {
                  final u = await _pick('avatars', 600);
                  if (u != null) setState(() => _p['avatar_url'] = u);
                }),
                icon: const Icon(Icons.photo_camera, color: C.gold, size: 18),
                label: const Text('Upload photo', style: TextStyle(color: C.text)),
              ),
              if (_p['avatar_url'] != null)
                TextButton(onPressed: () => setState(() => _p['avatar_url'] = null), child: const Text('Use an avatar instead', style: TextStyle(color: C.mute))),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () async {
            final url = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const AvatarStudio()));
            if (url != null && mounted) setState(() => _p['avatar_url'] = url);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF8A3AE0), Color(0xFFE0485A), Color(0xFFFFB347)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Color(0x668A3AE0), blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: const Row(children: [
              Icon(Icons.auto_awesome, color: Colors.white, size: 30),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Create my AI avatar', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  Text('Turn your photo into a fancy cartoon you', style: TextStyle(fontSize: 12, color: Colors.white70)),
                ]),
              ),
              Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
        const Section('Or pick an avatar'),
        GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var i = 1; i <= 24; i++)
              GestureDetector(
                onTap: () => setState(() {
                  _p['avatar_url'] = null;
                  _p['avatar_preset'] = i;
                }),
                child: Avatar(profile: {'username': _p['username'], 'avatar_preset': i}, size: 48, ring: _p['avatar_url'] == null && _p['avatar_preset'] == i ? C.gold : null),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(controller: _name, maxLength: 20, decoration: const InputDecoration(labelText: 'Username')),
        TextField(controller: _bio, maxLength: 120, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio')),
        const SizedBox(height: 12),
        GoldButton(label: 'Save', busy: _busy, onTap: _save),
      ]),
    );
  }
}

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  XFile? _doc, _selfie;
  bool _busy = false;

  Future<void> _submit() async {
    if (_doc == null || _selfie == null) return toast(context, 'Add both photos', bad: true);
    setState(() => _busy = true);
    final ok = await attempt(context, () async {
      final d = await App.i.upload('verification', await _doc!.readAsBytes(), 'jpg', private: true);
      final s = await App.i.upload('verification', await _selfie!.readAsBytes(), 'jpg', private: true);
      await App.i.rpc('request_verification', {'p_id_doc': d, 'p_selfie': s});
    }, ok: 'Sent for review. We will notify you.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  Widget _box(String label, XFile? f, ImageSource src, void Function(XFile) set) => Expanded(
        child: GestureDetector(
          onTap: () async {
            final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 85, preferredCameraDevice: src == ImageSource.camera ? CameraDevice.front : CameraDevice.rear);
            if (x != null) setState(() => set(x));
          },
          child: AspectRatio(
            aspectRatio: .8,
            child: Container(
              decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: f == null ? C.line : C.emerald)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(f == null ? Icons.add_a_photo : Icons.check_circle, color: f == null ? C.gold : C.emerald, size: 36),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Verify identity')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Verified people get a badge on their profile. Your photos are private and only seen by the Adda team.', style: TextStyle(color: C.mute)),
          const SizedBox(height: 16),
          Row(children: [
            _box('National ID or passport', _doc, ImageSource.gallery, (x) => _doc = x),
            const SizedBox(width: 12),
            _box('Selfie holding your ID', _selfie, ImageSource.camera, (x) => _selfie = x),
          ]),
          const SizedBox(height: 20),
          GoldButton(label: 'Submit', busy: _busy, onTap: _submit),
        ]),
      );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _showLastSeen;
  bool _bgAlways = BackgroundAudio.alwaysAllowed;

  @override
  void initState() {
    super.initState();
    db.from('profile_private').select('hide_last_seen').eq('user_id', myId!).maybeSingle().then((r) {
      if (mounted) setState(() => _showLastSeen = r?['hide_last_seen'] != true);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final support = '${App.i.settings['support_contact'] ?? 'support@adda.app'}';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('PRIVACY', style: TextStyle(color: C.mute, fontSize: 12, letterSpacing: 1.5))),
        SwitchListTile(
          secondary: const Icon(Icons.visibility, color: C.gold),
          title: const Text('Show my last seen'),
          subtitle: const Text('Off: people see "Online" while you are here and just "Offline" otherwise, never the time.', style: TextStyle(color: C.mute, fontSize: 12)),
          value: _showLastSeen ?? true,
          activeColor: C.gold,
          onChanged: _showLastSeen == null
              ? null
              : (v) async {
                  setState(() => _showLastSeen = v);
                  await attempt(context, () => App.i.rpc('set_presence_privacy', {'p_hide': !v}));
                },
        ),
        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('VOICE ROOMS', style: TextStyle(color: C.mute, fontSize: 12, letterSpacing: 1.5))),
        SwitchListTile(
          secondary: const Icon(Icons.headset_mic, color: C.gold),
          title: const Text('Keep rooms on in the background'),
          subtitle: const Text('On: never ask, stay in the room when you switch apps (with Mute and Leave buttons in the notification). Off: ask once each time you open Adda.', style: TextStyle(color: C.mute, fontSize: 12)),
          value: _bgAlways,
          activeColor: C.gold,
          onChanged: (v) async {
            await BackgroundAudio.setAlways(v);
            setState(() => _bgAlways = v);
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.support_agent, color: C.gold),
          title: const Text('Help & support'),
          subtitle: Text(support, style: const TextStyle(color: C.mute)),
          onTap: () => launchUrl(Uri.parse(support.contains('@') ? 'mailto:$support' : support), mode: LaunchMode.externalApplication),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip, color: C.gold),
          title: const Text('Privacy policy'),
          onTap: () {
            final u = App.i.settings['privacy_url'];
            if (u is String && u.isNotEmpty) launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
          },
        ),
        ListTile(
          leading: const Icon(Icons.description, color: C.gold),
          title: const Text('Terms of service'),
          onTap: () {
            final u = App.i.settings['terms_url'];
            if (u is String && u.isNotEmpty) launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: C.gold),
          title: const Text('Sign out'),
          onTap: () async {
            await App.i.signOut();
            if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: C.ruby),
          title: const Text('Delete my account', style: TextStyle(color: C.ruby)),
          subtitle: const Text('Your profile, rooms and coins will be removed', style: TextStyle(color: C.mute)),
          onTap: () async {
            if (!await confirm(context, 'Delete account?', 'This cannot be undone. Your coins and diamonds will be lost.', yes: 'Delete', danger: true)) return;
            if (!context.mounted) return;
            final ok = await attempt(context, () => App.i.rpc('delete_my_account'));
            if (ok) {
              await App.i.signOut();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            }
          },
        ),
        const SizedBox(height: 20),
        const Center(child: Text('Adda 1.0.0 · auto-updates on', style: TextStyle(color: C.mute, fontSize: 12))),
      ]),
    );
  }
}
