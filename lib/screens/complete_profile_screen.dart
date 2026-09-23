import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../theme/ym_theme.dart';
import 'home_screen.dart';

/// Shown ONCE, right after a Google/FJB Batam account's FIRST successful
/// login (server returns profile_complete: false — see backend's User
/// model). Collects the same fields RegisterScreen collects for local
/// accounts, so both signup paths end up with equivalent profile data.
/// Submitting calls PATCH /users/{username}/privacy with
/// mark_profile_complete: true, so this screen never shows again for
/// that account.
class CompleteProfileScreen extends StatefulWidget {
  final String username;
  const CompleteProfileScreen({super.key, required this.username});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _fullNameCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  DateTime? _birthDate;
  String? _gender;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _whatsappCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _submit() async {
    if (_fullNameCtrl.text.trim().isEmpty || _gender == null) {
      setState(() => _error = 'Nama/alias dan jenis kelamin wajib diisi.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await http.patch(
        Uri.parse('${AppConfig.apiBaseUrl}/users/${widget.username}/privacy'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'full_name': _fullNameCtrl.text.trim(),
          'gender': _gender,
          'whatsapp_number': _whatsappCtrl.text.trim().isEmpty ? null : _whatsappCtrl.text.trim(),
          'birth_date': _birthDate?.toIso8601String().split('T').first,
          'mark_profile_complete': true,
        }),
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(myUsername: widget.username)),
        );
      } else {
        setState(() {
          _loading = false;
          _error = 'Gagal menyimpan profil. Coba lagi.';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Tidak bisa terhubung ke server.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YmColors.titleBarStart,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(ymBorderRadius),
              border: Border.all(color: Colors.white24),
            ),
            // RadioListTile (gender, di bawah) mengecat ink splash-nya ke Material
            // TERDEKAT — tanpa ini, warna latar dari BoxDecoration Container di atas
            // menghalangi itu dan Flutter melempar assertion error untuknya.
            child: Material(
              color: Colors.transparent,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.person_add_alt_1, color: Colors.white, size: 36),
                const SizedBox(height: 8),
                const Text(
                  'Lengkapi Profil Kamu',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Cuma sekali ini aja — biar teman kamu gampang kenalin kamu.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _field(_fullNameCtrl, 'Nama / Alias', icon: Icons.badge_outlined),
                const SizedBox(height: 12),
                _field(_whatsappCtrl, 'Nomor WhatsApp (opsional)', icon: Icons.chat_outlined, keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickBirthDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.cake_outlined, color: Colors.white70, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          _birthDate == null ? 'Tanggal Lahir (opsional)' : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}',
                          style: TextStyle(color: _birthDate == null ? Colors.white54 : Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'male',
                        groupValue: _gender,
                        onChanged: (v) => setState(() => _gender = v),
                        title: const Text('Pria', style: TextStyle(color: Colors.white, fontSize: 13)),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'female',
                        groupValue: _gender,
                        onChanged: (v) => setState(() => _gender = v),
                        title: const Text('Wanita', style: TextStyle(color: Colors.white, fontSize: 13)),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YmColors.accentPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Simpan & Lanjutkan'),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {required IconData icon, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white70, size: 18),
        hintText: label,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
