import 'dart:convert';
import '../config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import '../theme/ym_theme.dart';
import '../widgets/retro_title_bar.dart';
import '../widgets/profile_panel.dart';

const _apiBase = AppConfig.apiBaseUrl;

enum _SettingsTab { profile, general, alerts, privacy, blocked, archive, about }

/// Preferences window: left-side tab navigation, detail panel on the right.
/// Mirrors the classic "General / Alerts & Sounds / Privacy / Archive" layout,
/// plus a Blocked Users tab.
class SettingsScreen extends StatefulWidget {
  final String username;
  const SettingsScreen({super.key, required this.username});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsTab _tab = _SettingsTab.profile;

  // Local UI state — wire these up to real persisted settings later.
  bool _launchOnStartup = true;
  bool _soundOnNewMessage = true;
  bool _soundOnBuzz = true;
  bool _soundOnLogin = false;

  bool _onlyContactsCanMessage = true;
  bool _showOnlineStatus = true;
  bool _showEmailToOthers = false;       // NEW: email visibility
  bool _hideBirthdate = true;            // NEW: birthdate hidden by default
  bool _showWhatsappToOthers = false;    // default disembunyikan
  bool _showAddressToOthers = false;     // default disembunyikan
  bool _speakerEnabled = false;          // "I have speakers on, can hear room music" — shown as a headphone icon in rooms

  bool _saveMessageHistory = true;

