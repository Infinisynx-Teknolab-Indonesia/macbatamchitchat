import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Hasil satu langkah reset password.
class PasswordResetResult {
  final bool success;
  final String? errorMessage;
  const PasswordResetResult({required this.success, this.errorMessage});
}

/// Lupa password lewat email + kode OTP (endpoint di backend: app/password_reset.py).
class PasswordResetService {
  /// Langkah 1: minta kode dikirim ke email. Respons backend SELALU sukses untuk
  /// email apa pun (agar tidak membocorkan email mana yang terdaftar).
  Future<PasswordResetResult> requestCode(String email) =>
      _post('/auth/forgot-password/request', {'email': email});

  /// Langkah 2: kirim kode + password baru.
  Future<PasswordResetResult> confirm({
    required String email,
    required String otp,
    required String newPassword,
  }) =>
      _post('/auth/forgot-password/confirm', {
        'email': email,
        'otp': otp,
        'new_password': newPassword,
      });

  Future<PasswordResetResult> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return const PasswordResetResult(success: true);
      return PasswordResetResult(success: false, errorMessage: _detail(res));
    } catch (_) {
      return const PasswordResetResult(
        success: false,
        errorMessage: 'Tidak bisa terhubung ke server. Coba lagi.',
      );
    }
  }

  String _detail(http.Response res) {
    try {
      final detail = jsonDecode(res.body)['detail'];
      if (detail is String) return detail;
    } catch (_) {}
    return 'Terjadi kesalahan (${res.statusCode}).';
  }
}
