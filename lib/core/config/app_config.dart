import 'package:flutter/material.dart';

/// White-label configuration.
///
/// Everything brand-specific that is not a color or a font lives here, so a
/// new client build only needs to change this file and the theme tokens.
class AppConfig {
  AppConfig._();

  static const appName = 'GlobaCity';
  static const tagline = 'Smarter living for your community';
  static const logoIcon = Icons.apartment_rounded;

  static const currency = 'AED';
  static const defaultCountryCode = '+971';
  static const supportEmail = 'support@globacity.app';
}
