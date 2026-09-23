import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../theme/ym_theme.dart';

/// Looks up (and remembers, per window) each user's photo_url so lists
/// with many people don't refetch the same profile on every rebuild.
/// Failed lookups are NOT remembered, so they get retried next build.
class ProfilePhotoCache {
  static final Map<String, Future<String?>> _cache = {};

  static Future<String?> photoUrlFor(String username, {String? viewer}) {
    final existing = _cache[username];
    if (existing != null) return existing;
    final future = _fetch(username, viewer ?? username);
    _cache[username] = future;
    return future;
  }

  static Future<String?> _fetch(String username, String viewer) async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/users/$username/profile').replace(
          queryParameters: {'viewer': viewer},
        ),
      );
      if (res.statusCode == 200) {
        final url = jsonDecode(res.body)['photo_url'];
        return (url is String && url.isNotEmpty) ? url : null;
      }
    } catch (_) {
      // fall through — treated as a failed lookup below
    }
    // Drop the failed entry AFTER photoUrlFor() has stored it.
    scheduleMicrotask(() => _cache.remove(username));
    return null;
  }

  /// Call after that user's photo changed so the next build refetches.
  static void invalidate(String username) => _cache.remove(username);
}

/// The ONE avatar widget for the whole app. Whenever a user has no photo
/// (or the photo fails to load) it shows the default "no photo" person
/// icon — never the first letter of the username.
///
/// To change what the default looks like everywhere at once (e.g. use
/// Icons.no_photography or an Image.asset), edit only [_noPhoto] below.
///
/// Two ways to use it:
///   UserAvatar(photoUrl: url, radius: 20)       — you already have the URL
///   UserAvatar(username: 'andi', viewer: me)     — looks the photo up
class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String? username;
  final String? viewer;
  final double radius;
  final Color? backgroundColor;
  final Color? iconColor;

  /// Appended as ?v=... so a re-uploaded photo (same server path) is
  /// actually refetched instead of served from Flutter's image cache.
  final int? version;

  const UserAvatar({
    super.key,
    this.photoUrl,
    this.username,
    this.viewer,
    this.radius = 16,
    this.backgroundColor,
    this.iconColor,
    this.version,
  });

  static String? resolveUrl(String? raw, {int? version}) {
    if (raw == null || raw.trim().isEmpty) return null;
    var url = raw.startsWith('http')
        ? raw
        : '${AppConfig.serverBaseUrl}${raw.startsWith('/') ? '' : '/'}$raw';
    if (version != null) {
      url += '${url.contains('?') ? '&' : '?'}v=$version';
    }
    return url;
  }

  Widget _noPhoto(Color color) => Icon(Icons.person, size: radius * 1.25, color: color);

  Widget _avatar(String? rawUrl) {
    final url = resolveUrl(rawUrl, version: version);
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? YmColors.accentPurple.withOpacity(0.15),
      foregroundImage: url != null ? NetworkImage(url) : null,
      onForegroundImageError: url != null ? (Object e, StackTrace? s) {} : null,
      // Shown when there's no photo, while it loads, or if it fails.
      child: _noPhoto(iconColor ?? YmColors.accentPurple),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (photoUrl == null && username != null) {
      return FutureBuilder<String?>(
        future: ProfilePhotoCache.photoUrlFor(username!, viewer: viewer),
        builder: (context, snap) => _avatar(snap.data),
      );
    }
    return _avatar(photoUrl);
  }
}
