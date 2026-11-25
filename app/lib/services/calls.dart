import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'active_room.dart';
import 'api.dart';
import 'rtc.dart';

/// 1-to-1 voice and video calls. Incoming calls arrive through realtime while the app is open.
class CallService {
  CallService._();
  static final CallService i = CallService._();

  RealtimeChannel? _ch;
  GlobalKey<NavigatorState>? _nav;
  String? _activeCall;

  void start(GlobalKey<NavigatorState> nav) {
    _nav = nav;
    final me = myId;
    if (me == null || _ch != null) return;
    _ch = db
        .channel('calls:$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'callee_id', value: me),
          callback: (p) => _incoming(p.newRecord),
        )
        .subscribe();
  }

  void stop() {
    if (_ch != null) db.removeChannel(_ch!);
    _ch = null;
  }

  Future<void> _incoming(Map<String, dynamic> call) async {
    if (_activeCall != null) {
      // already on a call: decline the new one
      try {
        await App.i.rpc('update_call', {'p_call': call['id'], 'p_status': 'declined'});
      } catch (_) {}
      return;
    }
    await Profiles.load([call['caller_id'] as String?]);
    _nav?.currentState?.push(MaterialPageRoute(builder: (_) => CallScreen(call: call, outgoing: false)));
  }

  Future<void> call(BuildContext context, String userId, {required bool video}) async {
    if (_activeCall != null) return;
    await attempt(context, () async {
      final c = Map<String, dynamic>.from(await App.i.rpc('start_call', {'p_callee': userId, 'p_type': video ? 'video' : 'audio'}) as Map);
      await Profiles.load([userId]);
      if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(call: c, outgoing: true)));
    });
  }
}

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.call, required this.outgoing});
  final Map<String, dynamic> call;
  final bool outgoing;
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late String _status = widget.call['status'] as String? ?? 'ringing';
  RtcSession? _rtc;
  RealtimeChannel? _ch;
  Timer? _ringTimeout;
  Timer? _clock;
  int _secs = 0;
  bool _speaker = true;
  bool _cam = true;
  bool _closing = false;

  String get _id => widget.call['id'] as String;
  bool get _video => widget.call['type'] == 'video';
  String get _otherId => widget.outgoing ? widget.call['callee_id'] as String : widget.call['caller_id'] as String;

  @override
  void initState() {
    super.initState();
    CallService.i._activeCall = _id;
    _ch = db
        .channel('call:$_id')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: _id),
          callback: (p) => _onStatus(p.newRecord['status'] as String),
        )
        .subscribe();
    // ring for 40 seconds, then give up
    _ringTimeout = Timer(const Duration(seconds: 40), () {
      if (_status == 'ringing') _hangUp();
    });
    if (widget.outgoing) _join(); // caller joins the channel straight away and waits
  }

  Future<void> _join() async {
    if (_rtc != null) return;
    // a phone can only run one voice session: leave any room first
    await ActiveRoom.current.value?.leave();
    final s = RtcSession(kind: 'call', id: _id, video: _video);
    _rtc = s;
    try {
      await s.start();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
      _hangUp();
    }
  }

  void _onStatus(String st) {
    if (!mounted) return;
    setState(() => _status = st);
    if (st == 'active') {
      _ringTimeout?.cancel();
      _clock ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _secs++));
    }
    if (st == 'ended' || st == 'declined' || st == 'missed') {
      if (st == 'declined' && widget.outgoing) toast(context, 'Call declined');
      _close();
    }
  }

  Future<void> _accept() async {
    try {
      await App.i.rpc('update_call', {'p_call': _id, 'p_status': 'active'});
      await _join();
      _onStatus('active');
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
      _close();
    }
  }

  Future<void> _decline() async {
    try {
      await App.i.rpc('update_call', {'p_call': _id, 'p_status': 'declined'});
    } catch (_) {}
    _close();
  }

  Future<void> _hangUp() async {
    try {
      await App.i.rpc('update_call', {'p_call': _id, 'p_status': 'ended'});
    } catch (_) {}
    _close();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _rtc?.stop();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    CallService.i._activeCall = null;
    _ringTimeout?.cancel();
    _clock?.cancel();
    if (_ch != null) db.removeChannel(_ch!);
    _rtc?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Profiles.get(_otherId);
    final engine = _rtc?.engine;
    final ringingIn = !widget.outgoing && _status == 'ringing';
    final label = switch (_status) {
      'ringing' => widget.outgoing ? 'Calling…' : (_video ? 'Incoming video call' : 'Incoming voice call'),
      'active' => '${(_secs ~/ 60).toString().padLeft(2, '0')}:${(_secs % 60).toString().padLeft(2, '0')}',
      _ => 'Call ended',
    };
    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ringingIn ? _decline() : _hangUp();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          if (_video && engine != null && _rtc != null)
            ValueListenableBuilder<Set<int>>(
              valueListenable: _rtc!.remotes,
              builder: (_, remotes, __) => remotes.isEmpty
                  ? AgoraVideoView(controller: VideoViewController(rtcEngine: engine, canvas: const VideoCanvas(uid: 0)))
                  : AgoraVideoView(controller: VideoViewController.remote(rtcEngine: engine, canvas: VideoCanvas(uid: remotes.first), connection: RtcConnection(channelId: _rtc!.channel))),
            )
          else
            Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF3A2A12), Colors.black], radius: 1.1))),
          if (_video && engine != null && _rtc != null)
            ValueListenableBuilder<Set<int>>(
              valueListenable: _rtc!.remotes,
              builder: (_, remotes, __) => remotes.isEmpty
                  ? const SizedBox.shrink()
                  : Positioned(
                      right: 16,
                      top: 60,
                      width: 110,
                      height: 160,
                      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: AgoraVideoView(controller: VideoViewController(rtcEngine: engine, canvas: const VideoCanvas(uid: 0)))),
                    ),
            ),
          SafeArea(
            child: Column(children: [
              const SizedBox(height: 40),
              if (!_video || _status != 'active') ...[
                Avatar(profile: p, size: 110, ring: C.gold),
                const SizedBox(height: 16),
              ],
              Text('${p?['username'] ?? ''}', style: serif(28, color: Colors.white)),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(color: Colors.white70)),
              const Spacer(),
              if (ringingIn)
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _btn(Icons.call_end, C.ruby, 'Decline', _decline),
                  _btn(_video ? Icons.videocam : Icons.call, C.emerald, 'Accept', _accept),
                ])
              else
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  if (_rtc != null)
                    ValueListenableBuilder<bool>(
                      valueListenable: _rtc!.micOn,
                      builder: (_, on, __) => _btn(on ? Icons.mic : Icons.mic_off, Colors.white24, on ? 'Mute' : 'Unmute', () => _rtc!.setMic(!on)),
                    ),
                  if (_video) _btn(_cam ? Icons.videocam : Icons.videocam_off, Colors.white24, 'Camera', () {
                    setState(() => _cam = !_cam);
                    _rtc?.setCamera(_cam);
                  }),
                  if (_video) _btn(Icons.cameraswitch, Colors.white24, 'Flip', () => _rtc?.switchCamera()),
                  if (!_video) _btn(_speaker ? Icons.volume_up : Icons.hearing, Colors.white24, 'Speaker', () {
                    setState(() => _speaker = !_speaker);
                    _rtc?.setSpeakerphone(_speaker);
                  }),
                  _btn(Icons.call_end, C.ruby, 'End', _hangUp),
                ]),
              const SizedBox(height: 40),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _btn(IconData icon, Color bg, String label, VoidCallback onTap) => Column(mainAxisSize: MainAxisSize.min, children: [
        Material(color: bg, shape: const CircleBorder(), child: IconButton(iconSize: 30, padding: const EdgeInsets.all(16), onPressed: onTap, icon: Icon(icon, color: Colors.white))),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);
}
