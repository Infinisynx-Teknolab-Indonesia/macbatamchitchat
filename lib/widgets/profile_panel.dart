import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../config/app_config.dart';
import '../theme/ym_theme.dart';
import 'user_avatar.dart';

const _apiBase = AppConfig.apiBaseUrl;

/// The editor for YOUR OWN profile — used both as the "Profil" tab in the
/// Settings window and inside ProfileEditScreen (opened by tapping your
/// avatar on Home), so there is exactly one implementation of it.
///
/// What can be changed:
///   - Foto: always (upload / replace). No photo yet -> default person icon.
///   - Nickname + Jenis kelamin: FILLED IN ONCE. While still empty they're
///     editable here (this is the "create nickname for the first time"
///     path — before, they were shown as locked '-' with no way to fill
///     them). Once set they lock, matching the server's own rule.
///   - Nomor WhatsApp, Alamat, Password: always.
class ProfilePanel extends StatefulWidget {
  final String username;
  final EdgeInsetsGeometry padding;
  const ProfilePanel({super.key, required this.username, this.padding = const EdgeInsets.all(20)});

  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  bool _uploadingPhoto = false;
  int? _photoVersion; // bumps after an upload so the new image isn't served from cache

  final _nicknameCtrl = TextEditingController();
  String? _pickedGender; // 'male' | 'female', only used while gender is still unset
  bool _savingIdentity = false;
  String? _identityMessage;
  bool _identityOk = false;

  final _whatsappCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _savingContact = false;
  String? _contactSaveMessage;

  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  bool _changingPassword = false;
  String? _passwordMessage;

