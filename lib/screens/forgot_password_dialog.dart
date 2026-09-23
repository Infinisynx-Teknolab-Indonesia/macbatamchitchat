import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/password_reset_service.dart';
import '../theme/ym_theme.dart';

/// Dialog "Lupa password": (1) masukkan email -> kode 6 angka dikirim,
/// (2) masukkan kode + password baru -> selesai.
Future<void> showForgotPasswordDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ForgotPasswordDialog(),
  );
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _service = PasswordResetService();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  int _step = 0; // 0 = email, 1 = kode + password baru, 2 = selesai
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode({bool resend = false}) async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@') || email.length < 5) {
      setState(() => _error = 'Masukkan alamat email yang valid.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final result = await _service.requestCode(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success) {
        _step = 1;
        if (resend) _info = 'Kode baru sudah dikirim.';
      } else {
        _error = result.errorMessage;
      }
    });
  }

  Future<void> _confirm() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Kode terdiri dari 6 angka.');
      return;
    }
    if (_passCtrl.text.length < 6) {
      setState(() => _error = 'Password baru minimal 6 karakter.');
      return;
    }
    if (_passCtrl.text != _pass2Ctrl.text) {
      setState(() => _error = 'Konfirmasi password tidak sama.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final result = await _service.confirm(
      email: _emailCtrl.text.trim(),
      otp: otp,
      newPassword: _passCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success) {
        _step = 2;
      } else {
        _error = result.errorMessage;
      }
    });
  }

  String get _title {
    switch (_step) {
      case 0:
        return 'Lupa password';
      case 1:
        return 'Masukkan kode';
      default:
        return 'Password diubah';
    }
  }

  Widget _errorAndInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: const TextStyle(color: YmColors.buzzRed, fontSize: 12)),
          ),
        if (_info != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_info!, style: const TextStyle(color: YmColors.statusOnline, fontSize: 12)),
          ),
      ],
    );
  }

  List<Widget> _content() {
    if (_step == 0) {
      return [
        const Text('Masukkan email akunmu. Kami kirim kode 6 angka untuk membuat password baru.',
            style: TextStyle(fontSize: 13)),
        const SizedBox(height: 14),
        TextField(
          controller: _emailCtrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          enabled: !_busy,
          onSubmitted: (_) => _busy ? null : _sendCode(),
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), isDense: true),
        ),
        _errorAndInfo(),
      ];
    }
    if (_step == 1) {
      return [
        Text('Jika ${_emailCtrl.text.trim()} terdaftar, kode 6 angka sudah dikirim (cek juga folder spam). '
            'Kode berlaku 10 menit.',
            style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 14),
        TextField(
          controller: _otpCtrl,
          autofocus: true,
          enabled: !_busy,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
              labelText: 'Kode 6 angka', border: OutlineInputBorder(), isDense: true, counterText: ''),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passCtrl,
          enabled: !_busy,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Password baru',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _pass2Ctrl,
          enabled: !_busy,
          obscureText: _obscure,
          onSubmitted: (_) => _busy ? null : _confirm(),
          decoration: const InputDecoration(
              labelText: 'Ulangi password baru', border: OutlineInputBorder(), isDense: true),
        ),
        _errorAndInfo(),
      ];
    }
    return [
      const Text('Password berhasil diubah. Silakan login dengan password baru.', style: TextStyle(fontSize: 13)),
    ];
  }

  List<Widget> _actions() {
    final spinner = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    final primaryStyle = ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white);

    if (_step == 0) {
      return [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Batal')),
        ElevatedButton(
          style: primaryStyle,
          onPressed: _busy ? null : _sendCode,
          child: _busy ? spinner : const Text('Kirim kode'),
        ),
      ];
    }
    if (_step == 1) {
      return [
        TextButton(onPressed: _busy ? null : () => _sendCode(resend: true), child: const Text('Kirim ulang')),
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Batal')),
        ElevatedButton(
          style: primaryStyle,
          onPressed: _busy ? null : _confirm,
          child: _busy ? spinner : const Text('Ubah password'),
        ),
      ];
    }
    return [
      ElevatedButton(
        style: primaryStyle,
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Tutup'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _content(),
          ),
        ),
      ),
      actions: _actions(),
    );
  }
}
