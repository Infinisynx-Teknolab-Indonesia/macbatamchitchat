/// Penanda isi pesan (sama dengan aplikasi desktop dan backend).
const String buzzMarker = '[BUZZ]';
const String locationPrefix = '[LOCATION]';
const String imagePrefix = '[IMAGE_BASE64]';
const String audiblePrefix = '\uE000AUDIBLE';
const String audibleSeparator = '\u241F';

/// Epoch detik dari server -> waktu lokal HP.
DateTime timeFromTs(double ts) => DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());

/// Ringkasan satu baris sebuah pesan (daftar percakapan / banner).
String previewOf(String content) {
  if (content == buzzMarker) return '⚡ Buzz!';
  if (content.startsWith(imagePrefix)) return '📷 Foto';
  if (content.startsWith(locationPrefix)) return '📍 Lokasi';
  if (content.startsWith(audiblePrefix)) {
    final parts = content.split(audibleSeparator);
    return '🔊 ${parts.length >= 2 ? parts[1] : 'Audible'}';
  }
  final text = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  return text.length <= 80 ? text : '${text.substring(0, 79)}…';
}

/// Satu percakapan di tab Chat.
class Conversation {
  final String peerUsername;
  final String? nickname;
  final String? alias;
  final String? displayNameRaw; // dari server: nama panggilan > nickname (null = belum ada)
  final String? photoUrl;
  final String lastMessage;
  final DateTime lastTime;
  final bool lastIsMine;
  final int unread;

  const Conversation({
    required this.peerUsername,
    this.nickname,
    this.alias,
    this.displayNameRaw,
    this.photoUrl,
    required this.lastMessage,
    required this.lastTime,
    required this.lastIsMine,
    required this.unread,
  });

  /// Nama yang tampil: nama panggilan > nickname > @username.
  String get displayName =>
      (displayNameRaw != null && displayNameRaw!.isNotEmpty) ? displayNameRaw! : '@$peerUsername';

  bool get hasRealName => displayNameRaw != null && displayNameRaw!.isNotEmpty;

  Conversation copyWith({String? lastMessage, DateTime? lastTime, bool? lastIsMine, int? unread}) => Conversation(
        peerUsername: peerUsername,
        nickname: nickname,
        alias: alias,
        displayNameRaw: displayNameRaw,
        photoUrl: photoUrl,
        lastMessage: lastMessage ?? this.lastMessage,
        lastTime: lastTime ?? this.lastTime,
        lastIsMine: lastIsMine ?? this.lastIsMine,
        unread: unread ?? this.unread,
      );

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        peerUsername: j['peer_username'] as String,
        nickname: j['nickname'] as String?,
        alias: j['alias'] as String?,
        displayNameRaw: j['display_name'] as String?,
        photoUrl: j['photo_url'] as String?,
        lastMessage: (j['last_message'] as String?) ?? '',
        lastTime: timeFromTs((j['last_ts'] as num).toDouble()),
        lastIsMine: (j['last_is_mine'] as bool?) ?? false,
        unread: (j['unread'] as num?)?.toInt() ?? 0,
      );
}

/// Satu pesan di layar chat.
class ChatEntry {
  final String sender;
  final String text;
  final DateTime time;
  final bool isMine;
  const ChatEntry({required this.sender, required this.text, required this.time, required this.isMine});
}