  List<String> _blockedUsers = [];
  bool _loadingBlocked = false;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
    _loadPrivacySettings();
    _configureWindowSize();
  }

  Future<void> _configureWindowSize() async {
    try {
      await windowManager.setMinimumSize(const Size(760, 560));
      await windowManager.setResizable(true);
    } catch (e) {
      // ignore: avoid_print
      print('[Settings] window_manager unavailable (native patch from NATIVE_SETUP.md not applied?): $e');
    }
  }

  Future<void> _loadPrivacySettings() async {
    try {
      final res = await http.get(Uri.parse('$_apiBase/users/${widget.username}/profile').replace(
        queryParameters: {'viewer': widget.username}, // self-view, so raw flags are included
      ));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _showEmailToOthers = data['show_email_publicly'] ?? false;
          _hideBirthdate = !(data['show_birthdate_publicly'] ?? false);
          _showWhatsappToOthers = data['show_whatsapp_publicly'] ?? false;
          _showAddressToOthers = data['show_address_publicly'] ?? false;
          _showOnlineStatus = data['show_online_status_publicly'] ?? true;
          _speakerEnabled = data['has_speaker_enabled'] ?? false;
        });
      }
    } catch (_) {
      // best-effort — keep local defaults if backend unreachable
    }
  }

  Future<void> _updatePrivacy({
    bool? showEmail,
    bool? hideBirthdate,
    bool? speakerEnabled,
    bool? showWhatsapp,
    bool? showAddress,
    bool? showOnlineStatus,
  }) async {
    try {
      await http.patch(
        Uri.parse('$_apiBase/users/${widget.username}/privacy'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (showEmail != null) 'show_email_publicly': showEmail,
          if (hideBirthdate != null) 'show_birthdate_publicly': !hideBirthdate,
          if (speakerEnabled != null) 'has_speaker_enabled': speakerEnabled,
          if (showWhatsapp != null) 'show_whatsapp_publicly': showWhatsapp,
          if (showAddress != null) 'show_address_publicly': showAddress,
          if (showOnlineStatus != null) 'show_online_status_publicly': showOnlineStatus,
        }),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menyimpan pengaturan.')),
        );
      }
    }
  }

  Future<void> _loadBlockedUsers() async {
    setState(() => _loadingBlocked = true);
    try {
      final res = await http.get(Uri.parse('$_apiBase/users/${widget.username}/blocked'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _blockedUsers = List<String>.from(data['blocked']));
      }
    } catch (_) {
      // best-effort — leave list empty if backend unreachable
    }
    setState(() => _loadingBlocked = false);
  }

  Future<void> _unblock(String username) async {
    try {
      await http.delete(
        Uri.parse('$_apiBase/block'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'blocker_username': widget.username, 'blocked_username': username}),
      );
      setState(() => _blockedUsers.remove(username));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal unblock, coba lagi.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const RetroTitleBar(title: 'Pengaturan', icon: Icons.settings_outlined),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 170,
                  color: YmColors.panelBackground,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _NavItem(label: 'Profil', icon: Icons.person_outline, selected: _tab == _SettingsTab.profile,
                          onTap: () => setState(() => _tab = _SettingsTab.profile)),
                      _NavItem(label: 'Umum', icon: Icons.tune, selected: _tab == _SettingsTab.general,
                          onTap: () => setState(() => _tab = _SettingsTab.general)),
                      _NavItem(label: 'Suara & Notifikasi', icon: Icons.notifications_outlined, selected: _tab == _SettingsTab.alerts,
                          onTap: () => setState(() => _tab = _SettingsTab.alerts)),
                      _NavItem(label: 'Privasi', icon: Icons.lock_outline, selected: _tab == _SettingsTab.privacy,
                          onTap: () => setState(() => _tab = _SettingsTab.privacy)),
                      _NavItem(label: 'Daftar Blokir', icon: Icons.block, selected: _tab == _SettingsTab.blocked,
                          onTap: () => setState(() => _tab = _SettingsTab.blocked)),
                      _NavItem(label: 'Arsip Chat', icon: Icons.archive_outlined, selected: _tab == _SettingsTab.archive,
                          onTap: () => setState(() => _tab = _SettingsTab.archive)),
                      _NavItem(label: 'Tentang', icon: Icons.info_outline, selected: _tab == _SettingsTab.about,
                          onTap: () => setState(() => _tab = _SettingsTab.about)),
                    ],
                  ),
                ),
                Container(width: 1, color: YmColors.borderLavender.withOpacity(0.5)),
                Expanded(
                  child: Container(
                    color: YmColors.contentBackground,
                    padding: const EdgeInsets.all(20),
                    child: _buildPanel(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    switch (_tab) {
      case _SettingsTab.profile:
        // The Settings container already pads 20px around the panel.
        return ProfilePanel(username: widget.username, padding: EdgeInsets.zero);

      case _SettingsTab.general:
        return _SettingsSection(title: 'Umum', children: [
          _SettingsSwitch(
            label: 'Jalankan Batam ChitChat saat komputer nyala',
            value: _launchOnStartup,
            onChanged: (v) => setState(() => _launchOnStartup = v),
          ),
          _SettingsSwitch(
            label: 'Speaker aktif (bisa dengar musik di room)',
            value: _speakerEnabled,
            onChanged: (v) {
              setState(() => _speakerEnabled = v);
              _updatePrivacy(speakerEnabled: v);
            },
          ),
        ]);

      case _SettingsTab.alerts:
        return _SettingsSection(title: 'Suara & Notifikasi', children: [
          _SettingsSwitch(label: 'Bunyi saat pesan baru masuk', value: _soundOnNewMessage,
              onChanged: (v) => setState(() => _soundOnNewMessage = v)),
          _SettingsSwitch(label: 'Bunyi saat menerima Buzz', value: _soundOnBuzz,
              onChanged: (v) => setState(() => _soundOnBuzz = v)),
          _SettingsSwitch(label: 'Bunyi saat teman login', value: _soundOnLogin,
              onChanged: (v) => setState(() => _soundOnLogin = v)),
        ]);

      case _SettingsTab.privacy:
        return _SettingsSection(title: 'Privasi', children: [
          _SettingsSwitch(
            label: 'Hanya kontak tersimpan yang bisa kirim pesan ke saya',
            value: _onlyContactsCanMessage,
            onChanged: (v) => setState(() => _onlyContactsCanMessage = v),
          ),
          _SettingsSwitch(
            label: 'Tampilkan status online saya ke orang lain',
            value: _showOnlineStatus,
            onChanged: (v) {
              setState(() => _showOnlineStatus = v);
              _updatePrivacy(showOnlineStatus: v);
            },
          ),
          _SettingsSwitch(
            label: 'Izinkan orang lain melihat email saya',
            value: _showEmailToOthers,
            onChanged: (v) {
              setState(() => _showEmailToOthers = v);
              _updatePrivacy(showEmail: v);
            },
          ),
          _SettingsSwitch(
            label: 'Sembunyikan tanggal lahir saya dari orang lain',
            value: _hideBirthdate,
            onChanged: (v) {
              setState(() => _hideBirthdate = v);
              _updatePrivacy(hideBirthdate: v);
            },
          ),
          _SettingsSwitch(
            label: 'Izinkan orang lain melihat nomor WhatsApp saya',
            value: _showWhatsappToOthers,
            onChanged: (v) {
              setState(() => _showWhatsappToOthers = v);
              _updatePrivacy(showWhatsapp: v);
            },
          ),
          _SettingsSwitch(
            label: 'Izinkan orang lain melihat alamat saya',
            value: _showAddressToOthers,
            onChanged: (v) {
              setState(() => _showAddressToOthers = v);
              _updatePrivacy(showAddress: v);
            },
          ),
        ]);

      case _SettingsTab.blocked:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daftar Blokir', style: YmTextStyles.username.copyWith(fontSize: 14)),
            const Divider(height: 24, color: YmColors.borderLavender),
            if (_loadingBlocked)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (_blockedUsers.isEmpty)
              Text('Belum ada yang kamu blokir.', style: YmTextStyles.statusMessage)
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _blockedUsers.length,
                  itemBuilder: (context, i) {
                    final username = _blockedUsers[i];
                    return ListTile(
                      leading: const Icon(Icons.block, color: YmColors.buzzRed, size: 20),
                      title: Text('@$username', style: YmTextStyles.buddyName),
                      trailing: TextButton(
                        onPressed: () => _unblock(username),
                        child: const Text('Unblock'),
                      ),
                    );
                  },
                ),
              ),
          ],
        );

      case _SettingsTab.archive:
        return _SettingsSection(title: 'Arsip Chat', children: [
          _SettingsSwitch(
            label: 'Simpan riwayat pesan saya secara otomatis',
            value: _saveMessageHistory,
            onChanged: (v) => setState(() => _saveMessageHistory = v),
          ),
          const SizedBox(height: 12),
          Text(
            'Riwayat chat yang tersimpan bisa dilihat lewat menu Arsip Percakapan '
            'di jendela utama.',
            style: YmTextStyles.statusMessage,
          ),
        ]);

      case _SettingsTab.about:
        return ListView(
          children: [
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 56, height: 56,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [YmColors.titleBarStart, YmColors.titleBarEnd]),
                    ),
                    child: const Icon(Icons.forum_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 10),
                  Text('Batam ChitChat', style: YmTextStyles.username.copyWith(fontSize: 15)),
                  Text('Versi 1.0.0', style: YmTextStyles.statusMessage),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: YmColors.borderLavender),
            const SizedBox(height: 16),
            Text(
              'Tentang Batam ChitChat',
              style: YmTextStyles.username.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Batam ChitChat adalah aplikasi chat lokal untuk warga Batam — ngobrol '
              'berdasarkan kecamatan, cari teman baru, dan gabung ke room sesuai minat.',
              style: YmTextStyles.chatText,
            ),
            const SizedBox(height: 16),
            Text(
              'Didukung oleh FJB Batam',
              style: YmTextStyles.username.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Aplikasi ini disediakan GRATIS untuk warga Batam, didukung oleh FJB Batam — '
              'komunitas jual-beli online terbesar untuk warga Batam. Batam ChitChat hadir '
              'sebagai wadah ngobrol santai di luar urusan jual-beli, tetap dari komunitas '
              'yang sama.',
              style: YmTextStyles.chatText,
            ),
            const SizedBox(height: 20),
          ],
        );
    }
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? YmColors.accentPurple.withOpacity(0.15) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? YmColors.accentPurple : YmColors.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: YmTextStyles.buddyName)),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: YmTextStyles.username.copyWith(fontSize: 14)),
        const Divider(height: 24, color: YmColors.borderLavender),
        ...children,
      ],
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingsSwitch({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: YmTextStyles.chatText)),
          Switch(value: value, onChanged: onChanged, activeColor: YmColors.accentPurple),
        ],
      ),
    );
  }
}
