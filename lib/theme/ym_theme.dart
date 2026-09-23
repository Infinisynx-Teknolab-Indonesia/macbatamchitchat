import 'package:flutter/material.dart';

/// Design tokens for "Batam ChitChat" — deep blue/indigo chrome with a
/// violet accent, matching the app's blue visual identity.
class YmColors {
  static const titleBarStart = Color(0xFF1E2A6E);
  static const titleBarEnd = Color(0xFF4C4FCE);
  static const accentPurple = Color(0xFF5B4FE0); // primary accent (buttons, links, selection)
  static const accentBlue = Color(0xFF2F3E9E);
  static const panelBackground = Color(0xFFF3F4FC);
  static const contentBackground = Color(0xFFFFFFFF);
  static const borderLavender = Color(0xFFD8DAF0);
  static const textDark = Color(0xFF232849);
  static const textMuted = Color(0xFF8A8DAE);
  static const statusOnline = Color(0xFF2ECC71);
  static const statusOffline = Color(0xFFB7BAD6);
  static const statusBusy = Color(0xFFE24C4B);
  static const statusAway = Color(0xFFF5A623);
  static const bubbleIncoming = Color(0xFFEDEEFA);
  static const bubbleOutgoing = Color(0xFFD9DAF7);
  static const buzzRed = Color(0xFFE24C4B);

  // Login hero background — deep navy-to-violet gradient behind the
  // original skyline/bridge illustration (no stock photo, drawn ourselves).
  static const heroGradientTop = Color(0xFF141B4D);
  static const heroGradientBottom = Color(0xFF3C2E7A);
  static const cardGlass = Color(0xCC1B234F); // semi-transparent navy card overlay
  static const fieldFillOnDark = Color(0x1FFFFFFF); // frosted input fill on dark hero
}

class YmTextStyles {
  static const _fontFamilyFallback = ['Tahoma', 'Segoe UI', 'Arial'];

  static const appTitle = TextStyle(
    fontFamily: 'Tahoma',
    fontFamilyFallback: _fontFamilyFallback,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static const username = TextStyle(
    fontFamily: 'Tahoma',
    fontFamilyFallback: _fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: YmColors.textDark,
  );

  static const statusMessage = TextStyle(
    fontFamily: 'Tahoma',
    fontFamilyFallback: _fontFamilyFallback,
    fontSize: 10,
    fontStyle: FontStyle.italic,
    color: YmColors.textMuted,
  );

  static const buddyName = TextStyle(
    fontFamily: 'Tahoma',
    fontFamilyFallback: _fontFamilyFallback,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: YmColors.textDark,
  );

  static const chatText = TextStyle(
    fontFamily: 'Tahoma',
    fontFamilyFallback: _fontFamilyFallback,
    fontSize: 11,
    color: YmColors.textDark,
  );

  static const label = TextStyle(
    fontFamily: 'Tahoma',
    fontFamilyFallback: _fontFamilyFallback,
    fontSize: 10,
    color: YmColors.textMuted,
  );
}

const ymBorderRadius = 6.0;
