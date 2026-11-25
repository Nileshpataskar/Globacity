import 'package:flutter/material.dart';

/// Spacing scale (4pt grid).
class AppSpacing {
  AppSpacing._();

  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  /// Horizontal padding for screen content.
  static const screen = EdgeInsets.symmetric(horizontal: lg);
  static const screenAll = EdgeInsets.all(lg);
}

/// Corner radii.
class AppRadius {
  AppRadius._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const pill = 999.0;

  static const cardRadius = BorderRadius.all(Radius.circular(lg));
  static const fieldRadius = BorderRadius.all(Radius.circular(md));
}
