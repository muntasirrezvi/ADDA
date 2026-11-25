import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';
import 'reel_create.dart';

const reelSelect = '*, user:profiles!reels_user_id_fkey(id, username, avatar_url, avatar_preset), track:music_tracks(id, title, artist, audio_url)';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, required this.active, this.initial, this.startIndex = 0});
  final bool active;
  final List<Map<String, dynamic>>? initial;
  final int startIndex;
  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  late final PageController _pc = PageController(initialPage: widget.startIndex);
  final List<Map<String, dynamic>> _reels = [];
  final Set<String> _liked = {};
  int _index = 0;
  bool _loading = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex;
    if (widget.initial != null) {
      _reels.addAll(widget.initial!);
      _done = true;
      _loadLikes(_reels);
    } else {
      _more();
    }
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    _loading = true;
    try {
      final rows = await db.from('reels').select(reelSelect).eq('status', 'active').order('created_at', ascending: false).range(_reels.length, _reels.length + 14);
      final list = List<Map<String, dynamic>>.from(rows);
      if (list.length < 15) _done = true;
      _reels.addAll(list);
      await _loadLikes(list);
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    _loading = false;
    if (mounted) setState(() {});
  }

  Future<void> _loadLikes(List<Map<String, dynamic>> list) async {
    if (list.isEmpty) return;
    final r = await db.from('reel_likes').select('reel_id').eq('user_id', myId!).inFilter('reel_id', list.map((e) => e['id']).toList());
    _liked.addAll(r.map((e) => e['reel_id'] as String));
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    _reels.clear();
    _done = false;
    await _more();
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (_reels.isEmpty)
          _loading
              ? const Center(child: CircularProgressIndicator(color: C.gold))
              : RefreshIndicator(onRefresh: _refresh, child: ListView(children: const [SizedBox(height: 200), EmptyState('No reels yet. Be the first!', icon: Icons.videocam)]))
        else
          RefreshIndicator(
            color: C.gold,
            onRefresh: _refresh,
            child: PageView.builder(
              controller: _pc,
              scrollDirection: Axis.vertical,
              itemCount: _reels.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                if (i >= _reels.length - 3) _more();
              },
              itemBuilder: (_, i) => ReelPlayer(
                key: ValueKey(_reels[i]['id']),
                reel: _reels[i],
                playing: widget.active && i == _index,
                liked: _liked.contains(_reels[i]['id']),
                onLiked: (v) => setState(() => v ? _liked.add(_reels[i]['id'] as String) : _liked.remove(_reels[i]['id'])),
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              if (widget.initial != null) const BackButton(color: Colors.white),
              Text('Reels', style: serif(24, color: Colors.white)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_box_outlined, color: Colors.white),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReelCreateScreen())),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class ReelPlayer extends StatefulWidget {
  const ReelPlayer({super.key, required this.reel, required this.playing, required this.liked, required this.onLiked});
  final Map<String, dynamic> reel;
  final bool playing;
  final bool liked;
  final void Function(bool) onLiked;
  @override
  State<ReelPlayer> createState() => _ReelPlayerState();
}

class _ReelPlayerState extends State<ReelPlayer> {
  VideoPlayerController? _v;
  AudioPlayer? _a;
  bool _ready = false;
  bool _paused = false;
  bool _counted = false;
  late int _likes = (widget.reel['likes'] as num?)?.toInt() ?? 0;
  late int _comments = (widget.reel['comments'] as num?)?.toInt() ?? 0;

  Map<String, dynamic>? get _track => widget.reel['track'] as Map<String, dynamic>?;

  @override
  void initState() {
    super.initState();
    if (widget.playing) _init();
  }

  Future<void> _init() async {
    if (_v != null) return;
    final v = VideoPlayerController.networkUrl(Uri.parse(widget.reel['video_url'] as String));
    _v = v;
    try {
      await v.initialize();
      await v.setLooping(true);
      final t = _track;
      if (t != null && t['audio_url'] != null) {
        await v.setVolume(0);
        final a = AudioPlayer();
        _a = a;
        await a.setUrl(t['audio_url'] as String);
        await a.setLoopMode(LoopMode.one);
      }
      if (!mounted) return;
      setState(() => _ready = true);
      _sync();
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _sync() {
    final v = _v;
    if (v == null || !_ready) return;
    if (widget.playing && !_paused) {
      v.play();
      _a?.play();
      if (!_counted) {
        _counted = true;
        App.i.rpc('view_reel', {'p_reel': widget.reel['id']}).catchError((_) => null);
      }
    } else {
      v.pause();
      _a?.pause();
    }
  }

  @override
  void didUpdateWidget(covariant ReelPlayer old) {
    super.didUpdateWidget(old);
    if (widget.playing && _v == null) _init();
    if (old.playing != widget.playing) {
      if (widget.playing) {
        _v?.seekTo(Duration.zero);
        _a?.seek(Duration.zero);
      }
      _sync();
    }
  }

  @override
  void dispose() {
    _v?.dispose();
    _a?.dispose();
    super.dispose();
  }

  Future<void> _like() async {
    final was = widget.liked;
    widget.onLiked(!was);
    setState(() => _likes += was ? -1 : 1);
    try {
      await App.i.rpc('toggle_reel_like', {'p_reel': widget.reel['id']});
    } catch (e) {
      widget.onLiked(was);
      setState(() => _likes += was ? 1 : -1);
    }
  }

  Future<void> _donate() async {
    final user = widget.reel['user'] as Map?;
    if (user?['id'] == myId) return toast(context, 'You cannot donate to your own reel');
    final amount = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Support ${user?['username'] ?? 'this creator'}', style: serif(20)),
            const SizedBox(height: 4),
            ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => Text('You have ${grouped(c)} coins', style: const TextStyle(color: C.mute))),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              for (final v in const [10000, 50000, 100000, 500000, 1000000, 5000000])
                ActionChip(avatar: const Icon(Icons.monetization_on, color: C.gold, size: 18), label: Text(compact(v)), onPressed: () => Navigator.pop(ctx, v)),
            ]),
          ]),
        ),
      ),
    );
    if (amount == null || !mounted) return;
    await attempt(context, () async {
      final r = await App.i.rpc('donate_reel', {'p_reel': widget.reel['id'], 'p_coins': amount});
      App.i.coins.value = ((r as Map)['coins'] as num).toInt();
    }, ok: 'Thank you! ${compact(amount)} coins sent');
  }

  void _openComments() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Comments(reel: widget.reel, onAdded: () => setState(() => _comments++)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reel;
    final user = Map<String, dynamic>.from(r['user'] as Map? ?? {});
    final v = _v;
    return GestureDetector(
      onTap: () {
        setState(() => _paused = !_paused);
        _sync();
      },
      onDoubleTap: widget.liked ? null : _like,
      child: Stack(fit: StackFit.expand, children: [
        Container(color: Colors.black),
        if (_ready && v != null)
          FittedBox(fit: BoxFit.cover, child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)))
        else
          const Center(child: CircularProgressIndicator(color: C.gold)),
        if (_paused) const Center(child: Icon(Icons.play_arrow, size: 80, color: Colors.white70)),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black38, Colors.transparent, Colors.transparent, Colors.black87], stops: [0, .2, .6, 1]))),
        Positioned(
          right: 8,
          bottom: 110,
          child: Column(children: [
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: user['id'] as String))),
              child: Avatar(profile: user, size: 46, ring: Colors.white),
            ),
            const SizedBox(height: 18),
            _side(widget.liked ? Icons.favorite : Icons.favorite_border, compact(_likes), _like, color: widget.liked ? C.ruby : Colors.white),
            _side(Icons.mode_comment_outlined, compact(_comments), _openComments),
            if (r['allow_donations'] == true) _side(Icons.monetization_on, 'Gift', _donate, color: C.gold),
            _side(Icons.share, 'Share', () {
              Clipboard.setData(ClipboardData(text: 'Watch this on Adda: reel ${r['id']}'));
              toast(context, 'Link copied');
            }),
          ]),
        ),
        Positioned(
          left: 14,
          right: 80,
          bottom: 24,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('@${user['username'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if ('${r['caption'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${r['caption']}', maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            if (_track != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.music_note, size: 15, color: C.gold),
                const SizedBox(width: 4),
                Flexible(child: Text('${_track!['title']} · ${_track!['artist']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _side(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: GestureDetector(
          onTap: onTap,
          child: Column(children: [
            Icon(icon, size: 32, color: color, shadows: const [Shadow(blurRadius: 8)]),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 6)])),
          ]),
        ),
      );
}

