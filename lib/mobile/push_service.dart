import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'chat_hub.dart';
import 'mobile_api.dart';
import 'mobile_config.dart';

/// Notifikasi push (Firebase Cloud Messaging) untuk saat aplikasi di latar belakang atau DITUTUP.
///
/// FIREBASE BOLEH BELUM ADA. Aplikasi berfungsi penuh tanpanya (banner + suara + getar + angka belum dibaca
/// saat aplikasi terbuka). Push baru menyala kalau SEMUA ini terpenuhi:
///   1. google-services.json terpasang di aplikasi (initCore berhasil),
///   2. admin sudah mengisi kredensial Firebase DAN saklarnya AKTIF (admin panel > Integrasi),
///   3. pengguna mengizinkan notifikasi.
/// Selama saklar admin MATI atau Firebase belum dibuat, aplikasi TIDAK meminta izin notifikasi dan tidak
/// mendaftarkan perangkat. Saat admin menghidupkannya, aplikasi mengikutinya begitu dibuka kembali.
///
/// Saat aplikasi TERBUKA, banner dalam-aplikasi (mobile_notifier.dart) yang dipakai, jadi push di foreground
/// sengaja tidak ditampilkan lagi. Saluran notifikasi ("messages" / "buzz", dengan suara masing-masing) dibuat di
/// MainActivity oleh siapkan_android.py.
class PushService {
  static bool _firebaseReady = false;
  static bool _registered = false;
  static bool _busy = false;
  static String? _token;
  static StreamSubscription<String>? _tokenSub;
  static StreamSubscription<RemoteMessage>? _openSub;
  static StreamSubscription<RemoteMessage>? _foregroundSub;

  /// Ringkasan status untuk tab Profile (membantu mencari tahu kalau notifikasi tidak muncul).
  static final ValueNotifier<String> status =
      ValueNotifier<String>('Notifikasi saat aplikasi ditutup belum aktif. Aplikasi tetap berfungsi normal saat dibuka.');

  /// Dipanggil sekali di main(). Aman: tanpa google-services.json aplikasi tetap jalan (tanpa push).
  static Future<void> initCore() async {
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      _firebaseReady = false;
      status.value = 'Notifikasi saat aplikasi ditutup belum aktif: Firebase belum dipasang di aplikasi '
          '(google-services.json). Aplikasi tetap berfungsi normal saat dibuka.';
      debugPrint('[push] Firebase.initializeApp gagal (wajar kalau Firebase belum dibuat): $e');
    }
  }

  /// Dipanggil setelah login.
  static Future<void> start(String username) => refresh();

  /// Dipanggil setelah login DAN setiap aplikasi dibuka kembali: memuat konfigurasi terbaru dari server
  /// (saklar admin, iklan) lalu menyalakan push kalau sudah waktunya.
  static Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      await MobileConfig.instance.load();
      if (!_firebaseReady) return; // status sudah dijelaskan oleh initCore()
      if (!MobileConfig.instance.pushEnabled) {
        status.value = 'Notifikasi saat aplikasi ditutup dimatikan admin (Firebase belum diaktifkan). '
            'Aplikasi tetap berfungsi normal saat dibuka.';
        return;
      }
      if (_registered) {
        _updateStatus(true);
        return;
      }
      await _register();
    } catch (e) {
      status.value = 'Gagal mengaktifkan notifikasi: $e';
      debugPrint('[push] refresh gagal: $e');
    } finally {
      _busy = false;
    }
  }

  static Future<void> _register() async {
    final messaging = FirebaseMessaging.instance;

    // Android 13+ menampilkan dialog izin notifikasi di sini (hanya kalau push memang aktif di server).
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      status.value = 'Izin notifikasi ditolak. Aktifkan di Pengaturan HP > Aplikasi > Batam ChitChat > Notifikasi.';
      return;
    }

    final token = await messaging.getToken();
    if (token == null || token.isEmpty) {
      status.value = 'Tidak mendapat token dari Google (Google Play Services tidak tersedia?).';
      return;
    }
    _token = token;
    final ok = await MobileApi.registerDevice(token);
    _registered = ok;
    _updateStatus(ok);
    if (!ok) return; // dicoba lagi saat aplikasi dibuka kembali

    await _tokenSub?.cancel();
    _tokenSub = messaging.onTokenRefresh.listen((newToken) {
      _token = newToken;
      MobileApi.registerDevice(newToken);
    });

    // Ketuk notifikasi saat aplikasi di latar belakang -> buka chat pengirimnya.
    await _openSub?.cancel();
    _openSub = FirebaseMessaging.onMessageOpenedApp.listen(_openChatFrom);
    // Push yang tiba saat aplikasi terbuka: banner dalam-aplikasi sudah menangani; cukup segarkan angka belum dibaca.
    await _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen((_) => ChatHub.instance.refresh());

    // Ketuk notifikasi saat aplikasi DITUTUP -> aplikasi terbuka langsung ke chat pengirimnya.
    final initial = await messaging.getInitialMessage();
    if (initial != null) _openChatFrom(initial);
  }

  static void _updateStatus(bool registered) {
    final appProject = Firebase.app().options.projectId;
    final serverProject = MobileConfig.instance.firebaseProjectId;
    if (!registered) {
      status.value = 'Gagal mendaftarkan perangkat ke server. Periksa koneksi lalu buka ulang aplikasi.';
    } else if (serverProject != null && serverProject != appProject) {
      status.value = 'Project Firebase BERBEDA: aplikasi memakai "$appProject", server memakai "$serverProject". '
          'Samakan keduanya (admin panel > Integrasi).';
    } else {
      status.value = 'Aktif (project $appProject). Notifikasi tetap muncul saat aplikasi ditutup.';
    }
  }

  static void _openChatFrom(RemoteMessage message) {
    final peer = message.data['from_username'];
    if (peer is String && peer.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ChatHub.instance.openChat?.call(peer));
    }
  }

  /// Dipanggil sebelum logout (masih butuh token sesi): berhenti menerima notifikasi untuk akun ini.
  static Future<void> stop() async {
    await _tokenSub?.cancel();
    await _openSub?.cancel();
    await _foregroundSub?.cancel();
    _tokenSub = _openSub = _foregroundSub = null;
    final token = _token;
    _token = null;
    _registered = false;
    if (token != null) {
      await MobileApi.unregisterDevice(token);
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
  }
}
