import 'package:flutter/material.dart';

/// White-label configuration.
///
/// Everything brand-specific that is not a color or a font lives here, so a
/// new client build only needs to change this file and the theme tokens.
class AppConfig {
  AppConfig._();

  /// True when running as the separate "GlobaCity Guard" app (set by guard_app/lib/main.dart).
  static bool guardApp = false;

  /// Package that owns the brand assets when this code runs inside another app (the guard app).
  static String? assetPackage;

  static String get appName => guardApp ? 'GlobaCity Guard' : 'GlobaCity';
  static const tagline = 'Smarter living for your community';
  static const logoIcon = Icons.apartment_rounded;

  static const currency = 'AED';
  static const defaultCountryCode = '+971';
  static const supportEmail = 'support@globacity.app';
}
