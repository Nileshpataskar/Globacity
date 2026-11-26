import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../core/config/env.dart';
import 'json.dart';
import 'token_store.dart';

/// Error with a user-presentable message extracted from the API response.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Machine-readable reason from the API, e.g. `not_registered`.
  final String? code;

  @override
  String toString() => message;
}

/// Thin wrapper over Dio: base URL, JWT + X-Unit-ID headers, token refresh, error mapping.
class ApiClient {
  ApiClient(this.tokens, {this.onSessionExpired}) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  final TokenStore tokens;
  void Function()? onSessionExpired;

  final _dio = Dio(BaseOptions(
    baseUrl: Env.apiUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    contentType: Headers.jsonContentType,
  ));

  Future<void>? _refreshing;

  void _onRequest(RequestOptions o, RequestInterceptorHandler h) {
    if (tokens.access != null && o.extra['auth'] != false) o.headers['Authorization'] = 'Bearer ${tokens.access}';
    final unit = o.extra['unit'] as String?;
    if (unit != null) o.headers['X-Unit-ID'] = unit;
    h.next(o);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler h) async {
    final o = e.requestOptions;
    final canRefresh = e.response?.statusCode == 401 && tokens.refresh != null && o.extra['retried'] != true &&
        !o.path.startsWith('/auth/');
    if (!canRefresh) return h.next(e);
    try {
      await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
      o.extra['retried'] = true;
      h.resolve(await _dio.fetch(o));
    } on DioException catch (err) {
      // Only sign out when the server rejects the refresh token. A network blip
      // (no Wi-Fi, cable unplugged, backend restarting) must keep the user signed in.
      final rejected = err.requestOptions.path.endsWith('/auth/token/refresh/') &&
          (err.response?.statusCode == 401 || err.response?.statusCode == 400);
      if (rejected) {
        await tokens.clear();
        onSessionExpired?.call();
        return h.next(e);
      }
      h.next(err);
    } catch (_) {
      h.next(e);
    }
  }

  Future<void> _refresh() async {
    final res = await Dio(BaseOptions(baseUrl: Env.apiUrl))
        .post<Json>('/auth/token/refresh/', data: {'refresh': tokens.refresh});
    await tokens.saveTokens(res.data!['access'] as String, res.data!['refresh'] as String?);
  }

  Future<T> _send<T>(Future<Response<dynamic>> Function() call) async {
    try {
      return (await call()).data as T;
    } on DioException catch (e) {
      final data = e.response?.data;
      throw ApiException(_message(e), statusCode: e.response?.statusCode,
          code: data is Map && data['code'] is String ? data['code'] as String : null);
    }
  }

  Options _opts(String? unit, {bool auth = true}) => Options(extra: {'unit': unit, 'auth': auth});

  Future<dynamic> get(String path, {Map<String, dynamic>? query, String? unit}) =>
      _send(() => _dio.get(path, queryParameters: _clean(query), options: _opts(unit)));

  Future<dynamic> post(String path, {Object? data, String? unit, bool auth = true}) =>
      _send(() => _dio.post(path, data: data ?? {}, options: _opts(unit, auth: auth)));

  Future<dynamic> patch(String path, {Object? data, String? unit}) =>
      _send(() => _dio.patch(path, data: data, options: _opts(unit)));

  Future<void> delete(String path, {String? unit}) => _send(() => _dio.delete(path, options: _opts(unit)));

  /// Multipart request with [files] (field name -> picked file) and plain [fields].
  Future<dynamic> upload(String path, {Map<String, Object?> fields = const {}, Map<String, XFile> files = const {},
      bool patch = false, String? unit}) async {
    final form = FormData();
    fields.forEach((k, v) {
      if (v != null) form.fields.add(MapEntry(k, v.toString()));
    });
    for (final e in files.entries) {
      form.files.add(MapEntry(e.key, MultipartFile.fromBytes(await e.value.readAsBytes(), filename: e.value.name)));
    }
    final options = _opts(unit).copyWith(contentType: 'multipart/form-data');
    return _send(() => patch ? _dio.patch(path, data: form, options: options) : _dio.post(path, data: form, options: options));
  }

  /// GET a list endpoint (paginated or not) and map each item.
  Future<List<T>> list<T>(String path, T Function(Json) fromJson, {Map<String, dynamic>? query, String? unit}) async {
    final data = await get(path, query: {'page_size': 100, ...?query}, unit: unit);
    final items = data is Map && data['results'] is List ? data['results'] as List : data as List;
    return items.map((e) => fromJson(e as Json)).toList();
  }

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) =>
      q == null ? null : (Map.of(q)..removeWhere((_, v) => v == null || v == ''));

  static String _message(DioException e) {
    final data = e.response?.data;
    if (e.response == null) {
      return e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError
          ? 'Cannot reach the server. Is the backend running at ${Env.apiBase}?'
          : 'Network error. Please try again.';
    }
    String? pick(dynamic v) {
      if (v is String) return v;
      if (v is List && v.isNotEmpty) return pick(v.first);
      if (v is Map) {
        if (v['detail'] != null) return pick(v['detail']);
        for (final entry in v.entries) {
          final msg = pick(entry.value);
          if (msg != null) return msg;
        }
      }
      return null;
    }

    return pick(data) ?? 'Something went wrong (${e.response?.statusCode}).';
  }
}
