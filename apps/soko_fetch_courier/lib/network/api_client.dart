import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  late final Dio dio = _build();

  Dio _build() {
    final d = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ));
    d.interceptors.add(InterceptorsWrapper(
      onRequest: (opts, handler) async {
        final t = await _storage.read(key: AppConfig.keyAccessToken);
        if (t != null) opts.headers['Authorization'] = 'Bearer $t';
        handler.next(opts);
      },
      onError: (err, handler) async {
        if (err.response?.statusCode == 401 && await _refresh()) {
          final t = await _storage.read(key: AppConfig.keyAccessToken);
          err.requestOptions.headers['Authorization'] = 'Bearer $t';
          try {
            return handler.resolve(await d.fetch(err.requestOptions));
          } catch (_) {}
        }
        handler.next(err);
      },
    ));
    return d;
  }

  Future<bool> _refresh() async {
    final rt = await _storage.read(key: AppConfig.keyRefreshToken);
    if (rt == null) return false;
    try {
      final resp = await Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl))
          .post('/auth/token/refresh', data: {'refresh_token': rt});
      final data = resp.data as Map<String, dynamic>;
      await _storage.write(key: AppConfig.keyAccessToken,  value: data['access_token']  as String);
      await _storage.write(key: AppConfig.keyRefreshToken, value: data['refresh_token'] as String);
      return true;
    } catch (_) { return false; }
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      dio.get(path, queryParameters: params);
  Future<Response> post(String path, {dynamic data}) => dio.post(path, data: data);
  Future<Response> put(String path,  {dynamic data}) => dio.put(path,  data: data);

  static Future<void> saveTokens({required String access, required String refresh, required String userId}) async {
    await _storage.write(key: AppConfig.keyAccessToken,  value: access);
    await _storage.write(key: AppConfig.keyRefreshToken, value: refresh);
    await _storage.write(key: AppConfig.keyUserId,       value: userId);
  }
  static Future<void> clearTokens() => _storage.deleteAll();
  static Future<String?> getToken() => _storage.read(key: AppConfig.keyAccessToken);
  static Future<bool> get isAuthenticated async => (await getToken()) != null;
}
