import 'package:flutter/material.dart';

/// Centralized theme definitions for DriveAware.
///
/// Use [AppTheme.night] and [AppTheme.day] to get the correct
/// color palette based on the current mode, instead of inline color literals.
class AppTheme {
  final Color background;
  final Color backgroundGradientStart;
  final Color backgroundGradientMid;
  final Color backgroundGradientEnd;
  final Color surface;
  final Color surfaceBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color accentGlow;
  final Color liveDot;
  final Color liveText;
  final Color liveBg;
  final Color liveBorder;

  const AppTheme._({
    required this.background,
    required this.backgroundGradientStart,
    required this.backgroundGradientMid,
    required this.backgroundGradientEnd,
    required this.surface,
    required this.surfaceBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentGlow,
    required this.liveDot,
    required this.liveText,
    required this.liveBg,
    required this.liveBorder,
  });

  /// Dark / Night mode palette.
  static const night = AppTheme._(
    background: Color(0xFF0F0C29),
    backgroundGradientStart: Color(0xFF0F0C29),
    backgroundGradientMid: Color(0xFF302B63),
    backgroundGradientEnd: Color(0xFF24243E),
    surface: Color(0x0DFFFFFF), // white 5%
    surfaceBorder: Color(0x1AFFFFFF), // white 10%
    textPrimary: Colors.white,
    textSecondary: Color(0xFFE0E7FF),
    accent: Color(0xFF6366F1),
    accentGlow: Color(0xFF6366F1),
    liveDot: Color(0xFF4ADE80),
    liveText: Color(0xFF86EFAC),
    liveBg: Color(0x1A22C55E), // green 10%
    liveBorder: Color(0x3322C55E), // green 20%
  );

  /// Light / Day mode palette.
  static const day = AppTheme._(
    background: Color(0xFFF8FAFC),
    backgroundGradientStart: Color(0xFFF8FAFC),
    backgroundGradientMid: Color(0xFFE2E8F0),
    backgroundGradientEnd: Color(0xFFCBD5E1),
    surface: Color(0x0D000000), // black 5%
    surfaceBorder: Color(0x1A000000), // black 10%
    textPrimary: Color(0xFF1E293B),
    textSecondary: Color(0xFF334155),
    accent: Color(0xFF3B82F6),
    accentGlow: Color(0xFF0EA5E9),
    liveDot: Color(0xFF15803D),
    liveText: Color(0xFF166534),
    liveBg: Color(0x2616A34A), // green 15%
    liveBorder: Color(0x6616A34A), // green 40%
  );

  /// Returns the correct theme based on [isNightMode].
  static AppTheme of(bool isNightMode) => isNightMode ? night : day;
}

