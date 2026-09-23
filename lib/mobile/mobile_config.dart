import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Konfigurasi satu lokasi iklan (diatur admin di panel: tab Settings > Banner Iklan + tab Integrasi).
class AdPlacement {
  final bool enabled;
  final String type; // image | admob | html (html diabaikan di HP)
  final String? imageUrl;
  final String? linkUrl;
  final String? admobUnitId;
  const AdPlacement({
    required this.enabled,
    required this.type,
    this.imageUrl,
    this.linkUrl,
    this.admobUnitId,
  });

  factory AdPlacement.fromJson(Map<String, dynamic> j) => AdPlacement(
        enabled: j['enabled'] == true,
        type: (j['type'] as String?) ?? 'image',
        imageUrl: j['image_url'] as String?,
        linkUrl: j['link_url'] as String?,
        admobUnitId: j['admob_unit_id'] as String?,
      );
}

/// Konfigurasi dari server (GET /api/mobile/config): status Firebase + iklan per lokasi.
class MobileConfig extends ChangeNotifier {
  MobileConfig._();
  static final MobileConfig instance = MobileConfig._();

  bool pushEnabled = false;
  String? firebaseProjectId;
  final Map<String, AdPlacement> placements = {};

  AdPlacement? placement(String key) => placements[key];

  Future<void> load() async {
    try {
      final res = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/mobile/config'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final push = (data['push'] as Map?) ?? const {};
      pushEnabled = push['enabled'] == true;
      firebaseProjectId = push['project_id'] as String?;
      final ads = (data['ads'] as Map?) ?? const {};
      final raw = (ads['placements'] as Map?) ?? const {};
      placements
        ..clear()
        ..addAll(raw.map((k, v) => MapEntry(k as String, AdPlacement.fromJson(Map<String, dynamic>.from(v as Map)))));
      notifyListeners();
    } catch (_) {
      // server lama / offline: pakai konfigurasi terakhir (kosong = tanpa iklan)
    }
  }
}
