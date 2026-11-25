import 'package:flutter/foundation.dart';

/// Backend location.
///
/// Defaults: web / iOS simulator / desktop -> localhost, Android emulator -> 10.0.2.2.
/// For a real phone, run with your Mac's LAN address:
///   flutter run --dart-define=API_URL=http://192.168.1.20:8000
class Env {
  Env._();

  static const _override = String.fromEnvironment('API_URL');

  static String get apiBase {
    if (_override.isNotEmpty) return _override;
    // Web dashboard: the API runs on the same machine that serves the page, on port 8000.
    if (kIsWeb && Uri.base.host.isNotEmpty) return '${Uri.base.scheme}://${Uri.base.host}:8000';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  static String get apiUrl => '$apiBase/api/v1';

  static String get wsUrl => '${apiBase.replaceFirst('http', 'ws')}/ws/notifications/';
}
