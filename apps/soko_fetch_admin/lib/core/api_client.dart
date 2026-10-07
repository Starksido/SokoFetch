import 'package:dio/dio.dart';

import 'config.dart';
import 'token_store.dart';

/// The HTTP client for the admin panel. Same refresh rules as the phone
/// app's client, against the admin login (/admin/auth):
///
/// - Attaches the access token to every request.
/// - On a 401 it refreshes the session once, however many requests failed at
///   the same time, then retries each request once.
/// - /admin/auth/* calls are never refreshed.
/// - If the server rejects the refresh token the session is over: tokens are
///   cleared and [onSessionExpired] runs. A network failure keeps the session.
class ApiClient {
  ApiClient({TokenStore? store, Dio? dio, Dio? refreshDio, this.onSessionExpired})
      : store = store ?? TokenStore(),
        dio = dio ?? Dio(_options()),
        _refreshDio = refreshDio ?? Dio(_options()) {
    this.dio.interceptors.add(
          InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
        );
  }

  static final ApiClient instance = ApiClient();

  final TokenStore store;
  final Dio dio;
  final Dio _refreshDio; // No interceptors, so a refresh can't recurse
  Future<void> Function()? onSessionExpired;

  Future<bool>? _refreshing;
  static const _retriedKey = 'sf_retried';

  static BaseOptions _options() => BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      );

  static bool _isAuthCall(RequestOptions o) => o.path.startsWith('/admin/auth/');

  Future<void> _onRequest(
      RequestOptions o, RequestInterceptorHandler handler) async {
    final token = await store.accessToken;
    if (token != null) o.headers['Authorization'] = 'Bearer $token';
    handler.next(o);
  }

  Future<void> _onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    if (err.response?.statusCode != 401 ||
        _isAuthCall(o) ||
        o.extra[_retriedKey] == true) {
      return handler.next(err);
    }

    // If another request refreshed while this one was in flight, the stored
    // token is already newer than the one this request used: just retry.
    var token = await store.accessToken;
    if (token == null || o.headers['Authorization'] == 'Bearer $token') {
      if (!await refreshSession()) return handler.next(err);
      token = await store.accessToken;
    }

    o.extra[_retriedKey] = true;
    o.headers['Authorization'] = 'Bearer $token';
    if (o.data is FormData) o.data = (o.data as FormData).clone();
    try {
      handler.resolve(await dio.fetch(o));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Exchanges the refresh token for a new pair. Concurrent callers share one
  /// request. Returns false if there is no usable session.
  Future<bool> refreshSession() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<bool> _refresh() async {
    final refreshToken = await store.refreshToken;
    if (refreshToken == null) {
      await _expire();
      return false;
    }
    try {
      final resp = await _refreshDio.post('/admin/auth/token/refresh',
          data: {'refresh_token': refreshToken});
      final data = resp.data as Map<String, dynamic>;
      await store.saveTokens(
        access: data['access_token'] as String,
        refresh: data['refresh_token'] as String,
      );
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Expired, revoked, reused or disabled: the server has ended the session
      if (status != null && status >= 400 && status < 500) await _expire();
      return false;
    }
  }

  Future<void> _expire() async {
    await store.clear();
    await onSessionExpired?.call();
  }

  // ── Convenience methods ───────────────────────────────────────────────────
  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) => dio.put(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      dio.patch(path, data: data);

  Future<Response> delete(String path) => dio.delete(path);

  /// Raw bytes, e.g. an image the server streams back.
  Future<List<int>> getBytes(String path) async {
    final resp = await dio.get<List<int>>(path,
        options: Options(responseType: ResponseType.bytes));
    return resp.data ?? const [];
  }
}
