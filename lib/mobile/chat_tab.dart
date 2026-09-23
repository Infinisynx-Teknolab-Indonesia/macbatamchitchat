import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config/app_config.dart';
import '../theme/ym_theme.dart';
import '../widgets/user_avatar.dart';
import 'chat_hub.dart';
import 'mobile_chat_screen.dart';
import 'models.dart';

/// Tab "Chat": kartu profil + daftar percakapan terbaru dengan penanda belum dibaca (gaya WhatsApp).
class ChatTab extends StatefulWidget {
  final String myUsername;
  const ChatTab({super.key, required this.myUsername});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final ChatHub _hub = ChatHub.instance;
  String? _myName;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/users/${widget.myUsername}/profile')
            .replace(queryParameters: {'viewer': widget.myUsername}),
      );
      if (res.statusCode == 200 && mounted) {
        final name = ((jsonDecode(res.body)['full_name'] as String?) ?? '').trim();
        setState(() => _myName = name.isEmpty ? null : name);
      }
    } catch (_) {}
  }

  String _timeLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return DateFormat('HH:mm').format(t);
    if (today.difference(day).inDays == 1) return 'Kemarin';
    return DateFormat('dd/MM/yy').format(t);
  }

  void _open(Conversation c) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MobileChatScreen(myUsername: widget.myUsername, peerUsername: c.peerUsername)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _hub,
      builder: (context, _) {
        final items = _hub.conversations;
        return RefreshIndicator(
          onRefresh: _hub.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFE9E8FA), borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    UserAvatar(username: widget.myUsername, viewer: widget.myUsername, radius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _myName ?? '@${widget.myUsername}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: YmColors.textDark),
                          ),
                          const SizedBox(height: 2),
                          const Row(
                            children: [
                              Icon(Icons.circle, size: 9, color: YmColors.statusOnline),
                              SizedBox(width: 5),
                              Text('Online', style: TextStyle(fontSize: 12, color: YmColors.textMuted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text('Recent Chats',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: YmColors.accentPurple)),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 30, 16, 16),
                  child: Text(
                    'Belum ada percakapan.\nBuka tab Friends lalu ketuk nama teman untuk mulai chat.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: YmColors.textMuted, fontSize: 14),
                  ),
                ),
              for (final c in items)
                ListTile(
                  onTap: () => _open(c),
                  leading: UserAvatar(username: c.peerUsername, viewer: widget.myUsername, radius: 24),
                  title: Text(
                    c.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: c.unread > 0 ? FontWeight.w800 : FontWeight.w600,
                      color: YmColors.textDark,
                    ),
                  ),
                  subtitle: Text(
                    c.lastIsMine ? 'Kamu: ${c.lastMessage}' : c.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.unread > 0 ? YmColors.textDark : YmColors.textMuted,
                      fontWeight: c.unread > 0 ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _timeLabel(c.lastTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: c.unread > 0 ? YmColors.accentPurple : YmColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (c.unread > 0)
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: YmColors.accentPurple, borderRadius: BorderRadius.circular(11)),
                          child: Text(
                            c.unread > 99 ? '99+' : '${c.unread}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        )
                      else
                        const SizedBox(height: 18),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
