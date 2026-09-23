import 'package:flutter/material.dart';
import '../theme/ym_theme.dart';
import '../widgets/retro_title_bar.dart';
import '../widgets/app_sidebar.dart';
import '../services/window_launcher.dart';

class CreateRoomScreen extends StatefulWidget {
  final String myUsername;
  const CreateRoomScreen({super.key, required this.myUsername});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _locationCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _yourNameCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _yourNameCtrl.text = widget.myUsername;
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _cityCtrl.dispose();
    _yourNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final location = _locationCtrl.text.trim();
    if (location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama lokasi wajib diisi.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      // Rooms are created lazily server-side the moment someone joins them
      // (see app/sockets.py's join_city_room -> _get_or_create_room), so
      // "creating" a room here just means opening its Room Chat window —
      // joining IS creating, for the very first person.
      await WindowLauncher.openRoomChat(myUsername: widget.myUsername, roomName: location);
      if (mounted) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const RetroTitleBar(title: 'Batam ChitChat — Create Room', icon: Icons.add_circle_outline),
          Expanded(
            child: Row(
              children: [
                AppSidebar(myUsername: widget.myUsername, activeItem: 'create_room'),
                Container(width: 1, color: YmColors.borderLavender.withOpacity(0.5)),
                Expanded(
                  child: Container(
                    color: YmColors.panelBackground,
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [YmColors.titleBarStart, YmColors.titleBarEnd]),
                              ),
                              child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 32),
                            ),
                            const SizedBox(height: 16),
                            Text('Buat Room Baru', style: YmTextStyles.username.copyWith(fontSize: 20)),
                            const SizedBox(height: 6),
                            Text(
                              'Buat room baru berdasarkan lokasi, kota, dan nama kamu.',
                              textAlign: TextAlign.center,
                              style: YmTextStyles.statusMessage,
                            ),
                            const SizedBox(height: 24),

                            _LabeledField(
                              icon: Icons.location_on_outlined,
                              label: 'Nama Lokasi',
                              hint: 'Contoh: Nagoya, Harbour Bay, Batu Aji, dll',
                              controller: _locationCtrl,
                            ),
                            const SizedBox(height: 14),
                            _LabeledField(
                              icon: Icons.location_city_outlined,
                              label: 'Nama City',
                              hint: 'Contoh: Batam, Tanjungpinang, dll',
                              controller: _cityCtrl,
                            ),
                            const SizedBox(height: 14),
                            _LabeledField(
                              icon: Icons.person_outline,
                              label: 'Nama Anda',
                              hint: 'Contoh: Andi, Rina, Dika, dll',
                              controller: _yourNameCtrl,
                            ),

                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton(
                                onPressed: _submitting ? null : _createRoom,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: YmColors.accentPurple,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: _submitting
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Buat Room', style: TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final TextEditingController controller;

  const _LabeledField({required this.icon, required this.label, required this.hint, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: YmTextStyles.label),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: YmTextStyles.chatText,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: YmTextStyles.label,
            prefixIcon: Icon(icon, size: 18, color: YmColors.textMuted),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            filled: true,
            fillColor: YmColors.contentBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: YmColors.borderLavender.withOpacity(0.6))),
          ),
        ),
      ],
    );
  }
}
