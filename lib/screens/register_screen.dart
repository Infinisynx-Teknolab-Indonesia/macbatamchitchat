import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../theme/ym_theme.dart';
import 'home_screen.dart';

/// Full registration — collects nickname, WhatsApp number, birth date,
/// gender, AND email. Email is now REQUIRED, and if the admin has turned
/// email on (settings.email_enabled), registration goes through a 2-step
/// OTP flow: request-otp emails a 6-digit code, verify-otp finishes
/// creating the account. If the admin hasn't set up email yet, this
/// falls back to instant registration — see /auth/config's
/// otp_registration_required, which mirrors email_enabled server-side so
/// registration is never accidentally left completely broken just
/// because nobody's configured SMTP.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

enum _RegisterStep { form, otpVerify }

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  DateTime? _birthDate;
  String? _gender;
  bool _loading = false;
  String? _error;
  _RegisterStep _step = _RegisterStep.form;
  bool? _otpRequired; // null while still checking /auth/config

  @override
  void initState() {
    super.initState();
    _checkOtpRequirement();
  }

  Future<void> _checkOtpRequirement() async {
    try {
      final res = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/auth/config'));
      if (res.statusCode == 200) {
        setState(() => _otpRequired = jsonDecode(res.body)['otp_registration_required'] ?? false);
        return;
      }
    } catch (_) {
      // fall through
    }
    setState(() => _otpRequired = false); // safe default — don't block registration if config check fails
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _emailCtrl.dispose();
    _fullNameCtrl.dispose();
    _whatsappCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  bool _looksLikeEmail(String v) => v.contains('@') && v.contains('.') && !v.contains(' ');

  Map<String, dynamic> _formPayload() => {
        'username': _usernameCtrl.text.trim(),
        'password': _passwordCtrl.text,
        'email': _emailCtrl.text.trim(),
        'full_name': _fullNameCtrl.text.trim().isEmpty ? null : _fullNameCtrl.text.trim(),
        'gender': _gender,
        'whatsapp_number': _whatsappCtrl.text.trim().isEmpty ? null : _whatsappCtrl.text.trim(),
        'birth_date': _birthDate?.toIso8601String().split('T').first,
      };

  Future<void> _submitForm() async {
    if (_usernameCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Username dan password wajib diisi.');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty || !_looksLikeEmail(_emailCtrl.text.trim())) {
      setState(() => _error = 'Email wajib diisi dengan format yang benar.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_otpRequired == true) {
        // Step 1 of 2 — request the OTP, don't create the account yet.
        final res = await http.post(
          Uri.parse('${AppConfig.apiBaseUrl}/auth/register/request-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(_formPayload()),
        );
        if (!mounted) return;
        if (res.statusCode == 200) {
          setState(() {
            _loading = false;
            _step = _RegisterStep.otpVerify;
          });
        } else {
          final data = jsonDecode(res.body);
          setState(() {
            _loading = false;
            _error = data['detail'] ?? 'Gagal mengirim kode verifikasi.';
          });
        }
      } else {
        // Email not turned on by the admin yet — instant registration,
        // same as before.
        final res = await http.post(
          Uri.parse('${AppConfig.apiBaseUrl}/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(_formPayload()),
        );
        if (!mounted) return;
        if (res.statusCode == 200) {
          _goToHome();
        } else {
          final data = jsonDecode(res.body);
          setState(() {
            _loading = false;
            _error = data['detail'] ?? 'Registrasi gagal.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Tidak bisa terhubung ke server.';
      });
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.trim().length != 6) {
      setState(() => _error = 'Kode verifikasi harus 6 digit.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/auth/register/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': _emailCtrl.text.trim(), 'otp': _otpCtrl.text.trim()}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _goToHome();
      } else {
        final data = jsonDecode(res.body);
        setState(() {
          _loading = false;
          _error = data['detail'] ?? 'Verifikasi gagal.';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Tidak bisa terhubung ke server.';
      });
    }
  }

  void _goToHome() {
    final username = _usernameCtrl.text.trim();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(myUsername: username)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YmColors.titleBarStart,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(ymBorderRadius),
              border: Border.all(color: Colors.white24),
            ),
            // RadioListTile gender (di dalam _buildForm(), lihat komentar sama
            // di complete_profile_screen.dart) butuh Material terdekat untuk
            // ink splash-nya — dibungkus di sini supaya berlaku untuk semua isi.
            child: Material(
              color: Colors.transparent,
              child: _otpRequired == null
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    )
                  : (_step == _RegisterStep.form ? _buildForm() : _buildOtpVerify()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Text('Daftar Akun Baru', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        _field(_usernameCtrl, 'Username', icon: Icons.person_outline),
        const SizedBox(height: 12),
        _field(_passwordCtrl, 'Password', icon: Icons.lock_outline, obscure: true),
        const SizedBox(height: 12),
        _field(_emailCtrl, 'Email', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
        if (_otpRequired == true)
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text('Kode verifikasi akan dikirim ke email ini.', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ),
        const SizedBox(height: 12),
        _field(_fullNameCtrl, 'Nama / Alias', icon: Icons.badge_outlined),
        const SizedBox(height: 12),
        _field(_whatsappCtrl, 'Nomor WhatsApp', icon: Icons.chat_outlined, keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickBirthDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                const Icon(Icons.cake_outlined, color: Colors.white70, size: 18),
                const SizedBox(width: 10),
                Text(
                  _birthDate == null ? 'Tanggal Lahir' : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}',
                  style: TextStyle(color: _birthDate == null ? Colors.white54 : Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                value: 'male',
                groupValue: _gender,
                onChanged: (v) => setState(() => _gender = v),
                title: const Text('Pria', style: TextStyle(color: Colors.white, fontSize: 13)),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                value: 'female',
                groupValue: _gender,
                onChanged: (v) => setState(() => _gender = v),
                title: const Text('Wanita', style: TextStyle(color: Colors.white, fontSize: 13)),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12)),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading ? null : _submitForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: YmColors.accentPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_otpRequired == true ? 'Kirim Kode Verifikasi' : 'Daftar'),
        ),
      ],
    );
  }

  Widget _buildOtpVerify() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => setState(() {
                _step = _RegisterStep.form;
                _error = null;
              }),
            ),
            const Expanded(child: Text('Verifikasi Email', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Kode verifikasi 6 digit sudah dikirim ke ${_emailCtrl.text.trim()}. Cek folder spam juga kalau belum masuk.',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 8),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 8),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading ? null : _verifyOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: YmColors.accentPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Verifikasi & Buat Akun'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _loading ? null : _submitForm,
          child: const Text('Kirim ulang kode', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, {required IconData icon, bool obscure = false, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white70, size: 18),
        hintText: label,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
