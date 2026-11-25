import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography tokens.
///
/// To change the app font, edit [fontFamily] (any Google Fonts family name).
/// To use a bundled font instead, add it under `flutter: fonts:` in
/// pubspec.yaml and return `base.apply(fontFamily: 'YourFont')` from
/// [textTheme].
class AppTypography {
  AppTypography._();

  /// Inter matches the GlobaCity wordmark.
  static const fontFamily = 'Inter';

  /// Arabic-capable font used when the locale is RTL.
  static const arabicFontFamily = 'Noto Kufi Arabic';

  static TextTheme textTheme(Color text, Color muted, {bool arabic = false}) {
    final base = TextTheme(
      displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.12, color: text, letterSpacing: -1.0),
      headlineMedium: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, height: 1.18, color: text, letterSpacing: -0.7),
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25, color: text, letterSpacing: -0.4),
      titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3, color: text, letterSpacing: -0.3),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35, color: text),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35, color: text),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5, color: text),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.45, color: text),
      bodySmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.4, color: muted),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: text),
      labelMedium: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: muted),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.3),
    );
    // Resolve each style separately so every weight loads its own font file.
    final family = arabic ? arabicFontFamily : fontFamily;
    TextStyle? font(TextStyle? s) => s == null ? null : GoogleFonts.getFont(family, textStyle: s);
    return base.copyWith(
      displaySmall: font(base.displaySmall),
      headlineMedium: font(base.headlineMedium),
      headlineSmall: font(base.headlineSmall),
      titleLarge: font(base.titleLarge),
      titleMedium: font(base.titleMedium),
      titleSmall: font(base.titleSmall),
      bodyLarge: font(base.bodyLarge),
      bodyMedium: font(base.bodyMedium),
      bodySmall: font(base.bodySmall),
      labelLarge: font(base.labelLarge),
      labelMedium: font(base.labelMedium),
      labelSmall: font(base.labelSmall),
    );
  }
}
