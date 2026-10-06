import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// Where the session lives on the device.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                  accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _storage;

  static const _access = 'sf_access_token';
  static const _refresh = 'sf_refresh_token';
  static const _userId = 'sf_user_id';
  static const _role = 'sf_user_role';

  Future<String?> get accessToken => _storage.read(key: _access);
  Future<String?> get refreshToken => _storage.read(key: _refresh);
  Future<String?> get role => _storage.read(key: _role);

  Future<void> save(AuthTokens t) async {
    await saveTokens(access: t.accessToken, refresh: t.refreshToken);
    await _storage.write(key: _userId, value: t.user.userId);
    await _storage.write(key: _role, value: t.user.role);
  }

  /// After a refresh: the server rotates the refresh token every time, so
  /// both must be stored or the next refresh is treated as token reuse.
  Future<void> saveTokens({required String access, required String refresh}) async {
    await _storage.write(key: _access, value: access);
    await _storage.write(key: _refresh, value: refresh);
  }

  Future<void> clear() async {
    for (final key in [_access, _refresh, _userId, _role]) {
      await _storage.delete(key: key);
    }
  }
}
