import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../theme/ym_theme.dart';
import 'mobile_room_chat_screen.dart';

/// Tab "Rooms": kategori (chip) -> sub-kategori -> daftar room. Room publik ramai, gaya WhatsApp Communities.
class RoomsTab extends StatefulWidget {
  final String myUsername;
  const RoomsTab({super.key, required this.myUsername});

  @override
  State<RoomsTab> createState() => RoomsTabState();
}

class RoomsTabState extends State<RoomsTab> {
  List<Map<String, dynamic>> _categories = [];
  int _selected = 0;
  // id sub-kategori -> daftar room
  final Map<int, List<Map<String, dynamic>>> _rooms = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/categories'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) throw Exception('kode ${res.statusCode}');
      final data = jsonDecode(res.body);
      _categories = List<Map<String, dynamic>>.from((data['categories'] as List).map((c) => Map<String, dynamic>.from(c as Map)));
      if (_selected >= _categories.length) _selected = 0;
      await _loadRooms();
    } catch (e) {
      _error = 'Tidak bisa memuat daftar room. Tarik ke bawah untuk mencoba lagi.';
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _subcategories {
    if (_categories.isEmpty) return [];
    return List<Map<String, dynamic>>.from(
        (_categories[_selected]['subcategories'] as List).map((s) => Map<String, dynamic>.from(s as Map)));
  }

  Future<void> _loadRooms() async {
    for (final sub in _subcategories) {
      final id = sub['id'] as int;
      try {
        final res = await http
            .get(Uri.parse('${AppConfig.apiBaseUrl}/subcategories/$id/rooms'))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          _rooms[id] = List<Map<String, dynamic>>.from(
              (jsonDecode(res.body)['rooms'] as List).map((r) => Map<String, dynamic>.from(r as Map)));
        }
      } catch (_) {}
    }
  }

  Future<void> _select(int index) async {
    setState(() => _selected = index);
    await _loadRooms();
    if (mounted) setState(() {});
  }

  void _join(String roomName, {String? pin}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MobileRoomChatScreen(myUsername: widget.myUsername, roomName: roomName, pin: pin),
      ),
    ).then((_) => reload());
  }

  Future<void> _askPinAndJoin(String roomName) async {
    final ctrl = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Room "$roomName" dikunci'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'PIN 8 angka', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(dialogContext).pop(ctrl.text),
            child: const Text('Masuk'),
          ),
        ],
      ),
    );
    if (pin != null && pin.isNotEmpty) _join(roomName, pin: pin);
  }

  Future<void> _createRoom(Map<String, dynamic> subcategory) async {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    var isPrivate = false;
    String? error;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Buat room di ${subcategory['name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  maxLength: 30,
                  decoration: const InputDecoration(labelText: 'Nama room', border: OutlineInputBorder()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Room dikunci (PIN)'),
                  value: isPrivate,
                  onChanged: (v) => setDialogState(() => isPrivate = v),
                ),
                if (isPrivate)
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: const InputDecoration(labelText: 'PIN 8 angka', border: OutlineInputBorder()),
                  ),
                if (error != null) Text(error!, style: const TextStyle(color: YmColors.buzzRed, fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => error = 'Nama room wajib diisi.');
                  return;
                }
                if (isPrivate && (pinCtrl.text.length != 8 || int.tryParse(pinCtrl.text) == null)) {
                  setDialogState(() => error = 'PIN harus 8 angka.');
                  return;
                }
                try {
                  final res = await http.post(
                    Uri.parse('${AppConfig.apiBaseUrl}/rooms/create'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'name': name,
                      'subcategory_id': subcategory['id'],
                      'creator_username': widget.myUsername,
                      'is_private': isPrivate,
                      if (isPrivate) 'pin': pinCtrl.text,
                    }),
                  );
                  if (res.statusCode == 200) {
                    if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
                  } else {
                    String detail = 'Gagal membuat room.';
                    try {
                      final d = jsonDecode(res.body)['detail'];
                      if (d is String) detail = d;
                    } catch (_) {}
                    setDialogState(() => error = detail);
                  }
                } catch (_) {
                  setDialogState(() => error = 'Tidak bisa terhubung ke server.');
                }
              },
              child: const Text('Buat'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      await _loadRooms();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _categories.isEmpty) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: YmColors.textMuted)),
            ),
          if (_categories.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ChoiceChip(
                  label: Text('${_categories[i]['name']}'),
                  selected: i == _selected,
                  selectedColor: YmColors.accentPurple,
                  labelStyle: TextStyle(
                    color: i == _selected ? Colors.white : YmColors.textDark,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => _select(i),
                ),
              ),
            ),
          for (final sub in _subcategories) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${sub['name']}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: YmColors.textDark)),
                  ),
                  TextButton.icon(
                    onPressed: () => _createRoom(sub),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Buat Room'),
                  ),
                ],
              ),
            ),
            if ((_rooms[sub['id'] as int] ?? const []).isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('Belum ada room.', style: TextStyle(color: YmColors.textMuted)),
              ),
            for (final room in _rooms[sub['id'] as int] ?? const <Map<String, dynamic>>[])
              _RoomCard(
                name: '${room['name']}',
                online: (room['online_count'] as num?)?.toInt() ?? 0,
                max: (room['max_members'] as num?)?.toInt() ?? 100,
                locked: room['is_private'] == true,
                onEnter: () => room['is_private'] == true ? _askPinAndJoin('${room['name']}') : _join('${room['name']}'),
              ),
          ],
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final String name;
  final int online;
  final int max;
  final bool locked;
  final VoidCallback onEnter;
  const _RoomCard({required this.name, required this.online, required this.max, required this.locked, required this.onEnter});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundColor: Color(0xFFE9E8FA),
                child: Icon(Icons.forum, color: YmColors.accentPurple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: YmColors.textDark)),
                        ),
                        if (locked) const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.lock, size: 15, color: YmColors.textMuted),
                        ),
                      ],
                    ),
                    Text('$online/$max orang online',
                        style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: YmColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: YmColors.accentPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: onEnter,
              child: const Text('Masuk Room', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
