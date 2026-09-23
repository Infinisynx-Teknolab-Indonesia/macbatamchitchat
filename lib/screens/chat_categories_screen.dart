import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import '../theme/ym_theme.dart';
import '../widgets/retro_title_bar.dart';
import '../config/app_config.dart';
import '../services/window_launcher.dart';
import '../services/nickname_gate.dart';

class _Category {
  final int id;
  final String name;
  final List<_Subcategory> subcategories;
  _Category({required this.id, required this.name, required this.subcategories});
}

class _Subcategory {
  final int id;
  final String name;
  _Subcategory({required this.id, required this.name});
}

class _RoomInfo {
  final String name;
  final int onlineCount;
  final int maxMembers;
  final bool isPrivate;
  final bool isDefault;
  final String? creatorUsername;
  _RoomInfo({
    required this.name,
    required this.onlineCount,
    required this.maxMembers,
    this.isPrivate = false,
    this.isDefault = false,
    this.creatorUsername,
  });
}

/// 3-panel browser: Category -> Subcategory -> Room list. Data comes from
/// the backend (GET /api/categories), NOT hardcoded — since this app is
/// specifically for Batam, "Regional" is Batam's own kecamatan, not other
/// Indonesian provinces. "Buat Room Baru" only appears once a subcategory
/// is selected — there's no standalone/global create-room entry point.
class ChatCategoriesScreen extends StatefulWidget {
  final String myUsername;
  const ChatCategoriesScreen({super.key, required this.myUsername});

  @override
  State<ChatCategoriesScreen> createState() => _ChatCategoriesScreenState();
}

