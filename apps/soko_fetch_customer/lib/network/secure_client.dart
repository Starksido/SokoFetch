import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

/// Singleton Dio client with:
///   - JWT auto-attach on every request
///   - 401 → auto-refresh via refresh token
///   - Security headers
class SecureApiClient {
  SecureApiClient._();
  static final SecureApiClient instance = SecureApiClient._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  late final Dio _dio = _buildDio();

  Dio get dio => _dio;

  Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl:        AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept':       'application/json',
      },
    ));

    // Attach JWT + handle 401 refresh
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (opts, handler) async {
        final token = await _storage.read(key: AppConfig.keyAccessToken);
        if (token != null) {
          opts.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(opts);
      },
      onError: (err, handler) async {
        if (err.response?.statusCode == 401) {
          // Try refresh
          try {
            final refreshed = await _refreshToken();
            if (refreshed) {
              // Retry original request with new token
              final token = await _storage.read(key: AppConfig.keyAccessToken);
              err.requestOptions.headers['Authorization'] = 'Bearer $token';
              final response = await dio.fetch(err.requestOptions);
              return handler.resolve(response);
            }
          } catch (_) {}
        }
        handler.next(err);
      },
    ));

    return dio;
  }

  Future<bool> _refreshToken() async {
    final refreshToken = await _storage.read(key: AppConfig.keyRefreshToken);
    if (refreshToken == null) return false;

    try {
      final resp = await Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl))
          .post('/auth/token/refresh', data: {'refresh_token': refreshToken});
      final data = resp.data as Map<String, dynamic>;
      await _storage.write(key: AppConfig.keyAccessToken,  value: data['access_token']  as String);
      await _storage.write(key: AppConfig.keyRefreshToken, value: data['refresh_token'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Convenience methods ───────────────────────────────────────────────────
  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> delete(String path) => _dio.delete(path);

  // ── Token management ─────────────────────────────────────────────────────
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String role,
  }) async {
    await _storage.write(key: AppConfig.keyAccessToken,  value: accessToken);
    await _storage.write(key: AppConfig.keyRefreshToken, value: refreshToken);
    await _storage.write(key: AppConfig.keyUserId,       value: userId);
    await _storage.write(key: AppConfig.keyUserRole,     value: role);
  }

  static Future<void> clearTokens() async {
    await _storage.deleteAll();
  }

  static Future<String?> getAccessToken() =>
      _storage.read(key: AppConfig.keyAccessToken);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: AppConfig.keyRefreshToken);

  static Future<bool> get isAuthenticated async {
    final token = await getAccessToken();
    return token != null;
  }
}

