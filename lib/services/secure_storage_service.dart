import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage so credentials/session tokens are kept in
/// the OS-level secure store (Keychain on macOS, Credential Locker on
/// Windows, libsecret on Linux) instead of plaintext files or SharedPreferences.
///
/// SECURITY NOTE: never store the raw password after login. Store only a
/// short-lived session token issued by the backend, and refresh it via a
/// proper auth flow (e.g. JWT refresh token) rather than keeping the
/// password around at all.
class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const _keySessionToken = 'session_token';
  static const _keyUsername = 'username';
  static const _keyFcmToken = 'fcm_token';
  static const _keySetupComplete = 'first_run_setup_complete';
  static const _keyRememberedUsername = 'remembered_username';
  static const _keyRememberedPassword = 'remembered_password';

  Future<void> saveSession({required String token, required String username}) async {
    await _storage.write(key: _keySessionToken, value: token);
    await _storage.write(key: _keyUsername, value: username);
  }

  Future<String?> getSessionToken() => _storage.read(key: _keySessionToken);
  Future<String?> getUsername() => _storage.read(key: _keyUsername);

  Future<void> saveFcmToken(String token) => _storage.write(key: _keyFcmToken, value: token);
  Future<String?> getFcmToken() => _storage.read(key: _keyFcmToken);

  /// "Remember me" — stored in flutter_secure_storage (OS-level Credential
  /// Locker on Windows, not a plaintext file), same tradeoff browsers make
  /// for saved passwords. This is what makes the login screen able to
  /// pre-fill both fields on next launch, INCLUDING after an explicit
  /// logout — logout only clears the session token (see clearSession
  /// below), not these, precisely so "remember me" survives a logout.
  Future<void> saveRememberedCredentials({required String username, required String password}) async {
    await _storage.write(key: _keyRememberedUsername, value: username);
    await _storage.write(key: _keyRememberedPassword, value: password);
  }

  Future<Map<String, String>?> getRememberedCredentials() async {
    final username = await _storage.read(key: _keyRememberedUsername);
    final password = await _storage.read(key: _keyRememberedPassword);
    if (username == null || password == null) return null;
    return {'username': username, 'password': password};
  }

  Future<void> clearRememberedCredentials() async {
    await _storage.delete(key: _keyRememberedUsername);
    await _storage.delete(key: _keyRememberedPassword);
  }

  /// Logout only clears the SESSION (so the server treats you as logged
  /// out) — it deliberately does NOT touch remembered credentials, so
  /// "remember me" survives a logout instead of being wiped by it.
  Future<void> clearSession() async {
    await _storage.delete(key: _keySessionToken);
    await _storage.delete(key: _keyUsername);
  }

  /// Whether the first-run permission wizard (location/notifications) has
  /// already been shown, so we never show it again on later launches.
  Future<bool> hasCompletedFirstRunSetup() async {
    final value = await _storage.read(key: _keySetupComplete);
    return value == 'true';
  }

  Future<void> markFirstRunSetupComplete() async {
    await _storage.write(key: _keySetupComplete, value: 'true');
  }
}
