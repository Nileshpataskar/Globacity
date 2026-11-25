import 'package:flutter/material.dart';

/// Raw color tokens. Change the brand here; the rest of the app reads colors
/// through [Theme.of] / `context.colors`, never from this class directly.
class AppColors {
  AppColors._();

  // Brand (GlobaCity logo): midnight navy, electric blue, cyan.
  static const navy = Color(0xFF101828);
  static const navyLight = Color(0xFF142F59);
  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1E40AF);
  static const secondary = Color(0xFF38BDF8);
  static const cyan = Color(0xFF38BDF8);

  /// Blue → cyan, as in the logo's "City" and G mark.
  static const brandGradient = [primary, cyan];

  // Semantic
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF0284C7);

  // Light neutrals
  static const lightBackground = Color(0xFFF6F8FC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFEFF3FA);
  static const lightBorder = Color(0xFFE6EBF3);
  static const lightText = Color(0xFF101828);
  static const lightTextMuted = Color(0xFF667085);

  // Dark neutrals
  static const darkBackground = Color(0xFF0A1020);
  static const darkSurface = Color(0xFF111A2E);
  static const darkSurfaceAlt = Color(0xFF18233D);
  static const darkBorder = Color(0xFF223051);
  static const darkText = Color(0xFFE6EBF5);
  static const darkTextMuted = Color(0xFF94A3B8);

  /// Palette used for avatar backgrounds and category accents.
  static const accents = [
    Color(0xFF2563EB),
    Color(0xFF0891B2),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF16A34A),
    Color(0xFF0891B2),
    Color(0xFFCA8A04),
  ];
}