class _ChatCategoriesScreenState extends State<ChatCategoriesScreen> {
  List<_Category> _categories = [];
  _Category? _selectedCategory;
  _Subcategory? _selectedSubcategory;
  List<_RoomInfo> _rooms = [];
  bool _loadingCategories = true;
  bool _loadingRooms = false;
  String? _categoriesError;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _configureWindowSize();
  }

  /// Prevents the "RenderListTile overflow" crash class of bug: without a
  /// minimum size, this window could be resized down until its 3-panel
  /// layout (categories + subcategories + room list) had no room left for
  /// the room list's ListTile content (icon + title + subtitle + button).
  Future<void> _configureWindowSize() async {
    try {
      await windowManager.setMinimumSize(const Size(950, 620));
      await windowManager.setResizable(true);
    } catch (e) {
      // ignore: avoid_print
      print('[Rooms] window_manager unavailable (native patch from NATIVE_SETUP.md not applied?): $e');
    }
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoriesError = null;
    });
    try {
      // Timeout added deliberately — without it, an unreachable backend
      // (server not running, wrong AppConfig URL, firewall blocking it)
      // makes this hang forever instead of showing an error, which is
      // exactly what an endless loading spinner with no error looks like.
      final res = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/categories'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final categories = (data['categories'] as List).map((c) => _Category(
              id: c['id'],
              name: c['name'],
              subcategories: (c['subcategories'] as List)
                  .map((s) => _Subcategory(id: s['id'], name: s['name']))
                  .toList(),
            )).toList();
        setState(() {
          _categories = categories;
          _loadingCategories = false;
          if (categories.isNotEmpty) {
            _selectedCategory = categories.first;
            if (categories.first.subcategories.isNotEmpty) {
              _selectedSubcategory = categories.first.subcategories.first;
              _loadRooms(_selectedSubcategory!.id);
            }
          }
        });
      } else {
        // Previously this branch did nothing at all if the status wasn't
        // 200 — meaning _loadingCategories never got set back to false,
        // which is exactly what an endless spinner with no error looks like.
        setState(() {
          _loadingCategories = false;
          _categoriesError = 'Server merespons dengan error (${res.statusCode}).';
        });
      }
    } on TimeoutException {
      setState(() {
        _loadingCategories = false;
        _categoriesError = 'Server tidak merespons. Pastikan backend sedang jalan dan '
            'alamat di lib/config/app_config.dart sudah benar.';
      });
    } catch (e) {
      setState(() {
        _loadingCategories = false;
        _categoriesError = 'Tidak bisa terhubung ke server: $e';
      });
    }
  }

  Future<void> _loadRooms(int subcategoryId) async {
    setState(() => _loadingRooms = true);
    try {
      final res = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/subcategories/$subcategoryId/rooms'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _rooms = (data['rooms'] as List).map((r) => _RoomInfo(
                name: r['name'],
                onlineCount: r['online_count'],
                maxMembers: r['max_members'],
                isPrivate: r['is_private'] ?? false,
                isDefault: r['is_default'] ?? false,
                creatorUsername: r['creator_username'],
              )).toList();
          _loadingRooms = false;
        });
      }
    } catch (_) {
      setState(() => _loadingRooms = false);
    }
  }

  /// Single entry point for entering a room. Someone without a nickname
  /// is asked to create one first (see nickname_gate.dart) instead of
  /// being sent into a room that won't let them in.
  Future<void> _joinRoom(String roomName, {String? pin}) async {
    if (!await ensureNickname(context, widget.myUsername)) return;
    if (!mounted) return;
    await WindowLauncher.openRoomChat(myUsername: widget.myUsername, roomName: roomName, pin: pin);
  }

  Future<void> _confirmDeleteRoom(_RoomInfo room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Hapus room "${room.name}"?'),
        content: const Text(
          'Semua orang yang sedang di dalam akan dikeluarkan dan riwayat chat room ini '
          'akan hilang. Tindakan ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final res = await http.delete(
        Uri.parse('${AppConfig.apiBaseUrl}/rooms/${Uri.encodeComponent(room.name)}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'requester_username': widget.myUsername}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        if (_selectedSubcategory != null) _loadRooms(_selectedSubcategory!.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Room "${room.name}" dihapus.')));
      } else {
        String message = 'Gagal menghapus room.';
        try {
          message = jsonDecode(res.body)['detail']?.toString() ?? message;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa terhubung ke server.')));
      }
    }
  }

  void _showPinDialogAndJoin(String roomName) {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Room Private: $roomName'),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          maxLength: 8,
          obscureText: true,
          decoration: const InputDecoration(isDense: true, labelText: 'Masukkan PIN (8 digit)', counterText: ''),
          onSubmitted: (_) {
            Navigator.of(dialogContext).pop();
            _joinRoom(roomName, pin: pinCtrl.text);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _joinRoom(roomName, pin: pinCtrl.text);
            },
            child: const Text('Masuk'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateRoomDialog() async {
    if (_selectedSubcategory == null) return;
    if (!await ensureNickname(context, widget.myUsername)) return;
    if (!mounted) return;
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    bool isPrivate = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Buat Room di ${_selectedSubcategory!.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Nama Room',
                  hintText: 'Contoh: Diskusi Warga ${_selectedSubcategory!.name}',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: isPrivate,
                onChanged: (v) => setDialogState(() => isPrivate = v ?? false),
                title: const Text('Room Private (butuh PIN)', style: TextStyle(fontSize: 13)),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (isPrivate)
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'PIN (8 digit angka)',
                    counterText: '',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                if (isPrivate && (pinCtrl.text.length != 8 || int.tryParse(pinCtrl.text) == null)) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('PIN harus persis 8 digit angka.')),
                  );
                  return;
                }
                try {
                  final res = await http.post(
                    Uri.parse('${AppConfig.apiBaseUrl}/rooms/create'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'name': name,
                      'subcategory_id': _selectedSubcategory!.id,
                      'creator_username': widget.myUsername,
                      'is_private': isPrivate,
                      if (isPrivate) 'pin': pinCtrl.text,
                    }),
                  );
                  if (res.statusCode == 200) {
                    Navigator.of(dialogContext).pop(true);
                  } else {
                    final data = jsonDecode(res.body);
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(data['detail'] ?? 'Gagal membuat room.')),
                      );
                    }
                  }
                } catch (_) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Tidak bisa terhubung ke server.')),
                    );
                  }
                }
              },
              child: const Text('Buat'),
            ),
          ],
        ),
      ),
    );

    if (created == true && _selectedSubcategory != null) {
      _loadRooms(_selectedSubcategory!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const RetroTitleBar(title: 'Batam ChitChat — Rooms', icon: Icons.explore_outlined),
          Expanded(
            child: Row(
              children: [
                if (_loadingCategories)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else if (_categoriesError != null)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 40, color: YmColors.textMuted),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(_categoriesError!, textAlign: TextAlign.center, style: YmTextStyles.statusMessage),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _loadCategories,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Coba Lagi'),
                            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  // Panel 1: top-level categories
                  _Panel(
                    width: 170,
                    header: 'KATEGORI',
                    children: [
                      for (final cat in _categories)
                        _ListRow(
                          label: cat.name,
                          selected: cat.id == _selectedCategory?.id,
                          onTap: () => setState(() {
                            _selectedCategory = cat;
                            _selectedSubcategory = cat.subcategories.isNotEmpty ? cat.subcategories.first : null;
                            _rooms = [];
                            if (_selectedSubcategory != null) _loadRooms(_selectedSubcategory!.id);
                          }),
                        ),
                    ],
                  ),
                  _Divider(),
                  // Panel 2: subcategories
                  _Panel(
                    width: 190,
                    header: 'SUB-KATEGORI',
                    children: [
                      for (final sub in _selectedCategory?.subcategories ?? <_Subcategory>[])
                        _ListRow(
                          label: sub.name,
                          selected: sub.id == _selectedSubcategory?.id,
                          onTap: () => setState(() {
                            _selectedSubcategory = sub;
                            _loadRooms(sub.id);
                          }),
                        ),
                    ],
                  ),
                  _Divider(),
                  // Panel 3: rooms in the selected subcategory + contextual "Buat Room"
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          color: YmColors.contentBackground,
                          child: Row(
                            children: [
                              Expanded(child: Text(_selectedSubcategory?.name ?? '', style: YmTextStyles.username)),
                              // "Buat Room" ONLY appears here, tied to whichever
                              // subcategory is currently selected — no global
                              // create-room button exists anywhere else.
                              if (_selectedSubcategory != null)
                                TextButton.icon(
                                  onPressed: _showCreateRoomDialog,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Buat Room Baru'),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _loadingRooms
                              ? const Center(child: CircularProgressIndicator())
                              : _rooms.isEmpty
                                  ? Center(
                                      child: Text('Belum ada room di sini. Jadi yang pertama!', style: YmTextStyles.statusMessage),
                                    )
                                  : ListView(
                                      children: [
                                        for (final room in _rooms)
                                          ListTile(
                                            leading: Icon(
                                              room.isPrivate ? Icons.lock_outline : Icons.chat_bubble_outline,
                                              color: YmColors.accentPurple,
                                            ),
                                            title: Text(room.name, style: YmTextStyles.buddyName),
                                            subtitle: Text('${room.onlineCount}/${room.maxMembers} orang online', style: YmTextStyles.statusMessage),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Hanya pembuat room yang melihat ini — room default (creatorUsername
                                                // null) tidak akan pernah cocok dengan siapa pun.
                                                if (room.creatorUsername == widget.myUsername)
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline, size: 20, color: YmColors.buzzRed),
                                                    tooltip: 'Hapus Room',
                                                    onPressed: () => _confirmDeleteRoom(room),
                                                  ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: YmColors.accentPurple,
                                                    foregroundColor: Colors.white,
                                                  ),
                                                  onPressed: () => room.isPrivate
                                                      ? _showPinDialogAndJoin(room.name)
                                                      : _joinRoom(room.name),
                                                  child: const Text('Masuk Room'),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final double width;
  final String header;
  final List<Widget> children;
  const _Panel({required this.width, required this.header, required this.children});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        color: YmColors.panelBackground,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(header, style: YmTextStyles.label),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 1, color: YmColors.borderLavender.withOpacity(0.5));
}

class _ListRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ListRow({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? YmColors.accentPurple.withOpacity(0.15) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label, style: YmTextStyles.buddyName),
      ),
    );
  }
}
