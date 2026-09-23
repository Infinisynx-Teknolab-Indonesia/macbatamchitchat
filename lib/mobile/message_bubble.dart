import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/ym_theme.dart';
import 'models.dart';

class _LatLng {
  final double lat;
  final double lng;
  const _LatLng(this.lat, this.lng);
}

/// Membaca "lat,lng" dari isi pesan lokasi. Isi pesan berasal dari orang lain, jadi HANYA angka yang lolos
/// validasi yang dipakai membentuk URL Google Maps.
_LatLng? _parseCoordinates(String raw) {
  final parts = raw.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return _LatLng(lat, lng);
}

Future<void> _openInMaps(BuildContext context, _LatLng p) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}',
  );
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa membuka Google Maps.')));
  }
}

/// Gelembung chat gaya WhatsApp: teks, Buzz, lokasi (bisa diketuk -> Google Maps), foto, audible.
class MessageBubble extends StatelessWidget {
  final ChatEntry entry;
  final String peerName; // nama lawan bicara di layar saya (nama panggilan / nickname / @username)
  const MessageBubble({super.key, required this.entry, required this.peerName});

  @override
  Widget build(BuildContext context) {
    final mine = entry.isMine;
    final isBuzz = entry.text == buzzMarker;
    final bubbleColor = isBuzz
        ? const Color(0xFFFDE7E6)
        : (mine ? const Color(0xFFDCD9FB) : Colors.white);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: entry.text.startsWith(imagePrefix)
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))],
            ),
            child: _content(context, isBuzz),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Text(
              DateFormat('dd/MM/yyyy HH:mm').format(entry.time),
              style: const TextStyle(fontSize: 10, color: YmColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, bool isBuzz) {
    final text = entry.text;

    if (isBuzz) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt, size: 20, color: YmColors.buzzRed),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              entry.isMine ? 'Kamu mengirim Buzz!' : '$peerName mengirim Buzz!',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: YmColors.buzzRed),
            ),
          ),
        ],
      );
    }

    if (text.startsWith(locationPrefix)) {
      final coords = text.substring(locationPrefix.length);
      final point = _parseCoordinates(coords);
      return InkWell(
        onTap: point == null ? null : () => _openInMaps(context, point),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 22, color: YmColors.accentPurple),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    point == null
                        ? 'Lokasi: $coords'
                        : 'Lokasi: ${point.lat.toStringAsFixed(5)}, ${point.lng.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 15, color: YmColors.textDark),
                  ),
                  if (point != null)
                    const Text(
                      'Ketuk untuk buka di Google Maps',
                      style: TextStyle(fontSize: 12, color: YmColors.accentPurple, decoration: TextDecoration.underline),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (text.startsWith(imagePrefix)) {
      try {
        final bytes = base64Decode(text.substring(imagePrefix.length));
        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.black,
              insetPadding: EdgeInsets.zero,
              child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, width: 220, fit: BoxFit.cover),
          ),
        );
      } catch (_) {
        return const Text('[Gambar tidak bisa ditampilkan]', style: TextStyle(fontSize: 15));
      }
    }

    if (text.startsWith(audiblePrefix)) {
      final parts = text.split(audibleSeparator);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.volume_up, size: 20, color: YmColors.accentPurple),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              parts.length >= 2 ? parts[1] : 'Audible',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: YmColors.textDark),
            ),
          ),
        ],
      );
    }

    return Text(text, style: const TextStyle(fontSize: 15, color: YmColors.textDark));
  }
}
