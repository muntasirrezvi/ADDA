import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api.dart';

/// One Agora session (a voice room or a 1-to-1 call).
/// Tokens come from the `agora-token` server function; the uid is the user's public ID.
class RtcSession {
  RtcSession({required this.kind, required this.id, this.video = false});

  final String kind; // 'room' or 'call'
  final String id;
  final bool video;

  RtcEngine? engine;
  String channel = '';
  int uid = 0;
  bool speaker = false;

  /// Public IDs currently talking (0 = me).
  final talking = ValueNotifier<Set<int>>({});
  /// Remote users in the channel (for calls: who has joined).
  final remotes = ValueNotifier<Set<int>>({});
  final connected = ValueNotifier<bool>(false);
  final micOn = ValueNotifier<bool>(true);

  Future<Map<String, dynamic>> _token() async {
    final r = await App.i.fn('agora-token', {'kind': kind, 'id': id});
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> start() async {
    // rooms: listeners need no microphone; the room asks again before taking a seat
    if (kind == 'call') {
      final res = await [Permission.microphone, if (video) Permission.camera].request();
      if (res[Permission.microphone] != PermissionStatus.granted) throw Exception('Allow microphone access to make calls');
    }
    final t = await _token();
    channel = t['channel'] as String;
    uid = (t['uid'] as num).toInt();
    speaker = t['role'] == 'speaker';

    final e = createAgoraRtcEngine();
    await e.initialize(RtcEngineContext(appId: t['appId'] as String, channelProfile: ChannelProfileType.channelProfileLiveBroadcasting));
    e.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) => connected.value = true,
      onUserJoined: (connection, remoteUid, elapsed) => remotes.value = {...remotes.value, remoteUid},
      onUserOffline: (connection, remoteUid, reason) => remotes.value = {...remotes.value}..remove(remoteUid),
      onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
        final now = <int>{};
        for (final s in speakers) {
          if ((s.volume ?? 0) > 18) now.add(s.uid ?? 0);
        }
        if (!setEquals(now, talking.value)) talking.value = now;
      },
      onTokenPrivilegeWillExpire: (connection, token) => refresh(),
      onConnectionStateChanged: (connection, state, reason) => connected.value = state == ConnectionStateType.connectionStateConnected,
    ));
    await e.enableAudio();
    await e.setAudioProfile(profile: AudioProfileType.audioProfileMusicStandard, scenario: AudioScenarioType.audioScenarioChatroom);
    await e.enableAudioVolumeIndication(interval: 300, smooth: 3, reportVad: true);
    if (video) {
      await e.enableVideo();
      await e.startPreview();
    }
    await e.setDefaultAudioRouteToSpeakerphone(true);
    await e.joinChannel(
      token: t['token'] as String,
      channelId: channel,
      uid: uid,
      options: ChannelMediaOptions(
        clientRoleType: speaker ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        publishMicrophoneTrack: speaker,
        publishCameraTrack: video,
        autoSubscribeAudio: true,
        autoSubscribeVideo: video,
      ),
    );
    engine = e;
  }

  /// Ask for a fresh token (after taking or leaving a seat, or before expiry) and switch role.
  Future<void> refresh() async {
    final e = engine;
    if (e == null) return;
    final t = await _token();
    final nowSpeaker = t['role'] == 'speaker';
    await e.renewToken(t['token'] as String);
    if (nowSpeaker != speaker) {
      speaker = nowSpeaker;
      await e.updateChannelMediaOptions(ChannelMediaOptions(
        clientRoleType: speaker ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience,
        publishMicrophoneTrack: speaker && micOn.value,
      ));
    }
  }

  Future<void> setMic(bool on) async {
    micOn.value = on;
    await engine?.muteLocalAudioStream(!on);
  }

  Future<void> setSpeakerphone(bool on) async => engine?.setEnableSpeakerphone(on);
  Future<void> switchCamera() async => engine?.switchCamera();
  Future<void> setCamera(bool on) async => engine?.muteLocalVideoStream(!on);

  Future<void> stop() async {
    final e = engine;
    engine = null;
    if (e == null) return;
    try {
      await e.leaveChannel();
      await e.release();
    } catch (_) {}
  }
}
