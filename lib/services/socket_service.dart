import 'package:socket_io_client/socket_io_client.dart' as io;

/// Wraps the Socket.IO connection to the FastAPI backend.
/// Event names match exactly what's defined in app/sockets.py on the server.
class SocketService {
  io.Socket? _socket;

  /// `members` = [{uid, nickname, gender, speaker, role}] — the server never
  /// sends other people's usernames in a room, only nickname + uid.
  final void Function(String city, List<Map<String, dynamic>> members)? onRoomJoined;
  final void Function(String city, List<Map<String, dynamic>> members)? onUserLeft;
  final void Function(String text)? onSystemMessage;
  final void Function(String sender, String message, double ts)? onNewMessage;
  final void Function(String from)? onBuzzReceived;
  final void Function(String message)? onError;
  final void Function(String sender, String message, double ts)? onDirectMessageReceived;
  final void Function(String recipient, String message, double ts)? onDirectMessageSent;
  final void Function(String city, int maxMembers)? onRoomFull;
  void Function(String sourceType, String sourceValue, String playlistId, String startedBy)? onMusicStarted;
  void Function()? onMusicStopped;
  void Function(String reason)? onForceLogout;
  /// The server removed THIS connection from its room (reason: 'logout' or
  /// 'replaced' = the same user opened that room in a newer window). The
  /// room window is expected to close itself.
  void Function(String reason)? onRoomEvicted;
  void Function(String callerUsername, String callType, String callRoom)? onCallIncoming;
  void Function(int requestId, String fromName)? onFriendRequestReceived;
  void Function(String callRoom)? onCallAccepted;
  void Function()? onCallRejected;
  void Function(String reason, String targetUsername)? onCallFailed;
  void Function()? onCallEnded;

  SocketService({
    this.onRoomJoined,
    this.onUserLeft,
    this.onSystemMessage,
    this.onNewMessage,
    this.onBuzzReceived,
    this.onError,
    this.onDirectMessageReceived,
    this.onDirectMessageSent,
    this.onRoomFull,
    this.onForceLogout,
    this.onCallIncoming,
    this.onFriendRequestReceived,
  });

  static List<Map<String, dynamic>> _asMemberList(dynamic raw) =>
      (raw as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  /// SECURITY NOTE: always connect over wss:// (TLS) in production, never
  /// plain ws://. Swap the scheme in [serverUrl] once you have a real
  /// domain + certificate in front of the backend.
  void connect(String serverUrl) {
    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) => print('[socket] connected'));
    _socket!.onDisconnect((_) => print('[socket] disconnected'));

    _socket!.on('room_joined', (data) {
      onRoomJoined?.call(data['city'], _asMemberList(data['members']));
    });
    _socket!.on('user_left', (data) {
      // Fired whenever ANYONE disconnects/leaves this room — this is what
      // makes offline members disappear from the room's list automatically,
      // rather than lingering there forever.
      onUserLeft?.call(data['city'], _asMemberList(data['members']));
    });
    _socket!.on('system_message', (data) => onSystemMessage?.call(data['text']));
    _socket!.on('new_message', (data) {
      onNewMessage?.call(data['sender'], data['message'], (data['ts'] as num).toDouble());
    });
    _socket!.on('message_sent', (data) {
      onNewMessage?.call('Anda', data['message'], (data['ts'] as num).toDouble());
    });
    _socket!.on('buzz_received', (data) => onBuzzReceived?.call(data['from']));
    _socket!.on('error', (data) => onError?.call(data['message']));
    _socket!.on('room_full', (data) => onRoomFull?.call(data['city'], data['max_members']));
    _socket!.on('music_started', (data) => onMusicStarted?.call(
          data['source_type'], data['source_value'], data['playlist_id'] ?? '', data['started_by'],
        ));
    _socket!.on('music_stopped', (data) => onMusicStopped?.call());
    _socket!.on('force_logout', (data) => onForceLogout?.call(data['reason'] ?? 'unknown'));
    _socket!.on('room_evicted', (data) => onRoomEvicted?.call(data['reason'] ?? 'unknown'));
    _socket!.on('call_incoming', (data) => onCallIncoming?.call(data['caller_username'], data['call_type'], data['call_room']));
    _socket!.on('friend_request_received', (data) => onFriendRequestReceived?.call(data['request_id'], data['from_name'] ?? 'Seseorang'));
    _socket!.on('call_accepted', (data) => onCallAccepted?.call(data['call_room']));
    _socket!.on('call_rejected', (data) => onCallRejected?.call());
    _socket!.on('call_failed', (data) => onCallFailed?.call(data['reason'], data['target_username']));
    _socket!.on('call_ended', (data) => onCallEnded?.call());