class _Comments extends StatefulWidget {
  const _Comments({required this.reel, required this.onAdded});
  final Map<String, dynamic> reel;
  final VoidCallback onAdded;
  @override
  State<_Comments> createState() => _CommentsState();
}

class _CommentsState extends State<_Comments> {
  List<Map<String, dynamic>> _rows = [];
  final _c = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await db.from('reel_comments').select().eq('reel_id', widget.reel['id']).order('id', ascending: false).limit(100);
    _rows = List<Map<String, dynamic>>.from(r);
    await Profiles.load(_rows.map((e) => e['user_id'] as String?));
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    _c.clear();
    await attempt(context, () async {
      final row = await db.from('reel_comments').insert({'reel_id': widget.reel['id'], 'user_id': myId, 'body': t}).select().single();
      setState(() => _rows.insert(0, row));
      widget.onAdded();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .6,
        child: Column(children: [
          Text('Comments', style: serif(19)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: C.gold))
                : _rows.isEmpty
                    ? const EmptyState('Be the first to comment', icon: Icons.mode_comment_outlined)
                    : ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (_, i) {
                          final m = _rows[i];
                          final p = Profiles.get(m['user_id'] as String?);
                          return ListTile(
                            leading: Avatar(profile: p, size: 36),
                            title: Text('${p?['username'] ?? ''}', style: const TextStyle(fontSize: 13, color: C.mute)),
                            subtitle: Text('${m['body']}', style: const TextStyle(color: C.text)),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                controller: _c,
                maxLength: 200,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(counterText: '', hintText: 'Add a comment', suffixIcon: IconButton(icon: const Icon(Icons.send, color: C.gold), onPressed: _send)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
