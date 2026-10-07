import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_fetch/core/api_client.dart';
import 'package:soko_fetch/core/session.dart';
import 'package:soko_fetch/features/auth/role_picker_screen.dart';
import 'package:soko_fetch/features/auth/splash_screen.dart';

import 'helpers.dart';

/// Any route other than the screen under test renders its name.
Route<dynamic> _routeName(RouteSettings s) => MaterialPageRoute(
    builder: (_) => Scaffold(body: Text('route:${s.name}')), settings: s);

FakeAdapter _serve(ResponseBody Function(RequestOptions o) handler) {
  final adapter = FakeAdapter((o) async => handler(o));
  ApiClient.instance.dio.httpClientAdapter = adapter;
  return adapter;
}

void main() {
  group('Splash routing', () {
    Future<void> pumpSplash(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: _routeName,
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute(
              builder: (_) => const SplashScreen(delay: Duration.zero)),
        ],
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no session goes to welcome', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await pumpSplash(tester);
      expect(find.text('route:/welcome'), findsOneWidget);
    });

    testWidgets('merchant with a shop goes to the merchant area', (tester) async {
      FlutterSecureStorage.setMockInitialValues(storedSession(role: 'merchant'));
      final adapter = _serve((o) => jsonBody(200, {'id': 'm1'}));
      await pumpSplash(tester);
      expect(find.text('route:/merchant'), findsOneWidget);
      expect(adapter.requests.single.path, '/merchant/me');
    });

    testWidgets('courier without a profile goes to onboarding', (tester) async {
      FlutterSecureStorage.setMockInitialValues(storedSession(role: 'courier'));
      _serve((o) => jsonBody(404, {
            'detail': {'code': 'NOT_FOUND', 'message': 'no courier'}
          }));
      await pumpSplash(tester);
      expect(find.text('route:/courier/onboarding'), findsOneWidget);
    });

    testWidgets('an old admin session is logged out', (tester) async {
      // Admins use the separate admin panel now
      FlutterSecureStorage.setMockInitialValues(storedSession(role: 'admin'));
      _serve((o) => jsonBody(200, {'message': 'Logged out successfully'}));
      final before = sessionGeneration.value;
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: _routeName,
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute(
              builder: (_) => const SplashScreen(delay: Duration.zero)),
        ],
      ));
      // The spinner never settles here: in the app, SessionScope rebuilds
      // everything when the generation changes
      for (var i = 0; i < 20 && sessionGeneration.value == before; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(sessionGeneration.value, before + 1);
      expect(await ApiClient.instance.store.refreshToken, isNull);
    });

    testWidgets('customer without a device lock opens the customer home',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues(storedSession(role: 'customer'));
      _serve((o) => jsonBody(200, {'id': 'c1'}));
      await pumpSplash(tester);
      expect(find.text('route:/customer'), findsOneWidget);
    });

    testWidgets('offline still opens the role home', (tester) async {
      FlutterSecureStorage.setMockInitialValues(storedSession(role: 'merchant'));
      _serve((o) => throw DioException.connectionError(
          requestOptions: o, reason: 'offline'));
      await pumpSplash(tester);
      expect(find.text('route:/merchant'), findsOneWidget);
    });
  });

  group('Role picker', () {
    Future<void> pumpPicker(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          onGenerateRoute: _routeName,
          onGenerateInitialRoutes: (_) => [
            MaterialPageRoute(
              builder: (_) => const RolePickerScreen(),
              settings:
                  const RouteSettings(name: '/auth/role', arguments: 'tok-1'),
            ),
          ],
        ),
      ));
    }

    testWidgets('offers the three roles and needs a choice', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await pumpPicker(tester);

      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('Merchant'), findsOneWidget);
      expect(find.text('Courier'), findsOneWidget);
      expect(find.text('Admin'), findsNothing);

      final button = find.widgetWithText(ElevatedButton, 'Continue');
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    });

    testWidgets('creates the account and opens that role\'s onboarding',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final adapter = _serve((o) =>
          jsonBody(201, tokenJson(role: 'merchant', isNew: true)));
      await pumpPicker(tester);

      await tester.tap(find.text('Merchant'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      final signup = adapter.requests.single;
      expect(signup.path, '/auth/signup');
      expect(signup.data, {'signup_token': 'tok-1', 'role': 'merchant'});
      expect(find.text('route:/merchant/onboarding'), findsOneWidget);
      expect(await ApiClient.instance.store.role, 'merchant');
    });

    testWidgets('an expired sign-up asks the user to start again',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      _serve((o) => jsonBody(400, {
            'detail': {
              'code': 'INVALID_SIGNUP_TOKEN',
              'message': 'Sign-up expired'
            }
          }));
      await pumpPicker(tester);

      await tester.tap(find.text('Courier'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.textContaining('took too long'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Start again'), findsOneWidget);
    });
  });
}