    // Direct/private messages — NOT room-scoped, see app/sockets.py's
    // send_direct_message. This is what real private-chat windows use,
    // as opposed to join_city_room/send_message (public room chat).
    _socket!.on('direct_message_received', (data) {
      onDirectMessageReceived?.call(data['sender'], data['message'], (data['ts'] as num).toDouble());
    });
    _socket!.on('direct_message_sent', (data) {
      onDirectMessageSent?.call(data['recipient'], data['message'], (data['ts'] as num).toDouble());
    });

    _socket!.connect();
  }

  void joinRoom({required String city, required String username, String? fcmToken, String? pin}) {
    _socket?.emit('join_city_room', {
      'city': city,
      'username': username,
      'fcm_token': fcmToken,
      if (pin != null) 'pin': pin,
    });
  }

  void sendMessage(String message) {
    _socket?.emit('send_message', {'message': message});
  }

  /// True private 1-on-1 messaging — independent of rooms. A user can
  /// have any number of these open with different people at once.
  void sendDirectMessage({
    required String senderUsername,
    required String recipientUsername,
    required String message,
  }) {
    _socket?.emit('send_direct_message', {
      'sender_username': senderUsername,
      'recipient_username': recipientUsername,
      'message': message,
    });
  }

  void buzz({required String requesterUsername, required String targetUsername}) {
    _socket?.emit('buzz', {'requester_username': requesterUsername, 'target_username': targetUsername});
  }

  void playMusic({
    required String city,
    required String requesterUsername,
    required String sourceType, // "upload" | "youtube"
    required String sourceValue, // file_url or YouTube video ID (may be empty for a pure playlist)
    String playlistId = '', // YouTube only — enables playlist autoplay/auto-advance
  }) {
    _socket?.emit('play_music', {
      'city': city,
      'requester_username': requesterUsername,
      'source_type': sourceType,
      'source_value': sourceValue,
      'playlist_id': playlistId,
    });
  }

  void stopMusic({required String city, required String requesterUsername}) {
    _socket?.emit('stop_music', {'city': city, 'requester_username': requesterUsername});
  }

  /// Called once when a Private Chat window opens — lets the server
  /// enforce MAX_PRIVATE_CHAT_WINDOWS_PER_USER (currently 10). If that
  /// limit is exceeded, the server force-logs-out the WHOLE session
  /// (see onForceLogout) rather than just rejecting this one window.
  void registerPrivateChat(String username) {
    _socket?.emit('register_private_chat', {'username': username});
  }

  /// Lightweight "I'm online, notify me" registration — used by Home,
  /// see backend's register_presence docstring for why this is separate
  /// from registerPrivateChat (doesn't count against the private-chat
  /// window limit).
  void registerPresence(String username) {
    _socket?.emit('register_presence', {'username': username});
  }

  void unregisterPrivateChat(String username) {
    _socket?.emit('unregister_private_chat', {'username': username});
  }

  void callInvite({required String callerUsername, required String targetUsername, required String callType, required String callRoom}) {
    _socket?.emit('call_invite', {
      'caller_username': callerUsername,
      'target_username': targetUsername,
      'call_type': callType,
      'call_room': callRoom,
    });
  }

  void callAccept({required String callerUsername, required String callRoom}) {
    _socket?.emit('call_accept', {'caller_username': callerUsername, 'call_room': callRoom});
  }

  void callReject({required String callerUsername}) {
    _socket?.emit('call_reject', {'caller_username': callerUsername});
  }

  void callEnd({required String peerUsername}) {
    _socket?.emit('call_end', {'peer_username': peerUsername});
  }

  void inviteToRoom({required String inviterUsername, required String targetUsername, required String city}) {
    _socket?.emit('invite_to_room', {
      'inviter_username': inviterUsername,
      'target_username': targetUsername,
      'city': city,
    });
  }

  void leaveRoom() {
    _socket?.emit('leave_city_room', {});
  }

  void dispose() {
    _socket?.dispose();
  }
}