  String get _fullName => ((_profile?['full_name'] as String?) ?? '').trim();
  String get _gender => (_profile?['gender'] as String?) ?? '';
  bool get _needsNickname => _fullName.isEmpty;
  bool get _needsGender => _gender != 'male' && _gender != 'female';
  // Server's own check (see app/friends.py's update_own_privacy): true only
  // once full_name is set AND the one allowed change hasn't been used yet.
  bool get _canChangeNickname => (_profile?['can_change_nickname'] as bool?) ?? false;
  bool _editingNickname = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _whatsappCtrl.dispose();
    _addressCtrl.dispose();
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await http.get(Uri.parse('$_apiBase/users/${widget.username}/profile').replace(
        queryParameters: {'viewer': widget.username}, // self-view — server includes locked/private fields only for this
      ));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final firstLoad = _profile == null;
        setState(() {
          _profile = data;
          // Only prefill on the first load, so a silent refresh after
          // saving something else never wipes what's being typed.
          if (firstLoad) {
            _whatsappCtrl.text = data['whatsapp_number'] ?? '';
            _addressCtrl.text = data['address'] ?? '';
          }
          _loading = false;
        });
      } else if (!silent) {
        setState(() {
          _error = 'Gagal memuat profil.';
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted || silent) return;
      setState(() {
        _error = 'Tidak bisa terhubung ke server.';
        _loading = false;
      });
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      final uri = Uri.parse('$_apiBase/users/${widget.username}/upload-photo');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', path));
      final streamedResponse = await request.send();
      final res = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        ProfilePhotoCache.invalidate(widget.username);
        setState(() {
          _profile?['photo_url'] = data['photo_url'];
          _photoVersion = DateTime.now().millisecondsSinceEpoch;
        });
      } else {
        String message = 'Gagal unggah foto.';
        try {
          message = jsonDecode(res.body)['detail']?.toString() ?? message;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal unggah foto: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _saveIdentity() async {
    final changingNickname = _needsNickname || _editingNickname;
    final nickname = _nicknameCtrl.text.trim();
    if (changingNickname && nickname.length < 2) {
      setState(() {
        _identityOk = false;
        _identityMessage = 'Nickname minimal 2 karakter.';
      });
      return;
    }
    if (!_needsNickname && _needsGender && _pickedGender == null) {
      setState(() {
        _identityOk = false;
        _identityMessage = 'Pilih jenis kelamin dulu.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Simpan?'),
        content: Text(
          _editingNickname
              // Changing an ALREADY-SET nickname: this is the one allowed
              // change, so warn it's the last one, distinct from the
              // "isi sekali" wording shown for the very first save.
              ? 'Ini adalah satu-satunya kesempatan ganti nickname. Setelah '
                'disimpan, nickname tidak bisa diubah lagi. Lanjutkan?'
              : 'Nickname dan jenis kelamin hanya bisa diisi sekali — setelah tersimpan '
                'tidak bisa diubah lagi (nickname masih boleh diganti sekali nanti). Lanjutkan?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _savingIdentity = true;
      _identityMessage = null;
    });
    try {
      final res = await http.patch(
        Uri.parse('$_apiBase/users/${widget.username}/privacy'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (changingNickname) 'full_name': nickname,
          if (_needsGender && _pickedGender != null) 'gender': _pickedGender,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _loadProfile(silent: true);
        if (!mounted) return;
        setState(() {
          _savingIdentity = false;
          _identityOk = true;
          _editingNickname = false;
          _identityMessage = 'Tersimpan.';
        });
      } else {
        String message = 'Gagal menyimpan.';
        try {
          message = jsonDecode(res.body)['detail']?.toString() ?? message;
        } catch (_) {}
        setState(() {
          _savingIdentity = false;
          _identityOk = false;
          _identityMessage = message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingIdentity = false;
        _identityOk = false;
        _identityMessage = 'Tidak bisa terhubung ke server.';
      });
    }
  }

  Future<void> _saveContactInfo() async {
    setState(() {
      _savingContact = true;
      _contactSaveMessage = null;
    });
    try {
      final res = await http.patch(
        Uri.parse('$_apiBase/users/${widget.username}/privacy'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'whatsapp_number': _whatsappCtrl.text.trim(),
          'address': _addressCtrl.text.trim(),
        }),
      );
      if (!mounted) return;
      setState(() {
        _savingContact = false;
        _contactSaveMessage = res.statusCode == 200 ? 'Tersimpan.' : 'Gagal menyimpan.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingContact = false;
        _contactSaveMessage = 'Tidak bisa terhubung ke server.';
      });
    }
  }

  Future<void> _changePassword() async {
    if (_oldPasswordCtrl.text.isEmpty || _newPasswordCtrl.text.isEmpty) {
      setState(() => _passwordMessage = 'Isi password lama dan baru.');
      return;
    }
    setState(() {
      _changingPassword = true;
      _passwordMessage = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/users/${widget.username}/change-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'old_password': _oldPasswordCtrl.text, 'new_password': _newPasswordCtrl.text}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _changingPassword = false;
          _passwordMessage = 'Password berhasil diganti.';
          _oldPasswordCtrl.clear();
          _newPasswordCtrl.clear();
        });
      } else {
        String message = 'Gagal mengganti password.';
        try {
          message = jsonDecode(res.body)['detail']?.toString() ?? message;
        } catch (_) {}
        setState(() {
          _changingPassword = false;
          _passwordMessage = message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _changingPassword = false;
        _passwordMessage = 'Tidak bisa terhubung ke server.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadProfile, child: const Text('Coba lagi')),
          ],
        ),
      );
    }
    return _buildForm();
  }

  Widget _buildForm() {
    final profile = _profile!;
    final photoUrl = profile['photo_url'] as String?;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return ListView(
      padding: widget.padding,
      children: [
        // ---- Foto ----
        Center(
          child: Column(
            children: [
              UserAvatar(photoUrl: photoUrl, radius: 44, version: _photoVersion),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _uploadingPhoto ? null : _pickAndUploadPhoto,
                icon: _uploadingPhoto
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_camera_outlined, size: 16),
                label: Text(hasPhoto ? 'Ganti Foto' : 'Unggah Foto'),
              ),
              const SizedBox(height: 4),
              Text(
                hasPhoto ? 'JPG, PNG, atau WEBP.' : 'Belum ada foto — JPG, PNG, atau WEBP.',
                style: YmTextStyles.statusMessage,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ---- Identitas ----
        _SectionLabel(_needsNickname || _needsGender
            ? 'Informasi Dasar (isi sekali, lalu terkunci)'
            : 'Informasi Dasar (terkunci)'),
        _LockedField(label: 'Username', value: '@${widget.username}'),
        if (_needsNickname) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _nicknameCtrl,
            maxLength: 24,
            enabled: !_savingIdentity,
            decoration: const InputDecoration(
              labelText: 'Nickname',
              helperText: 'Wajib dibuat sebelum bisa masuk room chat. Hanya bisa dibuat sekali.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ] else if (_editingNickname) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _nicknameCtrl,
            maxLength: 24,
            autofocus: true,
            enabled: !_savingIdentity,
            decoration: const InputDecoration(
              labelText: 'Nickname baru',
              helperText: 'Ini satu-satunya kesempatan ganti nickname.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _savingIdentity
                  ? null
                  : () => setState(() {
                        _editingNickname = false;
                        _nicknameCtrl.clear();
                        _identityMessage = null;
                      }),
              child: const Text('Batal ganti nickname'),
            ),
          ),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _LockedField(label: 'Nama / Nickname', value: _fullName)),
              if (_canChangeNickname)
                TextButton(
                  onPressed: () => setState(() {
                    _editingNickname = true;
                    _nicknameCtrl.text = _fullName;
                  }),
                  child: const Text('Ganti (1x)'),
                ),
            ],
          ),
        ],
        if (_needsGender) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 130, child: Text('Jenis Kelamin', style: YmTextStyles.label)),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Pria'),
                    selected: _pickedGender == 'male',
                    onSelected: _savingIdentity ? null : (_) => setState(() => _pickedGender = 'male'),
                  ),
                  ChoiceChip(
                    label: const Text('Wanita'),
                    selected: _pickedGender == 'female',
                    onSelected: _savingIdentity ? null : (_) => setState(() => _pickedGender = 'female'),
                  ),
                ],
              ),
            ],
          ),
        ] else
          _LockedField(label: 'Jenis Kelamin', value: _gender == 'male' ? 'Pria' : 'Wanita'),
        _LockedField(label: 'Email', value: profile['email'] ?? '-'),
        if (_needsNickname || _needsGender || _editingNickname) ...[
          const SizedBox(height: 8),
          if (_identityMessage != null)
            Text(_identityMessage!, style: TextStyle(fontSize: 12, color: _identityOk ? Colors.green : Colors.red)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton(
              onPressed: _savingIdentity ? null : _saveIdentity,
              style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
              child: _savingIdentity
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text((_needsNickname || _editingNickname) ? 'Simpan Nickname' : 'Simpan'),
            ),
          ),
        ] else if (_identityMessage != null) ...[
          const SizedBox(height: 8),
          Text(_identityMessage!, style: TextStyle(fontSize: 12, color: _identityOk ? Colors.green : Colors.red)),
        ],

        // ---- Kontak ----
        const SizedBox(height: 24),
        _SectionLabel('Info Kontak (bisa diubah kapan saja)'),
        TextField(
          controller: _whatsappCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Nomor WhatsApp', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressCtrl,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Alamat', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 8),
        if (_contactSaveMessage != null)
          Text(_contactSaveMessage!, style: TextStyle(fontSize: 12, color: _contactSaveMessage == 'Tersimpan.' ? Colors.green : Colors.red)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton(
            onPressed: _savingContact ? null : _saveContactInfo,
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            child: _savingContact
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Simpan Info Kontak'),
          ),
        ),

        // ---- Password ----
        const SizedBox(height: 24),
        _SectionLabel('Ganti Password'),
        TextField(
          controller: _oldPasswordCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password Lama', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPasswordCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password Baru (min. 6 karakter)', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 8),
        if (_passwordMessage != null)
          Text(_passwordMessage!, style: TextStyle(fontSize: 12, color: _passwordMessage == 'Password berhasil diganti.' ? Colors.green : Colors.red)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton(
            onPressed: _changingPassword ? null : _changePassword,
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.buzzRed, foregroundColor: Colors.white),
            child: _changingPassword
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Ganti Password'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: YmTextStyles.username.copyWith(fontSize: 13)),
    );
  }
}

class _LockedField extends StatelessWidget {
  final String label;
  final String value;
  const _LockedField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: YmTextStyles.label)),
          Expanded(child: Text(value, style: YmTextStyles.chatText)),
          const Icon(Icons.lock_outline, size: 14, color: YmColors.textMuted),
        ],
      ),
    );
  }
}
