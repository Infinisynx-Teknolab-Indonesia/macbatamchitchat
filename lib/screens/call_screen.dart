import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import '../config/app_config.dart';
import '../theme/ym_theme.dart';
import '../widgets/user_avatar.dart';
import '../services/socket_service.dart';

enum _CallPhase { ringingOutgoing, connecting, active, ended }

/// Voice or video call with one peer. Media flows directly between this
/// client and LiveKit's media server (LiveKit Cloud or self-hosted,
/// whichever the admin configured — see backend's AppSettings) — this
/// app's own backend is only used once, at the start, to fetch a LiveKit
/// access token via POST /api/calls/token.
///
/// IMPORTANT — NOT independently verified end-to-end: this code follows
/// livekit_client's documented API, but actually placing/receiving a call
/// needs a real LiveKit project (Cloud or self-hosted) configured by an
/// admin, a real microphone/camera, and a real Windows build — none of
/// which are available to test here. Treat this as a solid starting point
/// that will very likely need small fixes once tried on a real machine.
class CallScreen extends StatefulWidget {
  final String myUsername;
  final String peerUsername;
  final String callType; // "voice" | "video"
  final String callRoom;
  final bool isIncoming; // true = we already accepted, just need to connect
  final SocketService socket;

  const CallScreen({
    super.key,
    required this.myUsername,
    required this.peerUsername,
    required this.callType,
    required this.callRoom,
    required this.isIncoming,
    required this.socket,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  _CallPhase _phase = _CallPhase.ringingOutgoing;
  String? _errorMessage;
  lk.Room? _room;
  lk.LocalParticipant? _localParticipant;
  lk.RemoteParticipant? _remoteParticipant;
  bool _micEnabled = true;
  bool _cameraEnabled = false;

  @override
  void initState() {
    super.initState();
    _cameraEnabled = widget.callType == 'video';

    if (widget.isIncoming) {
      // We already tapped "Terima" before this screen opened — go
      // straight to fetching a token and connecting.
      _phase = _CallPhase.connecting;
      _connectToCall();
    } else {
      _phase = _CallPhase.ringingOutgoing;
      widget.socket.callInvite(
        callerUsername: widget.myUsername,
        targetUsername: widget.peerUsername,
        callType: widget.callType,
        callRoom: widget.callRoom,
      );
    }

    widget.socket.onCallAccepted = (callRoom) {
      setState(() => _phase = _CallPhase.connecting);
      _connectToCall();
    };
    widget.socket.onCallRejected = () {
      setState(() {
        _phase = _CallPhase.ended;
        _errorMessage = '${widget.peerUsername} menolak panggilan.';
      });
    };
    widget.socket.onCallFailed = (reason, targetUsername) {
      setState(() {
        _phase = _CallPhase.ended;
        _errorMessage = reason == 'offline' ? '${widget.peerUsername} sedang offline.' : 'Panggilan gagal.';
      });
    };
    widget.socket.onCallEnded = () {
      _hangUp(notifyPeer: false);
    };
  }

  Future<void> _connectToCall() async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/calls/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': widget.myUsername, 'call_room': widget.callRoom}),
      );

      if (res.statusCode != 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _phase = _CallPhase.ended;
          _errorMessage = data['detail'] ?? 'Gagal mendapatkan token panggilan.';
        });
        return;
      }

      final data = jsonDecode(res.body);
      final room = lk.Room();
      await room.connect(
        data['livekit_url'],
        data['token'],
        roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
      );

      await room.localParticipant?.setMicrophoneEnabled(true);
      if (widget.callType == 'video') {
        await room.localParticipant?.setCameraEnabled(true);
      }

      room.addListener(_onRoomUpdate);

      setState(() {
        _room = room;
        _localParticipant = room.localParticipant;
        _phase = _CallPhase.active;
      });
    } catch (e) {
      setState(() {
        _phase = _CallPhase.ended;
        _errorMessage = 'Gagal terhubung ke server panggilan: $e';
      });
    }
  }

  void _onRoomUpdate() {
    final room = _room;
    if (room == null) return;
    final remotes = room.remoteParticipants.values;
    setState(() {
      _remoteParticipant = remotes.isNotEmpty ? remotes.first : null;
      // If the only remote participant just left, the other side hung up.
      if (_remoteParticipant == null && _phase == _CallPhase.active) {
        _phase = _CallPhase.ended;
        _errorMessage = 'Panggilan berakhir.';
      }
    });
  }

  Future<void> _toggleMic() async {
    final enabled = !_micEnabled;
    await _localParticipant?.setMicrophoneEnabled(enabled);
    setState(() => _micEnabled = enabled);
  }

  Future<void> _toggleCamera() async {
    final enabled = !_cameraEnabled;
    await _localParticipant?.setCameraEnabled(enabled);
    setState(() => _cameraEnabled = enabled);
  }

  Future<void> _hangUp({bool notifyPeer = true}) async {
    if (notifyPeer) {
      widget.socket.callEnd(peerUsername: widget.peerUsername);
    }
    _room?.removeListener(_onRoomUpdate);
    await _room?.disconnect();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _room?.removeListener(_onRoomUpdate);
    _room?.disconnect();
    super.dispose();
  }

  lk.VideoTrack? _firstVideoTrack(lk.Participant? participant) {
    if (participant == null) return null;
    for (final pub in participant.videoTrackPublications) {
      final track = pub.track;
      if (track is lk.VideoTrack) return track;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _CallPhase.ringingOutgoing:
        return _statusView(icon: Icons.call_made, text: 'Memanggil @${widget.peerUsername}...');
      case _CallPhase.connecting:
        return _statusView(icon: Icons.sync, text: 'Menghubungkan...');
      case _CallPhase.ended:
        return _statusView(icon: Icons.call_end, text: _errorMessage ?? 'Panggilan berakhir.', isError: true);
      case _CallPhase.active:
        return widget.callType == 'video' ? _buildVideoLayout() : _buildVoiceLayout();
    }
  }

  Widget _statusView({required IconData icon, required String text, bool isError = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            username: widget.peerUsername,
            radius: 44,
            backgroundColor: YmColors.accentPurple.withOpacity(0.25),
            iconColor: Colors.white,
          ),
          const SizedBox(height: 16),
          Text('@${widget.peerUsername}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Icon(icon, color: isError ? YmColors.buzzRed : Colors.white70, size: 18),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(color: isError ? YmColors.buzzRed : Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildVoiceLayout() {
    return _statusView(icon: Icons.call, text: _micEnabled ? 'Terhubung' : 'Terhubung (mic dimatikan)');
  }

  Widget _buildVideoLayout() {
    final remoteTrack = _firstVideoTrack(_remoteParticipant);
    final localTrack = _firstVideoTrack(_localParticipant);

    return Stack(
      children: [
        Positioned.fill(
          child: remoteTrack != null
              ? lk.VideoTrackRenderer(remoteTrack)
              : Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: Text('Menunggu video @${widget.peerUsername}...', style: const TextStyle(color: Colors.white54)),
                ),
        ),
        if (_cameraEnabled && localTrack != null)
          Positioned(
            right: 16, bottom: 16,
            child: SizedBox(
              width: 120, height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: lk.VideoTrackRenderer(localTrack),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControls() {
    if (_phase == _CallPhase.ended) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
          child: const Text('Tutup'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_phase == _CallPhase.active) ...[
            _CallButton(
              icon: _micEnabled ? Icons.mic : Icons.mic_off,
              onTap: _toggleMic,
              backgroundColor: Colors.white24,
            ),
            const SizedBox(width: 20),
            if (widget.callType == 'video')
              _CallButton(
                icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                onTap: _toggleCamera,
                backgroundColor: Colors.white24,
              ),
            if (widget.callType == 'video') const SizedBox(width: 20),
          ],
          _CallButton(
            icon: Icons.call_end,
            onTap: () => _hangUp(),
            backgroundColor: YmColors.buzzRed,
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color backgroundColor;
  const _CallButton({required this.icon, required this.onTap, required this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(shape: BoxShape.circle, color: backgroundColor),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}
