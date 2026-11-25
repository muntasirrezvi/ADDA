import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// TikTok-style reel recorder.
/// With a track chosen, the video is recorded without the microphone and the track plays along;
/// viewers hear the track in sync (no server-side video processing needed).
class ReelCreateScreen extends StatefulWidget {
  const ReelCreateScreen({super.key});
  @override
  State<ReelCreateScreen> createState() => _ReelCreateScreenState();
}

class _ReelCreateScreenState extends State<ReelCreateScreen> {
  static const maxSeconds = 30;
  List<CameraDescription> _cams = [];
  CameraController? _cam;
  int _camIndex = 0;
  Map<String, dynamic>? _track;
  final _music = AudioPlayer();
  bool _recording = false;
  double _elapsed = 0;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final p = await [Permission.camera, Permission.microphone].request();
    if (p[Permission.camera] != PermissionStatus.granted) {
      setState(() => _error = 'Allow camera access to record reels');
      return;
    }
    try {
      _cams = await availableCameras();
      _camIndex = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      if (_camIndex < 0) _camIndex = 0;
      await _openCamera();
    } catch (e) {
      setState(() => _error = 'Camera unavailable: ${errText(e)}');
    }
  }

  Future<void> _openCamera() async {
    final old = _cam;
    _cam = null;
    if (mounted) setState(() {});
    await old?.dispose();
    if (_cams.isEmpty) return;
    final c = CameraController(_cams[_camIndex], ResolutionPreset.medium, enableAudio: _track == null);
    await c.initialize();
    _cam = c;
    if (mounted) setState(() {});
  }

  Future<void> _pickTrack() async {
    final t = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _TrackPicker(),
    );
    if (!mounted) return;
    if (t != null && t['id'] == '__none') {
      setState(() => _track = null);
      await _music.stop();
    } else if (t != null) {
      setState(() => _track = t);
      await _music.setUrl(t['audio_url'] as String);
    }
    await _openCamera(); // microphone on only when there is no track
  }

  Future<void> _start() async {
    final c = _cam;
    if (c == null || _recording) return;
    try {
      await c.startVideoRecording();
      if (_track != null) {
        await _music.seek(Duration.zero);
        _music.play();
      }
      setState(() {
        _recording = true;
        _elapsed = 0;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        setState(() => _elapsed += .1);
        if (_elapsed >= maxSeconds) _stop();
      });
    } catch (e) {
      toast(context, errText(e), bad: true);
    }
  }

  Future<void> _stop() async {
    final c = _cam;
    if (c == null || !_recording) return;
    _timer?.cancel();
    setState(() => _recording = false);
    await _music.pause();
    try {
      final file = await c.stopVideoRecording();
      if (_elapsed < 2) {
        if (mounted) toast(context, 'Hold a little longer (at least 2 seconds)');
        return;
      }
      if (!mounted) return;
      final posted = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _ReelPost(path: file.path, track: _track)));
      if (posted == true && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cam?.dispose();
    _music.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _cam;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (_error != null)
          Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
        else if (c == null || !c.value.isInitialized)
          const Center(child: CircularProgressIndicator(color: C.gold))
        else
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(width: c.value.previewSize?.height ?? 720, height: c.value.previewSize?.width ?? 1280, child: CameraPreview(c)),
            ),
          ),
        SafeArea(
          child: Column(children: [
            LinearProgressIndicator(value: _elapsed / maxSeconds, color: C.gold, backgroundColor: Colors.white12, minHeight: 4),
            Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
              const Spacer(),
              GestureDetector(
                onTap: _recording ? null : _pickTrack,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.music_note, size: 18, color: C.gold),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(_track == null ? 'Add music' : '${_track!['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _recording || _cams.length < 2
                    ? null
                    : () {
                        _camIndex = (_camIndex + 1) % _cams.length;
                        _openCamera();
                      },
                icon: const Icon(Icons.cameraswitch, color: Colors.white),
              ),
            ]),
            const Spacer(),
            Text(_recording ? '${_elapsed.toStringAsFixed(1)}s' : 'Tap to record · up to $maxSeconds s', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _recording ? _stop : _start,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 84,
                height: 84,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5)),
                padding: EdgeInsets.all(_recording ? 22 : 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(color: C.ruby, borderRadius: BorderRadius.circular(_recording ? 8 : 40)),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ]),
        ),
      ]),
    );
  }
}

