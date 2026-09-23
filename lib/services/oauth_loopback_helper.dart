import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hasil login OAuth dengan PKCE: `code` dari browser + data yang dibutuhkan
/// backend untuk menukarnya (redirect_uri persis yang dipakai, dan verifier PKCE).
class OAuthPkceResult {
  final String code;
  final String redirectUri;
  final String codeVerifier;
  const OAuthPkceResult({required this.code, required this.redirectUri, required this.codeVerifier});
}

/// Desktop apps can't receive an OAuth redirect the way a website does, so
/// the standard pattern (used by Google's own CLI tools, GitHub CLI, etc.)
/// is a "loopback" flow:
///   1. Start a tiny local HTTP server on 127.0.0.1 with a random free port.
///   2. Open the system browser to the provider's login/consent page, with
///      redirect_uri pointing back at that local server.
///   3. User logs in in their normal browser (safer than embedding a
///      password field inside our own app — the provider's real login page
///      is the one asking for the password, not us).
///   4. The provider redirects the browser back to
///      http://127.0.0.1:PORT/callback?code=..., our local server captures
///      that request, and we exchange the code for tokens server-side.
///
/// This same helper works for Google OAuth and, once FJB Batam exposes an
/// OAuth authorize endpoint, for FJB Batam login too — just point
/// [authorizationUrl] at whichever provider.
class OAuthLoopbackHelper {
  /// Opens [authorizationUrlBuilder] (given the loopback redirect URI it
  /// should use) in the system browser, waits for the redirect, and
  /// returns the `code` query parameter. Throws on timeout or if the
  /// browser can't be opened.
  static Future<String> authorizeAndGetCode({
    required Uri Function(String redirectUri) authorizationUrlBuilder,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/callback';

    final authUrl = authorizationUrlBuilder(redirectUri);
    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      await server.close(force: true);
      throw Exception('Tidak bisa membuka browser untuk login.');
    }

    try {
      final request = await server.first.timeout(timeout);
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_responseHtml(success: error == null));
      await request.response.close();

      if (error != null || code == null) {
        throw Exception('Login dibatalkan atau gagal: ${error ?? "kode tidak ditemukan"}');
      }
      return code;
    } finally {
      await server.close(force: true);
    }
  }

  static String _randomUrlSafe(int byteCount) {
    final rnd = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Sama seperti [authorizeAndGetCode], tetapi aman untuk "Login dengan FJBBATAM":
  ///  - membuat `state` acak dan MEMERIKSA-nya saat browser kembali (anti-CSRF),
  ///  - membuat PKCE (code_verifier + code_challenge S256). Verifier tidak pernah
  ///    dikirim ke browser; hanya challenge-nya. Verifier baru dikirim ke backend
  ///    kita untuk menukar `code`.
  ///  - hanya menerima request ke /callback (request lain, mis. /favicon.ico, diabaikan).
  static Future<OAuthPkceResult> authorizeWithPkce({
    required Uri Function(String redirectUri, String state, String codeChallenge) authorizationUrlBuilder,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/callback';
    final state = _randomUrlSafe(24);
    final verifier = _randomUrlSafe(64);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

    final authUrl = authorizationUrlBuilder(redirectUri, state, challenge);
    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      await server.close(force: true);
      throw Exception('Tidak bisa membuka browser untuk login.');
    }

    try {
      await for (final request in server.timeout(timeout)) {
        if (request.uri.path != '/callback') {
          request.response.statusCode = 404;
          await request.response.close();
          continue;
        }
        final q = request.uri.queryParameters;
        final code = q['code'];
        final error = q['error'];
        final stateOk = q['state'] == state;

        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_responseHtml(success: error == null && code != null && stateOk));
        await request.response.close();

        if (error != null) throw Exception('Login dibatalkan atau gagal: $error');
        if (!stateOk) throw Exception('Respons login tidak valid (state tidak cocok).');
        if (code == null) throw Exception('Login gagal: kode tidak ditemukan');
        return OAuthPkceResult(code: code, redirectUri: redirectUri, codeVerifier: verifier);
      }
      throw Exception('Login dibatalkan.');
    } finally {
      await server.close(force: true);
    }
  }

  static String _responseHtml({required bool success}) => '''
    <html><body style="font-family:sans-serif;text-align:center;padding-top:80px;">
      <h2>${success ? "Login berhasil!" : "Login gagal"}</h2>
      <p>Kamu bisa menutup tab ini dan kembali ke Batam ChitChat.</p>
    </body></html>
  ''';
}
