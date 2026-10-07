import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Bumped when an admin logs in or out (or the session expires). The app
/// rebuilds from scratch with fresh providers and shows login or the panel.
final sessionGeneration = ValueNotifier<int>(0);

class Session {
  Session._();

  static ApiClient get _api => ApiClient.instance;

  /// Call once at startup.
  static void init() {
    _api.onSessionExpired = () async => restart();
  }

  static Future<bool> get isLoggedIn async =>
      (await _api.store.refreshToken) != null;

  static Future<void> requestCode(String phone) =>
      _api.post('/admin/auth/otp/request', data: {'phone': phone});

  static Future<void> logIn(String phone, String code) async {
    final resp = await _api.post('/admin/auth/otp/verify',
        data: {'phone': phone, 'otp_code': code});
    final data = resp.data as Map<String, dynamic>;
    await _api.store.saveTokens(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
    restart();
  }

  /// Always ends the session locally; the server call is best effort.
  static Future<void> logout() async {
    final refreshToken = await _api.store.refreshToken;
    if (refreshToken != null) {
      try {
        await _api
            .post('/admin/auth/logout', data: {'refresh_token': refreshToken})
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    await _api.store.clear();
    restart();
  }

  static void restart() => sessionGeneration.value++;
}
