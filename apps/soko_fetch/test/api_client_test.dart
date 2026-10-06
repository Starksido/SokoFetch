import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_fetch/core/api_client.dart';
import 'package:soko_fetch/core/token_store.dart';

import 'helpers.dart';

/// A server whose current access token is [validAccess]. Refreshing with
/// [validRefresh] rotates both tokens; any other refresh token is rejected.
class FakeServer {
  String validAccess = 'A2';
  String validRefresh = 'R1';
  int refreshes = 0;
  bool offline = false;
  bool alwaysUnauthorized = false;

  late final adapter = FakeAdapter((o) async {
    if (offline) {
      throw DioException.connectionError(
          requestOptions: o, reason: 'offline');
    }
    if (o.path == '/auth/token/refresh') {
      refreshes++;
      await Future.delayed(const Duration(milliseconds: 20));
      if ((o.data as Map)['refresh_token'] != validRefresh) {
        return jsonBody(401, {
          'detail': {'code': 'TOKEN_REVOKED', 'message': 'revoked'}
        });
      }
      validAccess = 'A${refreshes + 2}';
      validRefresh = 'R${refreshes + 1}';
      return jsonBody(200,
          tokenJson(access: validAccess, refresh: validRefresh));
    }
    final auth = o.headers['Authorization'];
    if (alwaysUnauthorized || auth != 'Bearer $validAccess') {
      return jsonBody(401, {
        'detail': {'code': 'TOKEN_EXPIRED', 'message': 'expired'}
      });
    }
    return jsonBody(200, {'ok': o.path});
  });
}

void main() {
  late FakeServer server;
  late TokenStore store;
  late ApiClient api;
  late int expired;

  setUp(() {
    // The stored access token 'A1' is out of date; the server wants 'A2'
    FlutterSecureStorage.setMockInitialValues({
      'sf_access_token': 'A1',
      'sf_refresh_token': 'R1',
      'sf_user_id': 'u1',
      'sf_user_role': 'customer',
    });
    server = FakeServer();
    store = TokenStore();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = server.adapter;
    final refreshDio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = server.adapter;
    expired = 0;
    api = ApiClient(
      store: store,
      dio: dio,
      refreshDio: refreshDio,
      onSessionExpired: () async => expired++,
    );
  });

  test('parallel 401s share one refresh and every request is retried', () async {
    server.validAccess = 'stale-until-refresh';
    final results = await Future.wait([
      api.get('/orders'),
      api.get('/customer/me'),
      api.get('/merchant/browse'),
    ]);

    expect(server.refreshes, 1);
    expect(results.map((r) => r.data['ok']),
        ['/orders', '/customer/me', '/merchant/browse']);
  });

  test('stores the rotated refresh token', () async {
    server.validAccess = 'stale-until-refresh';
    await api.get('/orders');
    expect(await store.refreshToken, 'R2');
    expect(await store.accessToken, server.validAccess);

    // The next expiry refreshes with the new token, not the used one
    server.validAccess = 'stale-again';
    await api.get('/orders');
    expect(server.refreshes, 2);
    expect(expired, 0);
  });

  test('retries a request at most once', () async {
    server.alwaysUnauthorized = true;
    await expectLater(api.get('/orders'), throwsA(isA<DioException>()));
    expect(server.refreshes, 1);
    expect(server.adapter.count('/orders'), 2);
  });

  test('never refreshes for /auth calls', () async {
    server.validAccess = 'nobody';
    await expectLater(
        api.post('/auth/otp/verify', data: {}), throwsA(isA<DioException>()));
    expect(server.refreshes, 0);
  });

  test('a rejected refresh ends the session', () async {
    server.validAccess = 'stale-until-refresh';
    server.validRefresh = 'something-else';
    await expectLater(api.get('/orders'), throwsA(isA<DioException>()));

    expect(expired, 1);
    expect(await store.refreshToken, isNull);
    expect(await store.accessToken, isNull);
  });

  test('a network failure keeps the session', () async {
    server.offline = true;
    expect(await api.refreshSession(), isFalse);

    expect(expired, 0);
    expect(await store.refreshToken, isNotNull);
  });
}
