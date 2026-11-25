import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists auth tokens and the selected unit. Values are cached in memory.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage, this.persistent = true})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// When false, values live in memory only (tests).
  final bool persistent;
  String? access;
  String? refresh;
  String? unitId;

  /// True once the intro slides were shown on this device. Survives logout.
  bool onboardingSeen = false;
  bool _loaded = false;

  static const _kAccess = 'access';
  static const _kRefresh = 'refresh';
  static const _kUnit = 'unit_id';
  static const _kOnboarding = 'onboarding_seen';

  Future<void> load() async {
    if (_loaded || !persistent) return;
    try {
      access = await _storage.read(key: _kAccess);
      refresh = await _storage.read(key: _kRefresh);
      unitId = await _storage.read(key: _kUnit);
      onboardingSeen = await _storage.read(key: _kOnboarding) == '1';
    } catch (_) {
      // Storage can be unavailable (e.g. private browsing); fall back to memory only.
    }
    _loaded = true;
  }

  Future<void> saveTokens(String access, String? refresh) async {
    this.access = access;
    if (refresh != null) this.refresh = refresh;
    await _write(_kAccess, access);
    if (refresh != null) await _write(_kRefresh, refresh);
  }

  Future<void> saveUnit(String? id) async {
    unitId = id;
    await _write(_kUnit, id);
  }

  Future<void> markOnboardingSeen() async {
    onboardingSeen = true;
    await _write(_kOnboarding, '1');
  }

  /// Signs out: removes tokens and the selected unit, keeps device preferences.
  Future<void> clear() async {
    access = refresh = unitId = null;
    for (final key in [_kAccess, _kRefresh, _kUnit]) {
      await _write(key, null);
    }
  }

  Future<void> _write(String key, String? value) async {
    if (!persistent) return;
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {}
  }
}
