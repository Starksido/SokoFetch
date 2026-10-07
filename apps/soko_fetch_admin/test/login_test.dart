import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_fetch_admin/core/api_client.dart';
import 'package:soko_fetch_admin/core/session.dart';
import 'package:soko_fetch_admin/main.dart';

import 'helpers.dart';

FakeAdapter _serve(ResponseBody Function(RequestOptions o) handler) {
  final adapter = FakeAdapter((o) async => handler(o));
  ApiClient.instance.dio.httpClientAdapter = adapter;
  return adapter;
}

void main() {
  setUp(() => ApiClient.instance.store.clear());

  testWidgets('without a session the login screen is shown', (tester) async {
    await tester.pumpWidget(const SessionScope(child: AdminApp()));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with your admin phone number.'), findsOneWidget);
  });

  testWidgets('logs in with phone and code through /admin/auth', (tester) async {
    final adapter = _serve((o) => switch (o.path) {
          '/admin/auth/otp/request' => jsonBody(200, {'message': 'OTP sent successfully'}),
          '/admin/auth/otp/verify' => jsonBody(200, {
              'access_token': 'admin-access',
              'refresh_token': 'admin-refresh',
              'token_type': 'bearer',
            }),
          _ => jsonBody(200, []),   // The panel's lists, once logged in
        });
    await tester.pumpWidget(const SessionScope(child: AdminApp()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '0746396717');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('a code has been sent'), findsOneWidget);

    final before = sessionGeneration.value;
    await tester.enterText(find.widgetWithText(TextField, '6-digit code'), '492928');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(adapter.requests.map((r) => r.path).take(3),
        ['/admin/auth/otp/request', '/admin/auth/otp/verify', '/admin/merchants']);
    expect(adapter.requests.first.data, {'phone': '+254746396717'});
    expect(adapter.requests[1].data,
        {'phone': '+254746396717', 'otp_code': '492928'});
    expect(await ApiClient.instance.store.refreshToken, 'admin-refresh');
    expect(sessionGeneration.value, before + 1);
    // The panel replaced the login screen and uses the new token
    expect(find.text('No shops waiting for approval'), findsOneWidget);
    expect(adapter.requests[2].headers['Authorization'], 'Bearer admin-access');
  });

  testWidgets('a wrong code shows the server message', (tester) async {
    _serve((o) => o.path == '/admin/auth/otp/request'
        ? jsonBody(200, {'message': 'OTP sent successfully'})
        : jsonBody(400, {
            'detail': {'code': 'INVALID_OTP', 'message': 'Invalid or expired code.'}
          }));
    await tester.pumpWidget(const SessionScope(child: AdminApp()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '0746396717');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '6-digit code'), '000000');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid or expired code.'), findsOneWidget);
    expect(await ApiClient.instance.store.refreshToken, isNull);
  });

  testWidgets('with a session the panel loads the review lists', (tester) async {
    await ApiClient.instance.store.saveTokens(access: 'a', refresh: 'r');
    final adapter = _serve((o) => jsonBody(200, []));
    await tester.pumpWidget(const SessionScope(child: AdminApp()));
    await tester.pumpAndSettle();

    expect(find.text('Shops'), findsOneWidget);
    expect(find.text('No shops waiting for approval'), findsOneWidget);
    expect(adapter.requests.first.headers['Authorization'], 'Bearer a');
  });
}
