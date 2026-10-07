import 'kv_store_memory.dart' if (dart.library.js_interop) 'kv_store_web.dart';

/// Admin-panel tokens. In the browser they live in this tab's
/// sessionStorage, so closing the tab ends the session; nothing is kept
/// long-term on the machine.
class TokenStore {
  TokenStore([KeyValueStore? kv]) : _kv = kv ?? KeyValueStore();

  final KeyValueStore _kv;

  static const _access = 'sf_admin_access_token';
  static const _refresh = 'sf_admin_refresh_token';

  Future<String?> get accessToken async => _kv.read(_access);
  Future<String?> get refreshToken async => _kv.read(_refresh);

  /// The server rotates the refresh token on every refresh, so both are
  /// always replaced together.
  Future<void> saveTokens({required String access, required String refresh}) async {
    _kv.write(_access, access);
    _kv.write(_refresh, refresh);
  }

  Future<void> clear() async {
    _kv.delete(_access);
    _kv.delete(_refresh);
  }
}
