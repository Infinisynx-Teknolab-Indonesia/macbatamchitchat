import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/ym_theme.dart';
import '../widgets/retro_title_bar.dart';
import '../services/secure_storage_service.dart';
import 'login_screen.dart';

/// Shown ONCE on first launch, right after the installer finishes.
/// This is the app-level counterpart to the installer's system-level
/// prerequisite check (VC++ Redist, firewall rule) — here we request the
/// OS-level *permissions* the app needs to work fully:
///   - Location: to suggest the closest city room automatically
///   - Notifications: so chat/buzz alerts show up while the app is minimized
///
/// These can't be "installed" ahead of time like a DLL — the OS requires
/// the user to grant them interactively, so we ask clearly and explain why.
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

enum _SetupStep { welcome, location, notifications, done }

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  _SetupStep _step = _SetupStep.welcome;
  bool _locationGranted = false;
  bool _notificationsGranted = false;
  bool _busy = false;

  Future<void> _requestLocation() async {
    setState(() => _busy = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location services turned off at the OS level entirely.
        await Geolocator.openLocationSettings();
      }
      final permission = await Geolocator.requestPermission();
      _locationGranted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      _locationGranted = false;
    }
    setState(() {
      _busy = false;
      _step = _SetupStep.notifications;
    });
  }

  Future<void> _requestNotifications() async {
    setState(() => _busy = true);
    try {
      final status = await Permission.notification.request();
      _notificationsGranted = status.isGranted;
    } catch (_) {
      _notificationsGranted = false;
    }
    setState(() {
      _busy = false;
      _step = _SetupStep.done;
    });
  }

  Future<void> _finishSetup() async {
    // Persist that first-run setup is complete so we never show this wizard again.
    await SecureStorageService().markFirstRunSetupComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const RetroTitleBar(title: 'Batam ChitChat — Pengaturan Awal', icon: Icons.settings_suggest),
          Expanded(
            child: Container(
              color: YmColors.panelBackground,
              child: Center(
                child: Container(
                  width: 420,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: YmColors.contentBackground,
                    borderRadius: BorderRadius.circular(ymBorderRadius),
                    border: Border.all(color: YmColors.borderLavender),
                  ),
                  child: _buildStepContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _SetupStep.welcome:
        return _StepScaffold(
          icon: Icons.waving_hand_rounded,
          title: 'Selamat datang di Batam ChitChat!',
          description:
              'Sebelum mulai, kami perlu mengatur beberapa izin supaya semua fitur '
              '(deteksi kota otomatis & notifikasi chat/buzz) berjalan dengan baik. '
              'Ini cuma dilakukan sekali di awal.',
          buttonLabel: 'Mulai Pengaturan',
          onPressed: () => setState(() => _step = _SetupStep.location),
        );

      case _SetupStep.location:
        return _StepScaffold(
          icon: Icons.location_on_rounded,
          title: 'Izin Lokasi',
          description:
              'Dipakai untuk menyarankan room kota terdekat dengan kamu secara otomatis. '
              'Kamu tetap bisa pilih kota manapun secara manual kalau lebih suka.',
          buttonLabel: _busy ? 'Memproses...' : 'Izinkan Lokasi',
          onPressed: _busy ? null : _requestLocation,
          secondaryLabel: 'Lewati',
          onSecondaryPressed: _busy
              ? null
              : () => setState(() => _step = _SetupStep.notifications),
        );

      case _SetupStep.notifications:
        return _StepScaffold(
          icon: Icons.notifications_active_rounded,
          title: 'Izin Notifikasi',
          description:
              'Dipakai supaya kamu tetap dapat notifikasi pesan baru dan "Buzz" dari '
              'teman meskipun aplikasi sedang diminimize.',
          buttonLabel: _busy ? 'Memproses...' : 'Izinkan Notifikasi',
          onPressed: _busy ? null : _requestNotifications,
          secondaryLabel: 'Lewati',
          onSecondaryPressed: _busy ? null : () => setState(() => _step = _SetupStep.done),
        );

      case _SetupStep.done:
        return _StepScaffold(
          icon: Icons.check_circle_rounded,
          iconColor: Colors.green,
          title: 'Semua siap!',
          description:
              'Lokasi: ${_locationGranted ? "Diizinkan" : "Dilewati"}\n'
              'Notifikasi: ${_notificationsGranted ? "Diizinkan" : "Dilewati"}\n\n'
              'Kamu bisa ubah izin ini kapan saja lewat pengaturan sistem.',
          buttonLabel: 'Lanjut ke Sign In',
          onPressed: _finishSetup,
        );
    }
  }
}

class _StepScaffold extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  const _StepScaffold({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: iconColor ?? YmColors.accentPurple),
        const SizedBox(height: 16),
        Text(title, style: YmTextStyles.username.copyWith(fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(description, style: YmTextStyles.chatText, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: YmColors.accentPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ymBorderRadius)),
            ),
            child: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        if (secondaryLabel != null) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: onSecondaryPressed,
            child: Text(secondaryLabel!, style: YmTextStyles.label),
          ),
        ],
      ],
    );
  }
}
