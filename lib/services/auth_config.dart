/// Feature flags controlling which login methods are shown/active.
/// These are meant to be fetched from the backend (GET /api/auth/config)
/// so the *admin panel* can flip them on/off at runtime — no app rebuild
/// or redeploy needed. Defaults here are the safe fallback if the backend
/// call fails (e.g. offline first launch): only local username/password.
class AuthConfig {
  final bool passwordLoginEnabled;
  final bool googleLoginEnabled;
  final bool fjbBatamLoginEnabled;
  final bool captchaEnabled;
  final String? captchaSiteKey; // public site key only; secret stays server-side
  final String? googleClientId; // OAuth client ID (public, safe to ship)
  final String? fjbBatamAuthUrl; // FJB Batam OAuth authorize endpoint, once they provide one
  final String? fjbBatamClientId;

  const AuthConfig({
    this.passwordLoginEnabled = true,
    this.googleLoginEnabled = false,
    this.fjbBatamLoginEnabled = false,
    this.captchaEnabled = false,
    this.captchaSiteKey,
    this.googleClientId,
    this.fjbBatamAuthUrl,
    this.fjbBatamClientId,
  });

  factory AuthConfig.fromJson(Map<String, dynamic> json) {
    return AuthConfig(
      passwordLoginEnabled: json['password_login_enabled'] ?? true,
      googleLoginEnabled: json['google_login_enabled'] ?? false,
      fjbBatamLoginEnabled: json['fjb_batam_login_enabled'] ?? false,
      captchaEnabled: json['captcha_enabled'] ?? false,
      captchaSiteKey: json['captcha_site_key'],
      googleClientId: json['google_client_id'],
      fjbBatamAuthUrl: json['fjb_batam_auth_url'],
      fjbBatamClientId: json['fjb_batam_client_id'],
    );
  }

  /// Safe fallback used when the config endpoint is unreachable — never
  /// silently enable a login method we don't have real credentials for.
  static const disabled = AuthConfig();
}
