import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'google_sign_in.dart';
import 'models.dart';

/// Bumped whenever the session ends. The root ProviderScope is keyed on it,
/// so every provider (cart, orders, profile...) and every screen is thrown
/// away and the app starts again from the splash screen.
final sessionGeneration = ValueNotifier<int>(0);

/// The signed-in user, set at login. Null after an app restart until
/// something sets it again; screens should not rely on it for data.
final currentUserProvider = StateProvider<UserProfile?>((ref) => null);

class Session {
  Session._();

  static ApiClient get _api => ApiClient.instance;

  /// Call once at startup.
  static void init() {
    _api.onSessionExpired = () async => _restart();
  }

  static Future<bool> get hasSession async =>
      (await _api.store.refreshToken) != null;

  static Future<String?> get role => _api.store.role;

  static Future<void> start(AuthTokens tokens) => _api.store.save(tokens);

  /// Always succeeds locally, even offline: the server calls are best effort.
  static Future<void> logout() async {
    final store = _api.store;
    final refreshToken = await store.refreshToken;
    final role = await store.role;

    if (role == 'courier') {
      // Don't leave the rider listed as available
      await _quietly(() => _api.put('/courier/offline'));
    }
    if (refreshToken != null) {
      await _quietly(() =>
          _api.post('/auth/logout', data: {'refresh_token': refreshToken}));
    }
    await _quietly(() => GoogleSignInService.instance.signOut());

    await store.clear();
    _restart();
  }

  static void _restart() => sessionGeneration.value++;

  static Future<void> _quietly(Future<void> Function() call) async {
    try {
      await call().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}
