import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_config.dart';
import 'auth_config.dart';
import 'oauth_loopback_helper.dart';
import 'secure_storage_service.dart';

class AuthResult {
  final bool success;
  final String? sessionToken;
  final String? errorMessage;
  final bool profileComplete;
  final bool requiresUpdate;
  const AuthResult({required this.success, this.sessionToken, this.errorMessage, this.profileComplete = true, this.requiresUpdate = false});
}

/// Central place for all login methods. UI (login_screen.dart) should only
/// ever talk to this class, never build auth URLs or call the backend
/// directly — that keeps every provider's quirks in one place.
class AuthService {
  final String backendBaseUrl;
  final SecureStorageService _storage = SecureStorageService();

  AuthService({this.backendBaseUrl = AppConfig.serverBaseUrl});

  /// Fetches which login methods + keys are currently turned on.
  /// This is the hook the future admin panel controls: it edits config on
  /// the backend, and every client picks up the change next time this runs
  /// (e.g. on app start / login screen open) — no app update needed.
  Future<AuthConfig> fetchAuthConfig() async {
    try {
      final res = await http
          .get(Uri.parse('$backendBaseUrl/api/auth/config'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return AuthConfig.fromJson(jsonDecode(res.body));
      }
    } catch (_) {
      // Network/backend not reachable — fall through to the safe default.
    }
    return AuthConfig.disabled;
  }

  // ---------------------------------------------------------------------
  // Username & password
  // ---------------------------------------------------------------------

  Future<AuthResult> loginWithPassword({
    required String username,
    required String password,
    String? captchaToken,
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final res = await http.post(
        Uri.parse('$backendBaseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'app_version': packageInfo.version,
          if (captchaToken != null) 'captcha_token': captchaToken,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final token = data['token'] as String;
        await _storage.saveSession(token: token, username: username);
        return AuthResult(success: true, sessionToken: token, profileComplete: data['profile_complete'] ?? true);
      }
      if (res.statusCode == 426) {
        // Server says our version is too old — surface this distinctly
        // so the login screen can show "please update" instead of a
        // generic "wrong password" style error.
        return AuthResult(success: false, errorMessage: _extractError(res), requiresUpdate: true);
      }
      return AuthResult(success: false, errorMessage: _extractError(res));
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Tidak bisa terhubung ke server: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Google OAuth (desktop loopback flow — see oauth_loopback_helper.dart)
  // ---------------------------------------------------------------------

  Future<AuthResult> loginWithGoogle(AuthConfig config) async {
    if (!config.googleLoginEnabled || config.googleClientId == null) {
      return const AuthResult(success: false, errorMessage: 'Login Google belum diaktifkan admin.');
    }
    try {
      final code = await OAuthLoopbackHelper.authorizeAndGetCode(
        authorizationUrlBuilder: (redirectUri) => Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
          'client_id': config.googleClientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': 'openid email profile',
          'access_type': 'offline',
        }),
      );

      // IMPORTANT: the authorization code is exchanged for tokens on the
      // BACKEND, not here — that's where the Google client *secret* lives.
      // Never embed the client secret in the desktop app itself.
      final res = await http.post(
        Uri.parse('$backendBaseUrl/api/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await _storage.saveSession(token: data['token'], username: data['username']);
        return AuthResult(success: true, sessionToken: data['token'], profileComplete: data['profile_complete'] ?? false);
      }
      return AuthResult(success: false, errorMessage: _extractError(res));
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Login Google gagal: $e');
    }
  }

  // ---------------------------------------------------------------------
  // FJB Batam login
  // ---------------------------------------------------------------------
  // Login FJB Batam memakai OAuth 2.0 (Authorization Code + PKCE) ke fjbbatam.com/oauth.
  Future<AuthResult> loginWithFjbBatam(AuthConfig config) async {
    if (!config.fjbBatamLoginEnabled || config.fjbBatamAuthUrl == null || config.fjbBatamClientId == null) {
      return const AuthResult(success: false, errorMessage: 'Login FJB Batam belum diaktifkan admin.');
    }
    try {
      // OAuth 2.0 Authorization Code + PKCE lewat browser sistem (loopback 127.0.0.1).
      // client_secret TIDAK ada di aplikasi: penukaran code dilakukan backend kita.
      final pkce = await OAuthLoopbackHelper.authorizeWithPkce(
        authorizationUrlBuilder: (redirectUri, state, challenge) => Uri.parse(config.fjbBatamAuthUrl!).replace(
          queryParameters: {
            'response_type': 'code',
            'client_id': config.fjbBatamClientId!,
            'redirect_uri': redirectUri,
            'scope': 'profile email',
            'state': state,
            'code_challenge': challenge,
            'code_challenge_method': 'S256',
          },
        ),
      );
      final res = await http.post(
        Uri.parse('$backendBaseUrl/api/auth/fjbbatam'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': pkce.code,
          'redirect_uri': pkce.redirectUri,
          'code_verifier': pkce.codeVerifier,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await _storage.saveSession(token: data['token'], username: data['username']);
        return AuthResult(success: true, sessionToken: data['token'], profileComplete: data['profile_complete'] ?? false);
      }
      return AuthResult(success: false, errorMessage: _extractError(res));
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Login FJB Batam gagal: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Captcha (see README for the desktop-vs-reCAPTCHA-v3 limitation)
  // ---------------------------------------------------------------------

  /// Returns a captcha token to attach to loginWithPassword, or null if
  /// captcha is disabled in config. Actual token generation needs a
  /// webview (see README "Soal reCAPTCHA v3 di Desktop") — until that's
  /// wired in, this is an explicit TODO rather than a fake/mock token, so
  /// nobody mistakes a placeholder for a real security check.
  Future<String?> getCaptchaToken(AuthConfig config) async {
    if (!config.captchaEnabled) return null;
    throw UnimplementedError(
      'Captcha diaktifkan di config tapi widget captcha-nya belum dipasang. '
      'Lihat README bagian reCAPTCHA v3 untuk 2 opsi implementasinya.',
    );
  }

  String _extractError(http.Response res) {
    try {
      return jsonDecode(res.body)['detail'] ?? 'Login gagal (${res.statusCode})';
    } catch (_) {
      return 'Login gagal (${res.statusCode})';
    }
  }
}
