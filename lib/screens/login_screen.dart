import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import '../theme/ym_theme.dart';
import '../widgets/retro_title_bar.dart';
import '../widgets/login_hero_background.dart';
import '../services/secure_storage_service.dart';
import '../services/auth_service.dart';
import '../services/auth_config.dart';
import '../services/tray_service.dart';
import '../main.dart' show AppWindowSizes;
import 'home_screen.dart';
import 'register_screen.dart';
import 'complete_profile_screen.dart';
import 'forgot_password_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _storage = SecureStorageService();
  final _authService = AuthService();

  AuthConfig _authConfig = AuthConfig.disabled;
  bool _configLoaded = false;

  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _prefillRememberedCredentials();
    _loadAuthConfig();
    // Same tray behavior as Home — closing the Login window (before ever
    // logging in) also minimizes to tray instead of quitting outright.
    // TrayService.init() is idempotent (guards against double-init), so
    // whichever screen calls it FIRST — Login here, or Home later after
    // a successful login — "wins" and sets up the ONE tray icon for the
    // app's whole lifetime; the other's call becomes a harmless no-op.
    TrayService.init(
      onExitRequested: () => exit(0),
      // No real session exists yet at the login screen, so "Logout" here
      // just clears whatever might be lingering (harmless no-op if
      // nothing was stored) rather than doing nothing silently.
      onLogoutRequested: () => SecureStorageService().clearSession(),
    );
  }

  Future<void> _prefillRememberedCredentials() async {
    // Uses getRememberedCredentials (survives logout) instead of the old
    // getUsername() (which came from the SESSION and got wiped by
    // clearSession() on every logout) — that mismatch is exactly why
    // "Remember me" appeared to do nothing after logging out.
    final creds = await _storage.getRememberedCredentials();
    if (creds != null) {
      setState(() {
        _usernameCtrl.text = creds['username']!;
        _passwordCtrl.text = creds['password']!;
        _rememberMe = true;
      });
    }
  }

  Future<void> _loadAuthConfig() async {
    // Fetched from the backend so the admin panel can enable/disable
    // Google / FJB Batam / captcha at any time without an app update.
    final config = await _authService.fetchAuthConfig();
    if (mounted) setState(() {
      _authConfig = config;
      _configLoaded = true;
    });
  }

  Future<void> _handlePasswordSignIn() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorText = 'Username dan password wajib diisi.');
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });

    String? captchaToken;
    if (_authConfig.captchaEnabled) {
      try {
        captchaToken = await _authService.getCaptchaToken(_authConfig);
      } catch (e) {
        setState(() {
          _loading = false;
          _errorText = 'Verifikasi keamanan belum siap. Coba lagi nanti.';
        });
        return;
      }
    }

    final result = await _authService.loginWithPassword(
      username: username,
      password: password,
      captchaToken: captchaToken,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      // Save (or forget) credentials based on the checkbox — this is what
      // makes "Remember me" actually survive a logout, unlike before
      // where nothing was ever written anywhere.
      if (_rememberMe) {
        await _storage.saveRememberedCredentials(username: username, password: password);
      } else {
        await _storage.clearRememberedCredentials();
      }
      _goToBuddyList(username);
    } else if (result.requiresUpdate) {
      _showUpdateRequiredDialog(result.errorMessage ?? 'Versi aplikasi kamu sudah usang.');
    } else {
      setState(() => _errorText = result.errorMessage ?? 'Login gagal.');
    }
  }

  void _showUpdateRequiredDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Update Diperlukan'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Oke')),
        ],
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() { _loading = true; _errorText = null; });
    final result = await _authService.loginWithGoogle(_authConfig);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.success) {
      final username = await _storage.getUsername() ?? 'Pengguna Google';
      _goToBuddyList(username, profileComplete: result.profileComplete);
    } else {
      setState(() => _errorText = result.errorMessage);
    }
  }

  Future<void> _handleFjbBatamSignIn() async {
    setState(() { _loading = true; _errorText = null; });
    final result = await _authService.loginWithFjbBatam(_authConfig);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.success) {
      final username = await _storage.getUsername() ?? 'Pengguna FJB Batam';
      _goToBuddyList(username, profileComplete: result.profileComplete);
    } else {
      setState(() => _errorText = result.errorMessage);
    }
  }

  Future<void> _goToBuddyList(String username, {bool profileComplete = true}) async {
    // Resize the login window into the main app's fixed size — still
    // NOT resizable, just a different fixed size (300x700).
    await windowManager.setMinimumSize(AppWindowSizes.main);
    await windowManager.setMaximumSize(AppWindowSizes.main);
    await windowManager.setSize(AppWindowSizes.main);
    await windowManager.center();

    if (!mounted) return;
    // Google/FJB Batam accounts that haven't filled in nickname/birth
    // date/gender/WhatsApp yet go through CompleteProfileScreen FIRST —
    // local password accounts always collect these upfront at register,
    // so profileComplete defaults to true for that path.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => profileComplete
            ? HomeScreen(myUsername: username)
            : CompleteProfileScreen(username: username),
      ),
    );
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const RetroTitleBar(title: 'Batam ChitChat', icon: Icons.forum_rounded),
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: LoginHeroBackground()),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      width: 340,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: YmColors.cardGlass,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            // Logo resmi langsung dari file gambar — tidak lewat AppLogo,
                            // supaya tidak tergantung isi app_logo.dart.
                            child: Image.asset(
                              'assets/icons/logo_batamchitchat.png',
                              width: 96,
                              height: 96,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Center(
                            child: Text('Batam ChitChat', style: TextStyle(
                              fontFamily: 'Tahoma', fontFamilyFallback: ['Segoe UI', 'Arial'],
                              fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
                            )),
                          ),
                          const SizedBox(height: 4),
                          Center(
                            child: Text('Chat • Teman • Komunitas Lokal', style: TextStyle(
                              fontSize: 12, color: Colors.white.withOpacity(0.7),
                            )),
                          ),
                          const SizedBox(height: 24),

                          if (_authConfig.passwordLoginEnabled) ...[
                            _DarkTextField(
                              controller: _usernameCtrl,
                              hint: 'Username / Email',
                              icon: Icons.person_outline,
                            ),
                            const SizedBox(height: 12),
                            _DarkTextField(
                              controller: _passwordCtrl,
                              hint: 'Password',
                              icon: Icons.lock_outline,
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility,
                                    size: 18, color: Colors.white70),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              onSubmitted: (_) => _handlePasswordSignIn(),
                            ),

                            if (_errorText != null) ...[
                              const SizedBox(height: 10),
                              Text(_errorText!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12)),
                            ],

                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 18, height: 18,
                                        child: Checkbox(
                                          value: _rememberMe,
                                          onChanged: (v) => setState(() => _rememberMe = v ?? true),
                                          activeColor: YmColors.accentPurple,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Remember me',
                                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: _loading ? null : () => showForgotPasswordDialog(context),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('Forgot password?', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 44,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _handlePasswordSignIn,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: YmColors.accentPurple,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: _loading
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Login', style: TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ] else if (!_configLoaded) ...[
                            const Center(child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: CircularProgressIndicator(color: Colors.white),
                            )),
                          ],

                          // Divider + social logins, shown only per admin-controlled config
                          if (_authConfig.googleLoginEnabled || _authConfig.fjbBatamLoginEnabled) ...[
                            const SizedBox(height: 18),
                            Row(children: [
                              Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text('or', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                              ),
                              Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
                            ]),
                            const SizedBox(height: 14),
                          ],

                          if (_authConfig.googleLoginEnabled) ...[
                            _SocialLoginButton(
                              label: 'Login with Google',
                              icon: Icons.g_mobiledata_rounded, // placeholder glyph; swap for the real Google "G" asset per Google's brand guidelines
                              onPressed: _loading ? null : _handleGoogleSignIn,
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_authConfig.fjbBatamLoginEnabled) ...[
                            _SocialLoginButton(
                              label: 'Login with FJB Batam',
                              icon: Icons.storefront_outlined,
                              onPressed: _loading ? null : _handleFjbBatamSignIn,
                            ),
                          ],

                          const SizedBox(height: 18),
                          Center(
                            child: Text.rich(
                              TextSpan(
                                text: "Don't have an account? ",
                                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                                children: [
                                  TextSpan(
                                    text: 'Register here',
                                    style: const TextStyle(color: Color(0xFFFFC94D), fontWeight: FontWeight.w600),
                                    // This TextSpan previously had NO
                                    // recognizer at all — it LOOKED like a
                                    // link (styled, colored) but was
                                    // literally inert, unclickable text.
                                    // A recognizer is required for a
                                    // TextSpan to respond to taps at all.
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () => Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: Text(
                              'Powered by FJB Batam',
                              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;

  const _DarkTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white70, size: 18),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        filled: true,
        fillColor: YmColors.fieldFillOnDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: YmColors.accentPurple, width: 1.5),
        ),
      ),
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const _SocialLoginButton({required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: YmColors.textDark, size: 20),
        label: Text(label, style: const TextStyle(color: YmColors.textDark, fontWeight: FontWeight.w600, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
