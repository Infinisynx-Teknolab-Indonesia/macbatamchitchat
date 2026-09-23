import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/socket_service.dart';
import '../theme/ym_theme.dart';
import 'ad_slot.dart';
import 'models.dart';

class _RoomLine {
  final bool system;
  final String sender;
  final String text;
  final bool mine;
  const _RoomLine({required this.system, required this.sender, required this.text, required this.mine});
}

/// Chat room publik (teks). Musik bersama, undangan, dan pengaturan operator ada di aplikasi desktop.
class MobileRoomChatScreen extends StatefulWidget {
  final String myUsername;
  final String roomName;
  final String? pin;
  const MobileRoomChatScreen({super.key, required this.myUsername, required this.roomName, this.pin});

  @override
  State<MobileRoomChatScreen> createState() => _MobileRoomChatScreenState();
}

class _MobileRoomChatScreenState extends State<MobileRoomChatScreen> {
  late final SocketService _socket;
  final List<_RoomLine> _lines = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<Map<String, dynamic>> _members = [];
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    _socket = SocketService(
      onRoomJoined: (city, members) {
        if (!mounted) return;
        setState(() {
          _members = members;
          _joined = true;
        });
      },
      onUserLeft: (city, members) {
        if (mounted) setState(() => _members = members);
      },
      onSystemMessage: (text) => _add(_RoomLine(system: true, sender: '', text: text, mine: false)),
      onNewMessage: (sender, message, ts) =>
          _add(_RoomLine(system: false, sender: sender, text: message, mine: sender == 'Anda')),
      onError: (message) async {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        if (!_joined) {
          await Future.delayed(const Duration(milliseconds: 1200));
          if (mounted) Navigator.of(context).maybePop();
        }
      },
      onRoomFull: (city, maxMembers) async {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Room penuh'),
            content: Text('Room ini sudah berisi $maxMembers orang. Coba lagi nanti.'),
            actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
          ),
        );
        if (mounted) Navigator.of(context).maybePop();
      },
      onForceLogout: (reason) {
        if (mounted) Navigator.of(context).maybePop();
      },
    )..connect(AppConfig.socketUrl);
    _socket.joinRoom(city: widget.roomName, username: widget.myUsername, pin: widget.pin);
  }

  @override
  void dispose() {
    _socket.leaveRoom();
    _socket.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _add(_RoomLine line) {
    if (!mounted) return;
    setState(() => _lines.add(line));
    Future.delayed(const Duration(milliseconds: 60), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _socket.sendMessage(text);
    _input.clear();
  }

  String _display(String text) {
    if (text.startsWith(audiblePrefix)) {
      final parts = text.split(audibleSeparator);
      return '🔊 ${parts.length >= 2 ? parts[1] : 'Audible'}';
    }
    if (text.startsWith(imagePrefix)) return '📷 Foto';
    if (text.startsWith(locationPrefix)) return '📍 Lokasi';
    return text;
  }

  void _showMembers() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${_members.length} orang di room ini',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final m in _members)
              ListTile(
                dense: true,
                leading: const CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xFFE9E8FA),
                  child: Icon(Icons.person, size: 18, color: YmColors.accentPurple),
                ),
                title: Text('${m['nickname'] ?? 'Anggota'}'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECEAF9),
      appBar: AppBar(
        backgroundColor: YmColors.titleBarStart,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.roomName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(_joined ? '${_members.length} orang online' : 'Menghubungkan…',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.groups), tooltip: 'Anggota', onPressed: _showMembers)],
      ),
      body: Column(
        children: [
          const AdSlot(placement: 'room_chat'),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final line = _lines[i];
                if (line.system) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Text(line.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: YmColors.textMuted)),
                    ),
                  );
                }
                return Align(
                  alignment: line.mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: line.mine ? const Color(0xFFDCD9FB) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!line.mine)
                          Text(line.sender,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: YmColors.accentPurple)),
                        Text(_display(line.text), style: const TextStyle(fontSize: 15, color: YmColors.textDark)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ketik pesan ke room',
                        filled: true,
                        fillColor: const Color(0xFFF1F0FB),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  CircleAvatar(
                    backgroundColor: YmColors.accentPurple,
                    child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: _send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
