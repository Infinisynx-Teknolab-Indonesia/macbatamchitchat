import 'package:flutter/material.dart';
import '../screens/forgot_password_dialog.dart';
import '../screens/register_screen.dart';
import '../services/auth_service.dart';
import '../services/secure_storage_service.dart';
import '../theme/ym_theme.dart';
import 'mobile_session.dart';

/// Layar login mobile: logo, username + password, Remember me, lupa password, daftar.
class MobileLoginScreen extends StatefulWidget {
  const MobileLoginScreen({super.key});

  @override
  State<MobileLoginScreen> createState() => _MobileLoginScreenState();
}

class _MobileLoginScreenState extends State<MobileLoginScreen> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final AuthService _auth = AuthService();
  final SecureStorageService _storage = SecureStorageService();

  bool _remember = true;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    final creds = await _storage.getRememberedCredentials();
    if (creds != null && mounted) {
      setState(() {
        _username.text = creds['username'] ?? '';
        _password.text = creds['password'] ?? '';
      });
    }
  }

  Future<void> _login() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Username dan password wajib diisi.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _auth.loginWithPassword(username: username, password: password);
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _loading = false;
        _error = result.requiresUpdate
            ? '${result.errorMessage ?? 'Versi aplikasi terlalu lama.'} Silakan perbarui aplikasi.'
            : (result.errorMessage ?? 'Login gagal.');
      });
      return;
    }
    if (_remember) {
      await _storage.saveRememberedCredentials(username: username, password: password);
    } else {
      await _storage.clearRememberedCredentials();
    }
    if (!mounted) return;
    MobileSession.enter(context, username, profileComplete: result.profileComplete);
  }

  InputDecoration _decoration(String hint, IconData icon, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white70),
        suffixIcon: suffix,
        filled: true,
        fillColor: YmColors.fieldFillOnDark,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [YmColors.heroGradientTop, YmColors.heroGradientBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset('assets/icons/logo_batamchitchat.png', width: 104, height: 104),
                    ),
                    const SizedBox(height: 16),
                    const Text('Batam ChitChat',
                        style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Chat • Teman • Komunitas Lokal', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: YmColors.cardGlass,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _username,
                            enabled: !_loading,
                            style: const TextStyle(color: Colors.white),
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            decoration: _decoration('Username', Icons.person_outline),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            enabled: !_loading,
                            obscureText: _obscure,
                            style: const TextStyle(color: Colors.white),
                            onSubmitted: (_) => _loading ? null : _login(),
                            decoration: _decoration(
                              'Password',
                              Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white70),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Checkbox(
                                value: _remember,
                                activeColor: YmColors.accentPurple,
                                onChanged: _loading ? null : (v) => setState(() => _remember = v ?? true),
                              ),
                              const Text('Remember me', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              const Spacer(),
                              TextButton(
                                onPressed: _loading ? null : () => showForgotPasswordDialog(context),
                                child: const Text('Forgot password?',
                                    style: TextStyle(color: Color(0xFF9B8CFF), fontSize: 13)),
                              ),
                            ],
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13)),
                            ),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: YmColors.accentPurple,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: _loading ? null : _login,
                              child: _loading
                                  ? const SizedBox(
                                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                  : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Row(
                            children: [
                              Expanded(child: Divider(color: Colors.white24)),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('or', style: TextStyle(color: Colors.white54))),
                              Expanded(child: Divider(color: Colors.white24)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: YmColors.textDark,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Login dengan FJB Batam di aplikasi mobile segera hadir.')),
                              ),
                              icon: const Icon(Icons.storefront_outlined),
                              label: const Text('Login with FJB Batam', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account? ", style: TextStyle(color: Colors.white70)),
                        GestureDetector(
                          onTap: _loading
                              ? null
                              : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                          child: const Text('Register here',
                              style: TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text('Powered by FJB Batam', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
