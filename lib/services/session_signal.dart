import 'dart:async';
import 'dart:io';

/// Sinyal "logout" lintas-window lewat satu file kecil di folder temp.
///
/// Semua window aplikasi berjalan di SATU proses dan SATU PC, jadi file ini bisa dibaca oleh semua
/// window tanpa plugin apa pun dan tanpa pesan antar-window (desktop_multi_window). Dipakai sebagai
/// jalur penutupan yang tidak bisa "putus" ketika Logout: window utama menulis waktu logout,
/// setiap sub-window (private chat, room chat, daftar room, settings) memeriksanya tiap detik dan
/// menutup dirinya sendiri kalau ada logout SETELAH window itu dibuat.
class SessionSignal {
  static File get _file =>
      File('${Directory.systemTemp.path}${Platform.pathSeparator}batam_chitchat_logout.txt');

  /// Dipanggil window utama saat Logout.
  static Future<void> markLoggedOut() async {
    try {
      await _file.writeAsString(DateTime.now().millisecondsSinceEpoch.toString(), flush: true);
    } catch (e) {
      // ignore: avoid_print
      print('[SessionSignal] gagal menulis sinyal logout: $e');
    }
  }

  /// Dipanggil di setiap SUB-window saat dibuat. [onLogout] dijalankan satu kali kalau ada
  /// logout setelah window ini dibuat. Window yang dibuat SESUDAH logout (login berikutnya) tidak
  /// terpengaruh, karena waktu buatnya lebih baru daripada waktu logout.
  static Timer watch(Future<void> Function() onLogout) {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    var fired = false;
    return Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (fired) return;
      try {
        final file = _file;
        if (!await file.exists()) return;
        final loggedOutAt = int.tryParse((await file.readAsString()).trim()) ?? 0;
        if (loggedOutAt > startedAt) {
          fired = true;
          timer.cancel();
          await onLogout();
        }
      } catch (_) {
        // membaca file gagal sesaat (mis. sedang ditulis): coba lagi di detik berikutnya
      }
    });
  }
}
