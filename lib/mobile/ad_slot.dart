import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import 'mobile_config.dart';

/// Spanduk iklan untuk satu lokasi ("home", "room_list", "private_chat", "room_chat"). Semua dikendalikan admin
/// lewat admin panel; secara bawaan semua lokasi MATI sehingga tidak tampil apa-apa.
///   image -> banner gambar + link buatan sendiri
///   admob -> banner Google AdMob (mode uji memakai iklan contoh Google)
///   html  -> tidak ditampilkan di HP (kode AdSense hanya untuk website; aplikasi wajib AdMob)
class AdSlot extends StatelessWidget {
  final String placement;
  const AdSlot({super.key, required this.placement});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MobileConfig.instance,
      builder: (context, _) {
        final p = MobileConfig.instance.placement(placement);
        if (p == null || !p.enabled) return const SizedBox.shrink();
        if (p.type == 'image') return _ImageAd(imageUrl: p.imageUrl, linkUrl: p.linkUrl);
        if (p.type == 'admob') return _AdMobBanner(unitId: p.admobUnitId);
        return const SizedBox.shrink();
      },
    );
  }
}

class _ImageAd extends StatelessWidget {
  final String? imageUrl;
  final String? linkUrl;
  const _ImageAd({required this.imageUrl, required this.linkUrl});

  Future<void> _open() async {
    final uri = Uri.tryParse(linkUrl ?? '');
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Iklan', style: TextStyle(fontSize: 9, color: Colors.grey)),
          InkWell(
            onTap: _open,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 90),
              child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdMobBanner extends StatefulWidget {
  final String? unitId;
  const _AdMobBanner({required this.unitId});

  @override
  State<_AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<_AdMobBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AdMobBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitId != widget.unitId) {
      _ad?.dispose();
      _ad = null;
      _loaded = false;
      _load();
    }
  }

  void _load() {
    final unit = widget.unitId;
    if (unit == null || unit.isEmpty) return;
    final ad = BannerAd(
      adUnitId: unit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (failed, error) {
          failed.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      height: ad.size.height.toDouble(),
      color: Colors.white,
      alignment: Alignment.center,
      child: SizedBox(width: ad.size.width.toDouble(), height: ad.size.height.toDouble(), child: AdWidget(ad: ad)),
    );
  }
}
