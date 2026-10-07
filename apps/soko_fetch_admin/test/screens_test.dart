import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_fetch_admin/core/theme.dart';
import 'package:soko_fetch_admin/features/login/login_screen.dart';
import 'package:soko_fetch_admin/features/review/admin_api.dart';
import 'package:soko_fetch_admin/features/review/admin_home_screen.dart';
import 'package:soko_fetch_admin/features/review/rider_review_screen.dart';

final _created = DateTime.utc(2026, 10, 6, 9, 30).toIso8601String();

final _rider = RiderReview.fromJson({
  'id': 'r1',
  'user_id': 'u1',
  'status': 'pending_review',
  'vehicle_type': 'motorcycle',
  'full_name': 'Juma Otieno Wekesa Kamau',
  'vehicle_plate': 'KMDA 123X',
  'rejection_reason': 'The ID photo was too blurry to read',
  'created_at': _created,
  'documents': [
    for (final t in ['national_id_front', 'national_id_back', 'selfie'])
      {'id': t, 'doc_type': t, 'uploaded_at': _created},
  ],
});

List<Override> _overrides() => [
      pendingShopsProvider.overrideWith((ref) async => [
            PendingShop.fromJson({
              'id': 's1',
              'shop_name': 'Mama Mboga Greens & Fresh Produce Westlands',
              'category': 'grocery',
              'address': 'Stall 12, Westlands Market',
              'city': 'Nairobi',
              'status': 'pending_approval',
              'description': 'Fresh vegetables and fruit delivered daily '
                  'from the farm to your door.',
              'payout_phone': '+254700000101',
              'created_at': _created,
            }),
          ]),
      pendingRidersProvider.overrideWith((ref) async => [_rider]),
      riderProvider.overrideWith((ref, id) async => _rider),
      riderDocumentProvider
          .overrideWith((ref, key) async => throw Exception('offline')),
    ];

const _sizes = [Size(320, 640), Size(412, 915), Size(1280, 800)];

/// Pumps [screen] at [size] and [textScale]; returns layout errors.
Future<List<String>> _pumpAt(WidgetTester tester, Widget screen, Size size,
    {double textScale = 1.0}) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError =
      (d) => errors.add(d.toString().split('\n').take(4).join(' '));

  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(),
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      onGenerateRoute: (s) => MaterialPageRoute(
          builder: (_) => Scaffold(body: Text('route:${s.name}'))),
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute(
          builder: (_) => screen,
          settings: const RouteSettings(name: '/rider', arguments: 'r1'),
        ),
      ],
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  // Restore before any expect() runs, or a failure hides the real error
  FlutterError.onError = previous;
  return errors;
}

void main() {
  // The test font draws wide squares; load Inter so widths match browsers
  setUpAll(() async {
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await loader.load();
  });

  testWidgets('shop card offers approve and reject', (tester) async {
    await _pumpAt(tester, const AdminHomeScreen(), const Size(412, 915));
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('rider review lists missing documents and the history',
      (tester) async {
    await _pumpAt(tester, const RiderReviewScreen(), const Size(412, 915));
    expect(find.textContaining('Missing: '), findsOneWidget);
    expect(find.textContaining('Previously rejected'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
  });

  group('admin screens lay out at every size', () {
    final screens = <String, Widget>{
      'login': const LoginScreen(),
      'review lists': const AdminHomeScreen(),
      'rider review': const RiderReviewScreen(),
    };
    for (final MapEntry(key: name, value: screen) in screens.entries) {
      for (final size in _sizes) {
        testWidgets('$name at ${size.width.toInt()}x${size.height.toInt()}',
            (tester) async {
          expect(await _pumpAt(tester, screen, size), isEmpty);
        });
      }
      testWidgets('$name with large text', (tester) async {
        expect(
            await _pumpAt(tester, screen, const Size(360, 800), textScale: 1.3),
            isEmpty);
      });
    }
  });
}
