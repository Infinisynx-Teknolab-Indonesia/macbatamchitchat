import 'package:flutter/material.dart';

/// Logo Batam ChitChat — gambar resmi (assets/icons/logo_batamchitchat.png).
///
/// Sebelumnya widget ini menggambar siluet jembatan di dalam lingkaran;
/// sekarang cukup menampilkan gambar logo. Satu-satunya tempat mengganti
/// logo di seluruh aplikasi: timpa file PNG-nya.
///
/// PENTING: aset harus terdaftar di pubspec.yaml:
///   flutter:
///     assets:
///       - assets/icons/logo_batamchitchat.png
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/logo_batamchitchat.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Batam ChitChat',
    );
  }
}