class _TrackPicker extends StatefulWidget {
  const _TrackPicker();
  @override
  State<_TrackPicker> createState() => _TrackPickerState();
}

class _TrackPickerState extends State<_TrackPicker> {
  List<Map<String, dynamic>> _tracks = [];
  final _preview = AudioPlayer();
  String? _playing;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    db.from('music_tracks').select().eq('active', true).order('uses', ascending: false).limit(100).then((r) {
      if (mounted) {
        setState(() {
          _tracks = List<Map<String, dynamic>>.from(r);
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _toggle(Map<String, dynamic> t) async {
    if (_playing == t['id']) {
      await _preview.stop();
      setState(() => _playing = null);
      return;
    }
    setState(() => _playing = t['id'] as String);
    try {
      await _preview.setUrl(t['audio_url'] as String);
      _preview.play();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * .7,
      child: Column(children: [
        Text('Trending sounds', style: serif(20)),
        TextButton(onPressed: () => Navigator.pop(context, {'id': '__none'}), child: const Text('No music (use my voice)', style: TextStyle(color: C.mute))),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: C.gold))
              : _tracks.isEmpty
                  ? const EmptyState('No tracks yet', icon: Icons.music_off)
                  : ListView.builder(
                      itemCount: _tracks.length,
                      itemBuilder: (_, i) {
                        final t = _tracks[i];
                        final cover = t['cover_url'] as String?;
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: cover != null ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover) : Container(color: C.card, child: const Icon(Icons.music_note, color: C.gold)),
                            ),
                          ),
                          title: Text('${t['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${t['artist']} · ${compact(t['uses'] as num)} reels', style: const TextStyle(color: C.mute, fontSize: 12)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: Icon(_playing == t['id'] ? Icons.pause_circle : Icons.play_circle, color: C.gold), onPressed: () => _toggle(t)),
                            TextButton(onPressed: () => Navigator.pop(context, t), child: const Text('Use', style: TextStyle(color: C.gold, fontWeight: FontWeight.w700))),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

class _ReelPost extends StatefulWidget {
  const _ReelPost({required this.path, required this.track});
  final String path;
  final Map<String, dynamic>? track;
  @override
  State<_ReelPost> createState() => _ReelPostState();
}

class _ReelPostState extends State<_ReelPost> {
  late final VideoPlayerController _v = VideoPlayerController.file(File(widget.path));
  final _a = AudioPlayer();
  final _caption = TextEditingController();
  bool _donations = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _v.initialize();
    await _v.setLooping(true);
    if (widget.track != null) {
      await _v.setVolume(0);
      await _a.setUrl(widget.track!['audio_url'] as String);
      await _a.setLoopMode(LoopMode.one);
      _a.play();
    }
    _v.play();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _v.dispose();
    _a.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    final ok = await attempt(context, () async {
      final bytes = await File(widget.path).readAsBytes();
      if (bytes.length > 95 * 1024 * 1024) throw Exception('This video is too large');
      final ext = widget.path.toLowerCase().endsWith('.mov') ? 'mov' : 'mp4';
      final url = await App.i.upload('reels', bytes, ext);
      await db.from('reels').insert({
        'user_id': myId,
        'video_url': url,
        'caption': _caption.text.trim(),
        'track_id': widget.track?['id'],
        'allow_donations': _donations,
      });
    }, ok: 'Reel posted');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post reel')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 380,
              child: _v.value.isInitialized ? AspectRatio(aspectRatio: _v.value.aspectRatio, child: VideoPlayer(_v)) : const SizedBox(width: 220, child: Center(child: CircularProgressIndicator(color: C.gold))),
            ),
          ),
        ),
        if (widget.track != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.music_note, size: 16, color: C.gold),
              Text(' ${widget.track!['title']} · ${widget.track!['artist']}', style: const TextStyle(color: C.mute)),
            ]),
          ),
        const SizedBox(height: 16),
        TextField(controller: _caption, maxLength: 150, maxLines: 2, decoration: const InputDecoration(labelText: 'Caption')),
        SwitchListTile(
          value: _donations,
          onChanged: (v) => setState(() => _donations = v),
          contentPadding: EdgeInsets.zero,
          activeColor: C.gold,
          title: const Text('Allow coin gifts on this reel'),
          subtitle: const Text('You keep 80% of what fans send', style: TextStyle(color: C.mute, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        GoldButton(label: _busy ? 'Uploading…' : 'Post', icon: Icons.send, busy: _busy, onTap: _post),
      ]),
    );
  }
}
