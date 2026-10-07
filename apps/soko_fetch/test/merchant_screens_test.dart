import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_fetch/core/api_client.dart';
import 'package:soko_fetch/features/merchant/models/models.dart';
import 'package:soko_fetch/features/merchant/providers/providers.dart';
import 'package:soko_fetch/features/merchant/routes.dart';
import 'package:soko_fetch/features/merchant/screens/dashboard/dashboard_screen.dart';
import 'package:soko_fetch/features/merchant/screens/earnings/earnings_screen.dart';
import 'package:soko_fetch/features/merchant/screens/menu/menu_screen.dart';
import 'package:soko_fetch/features/merchant/screens/onboarding/onboarding_screen.dart';
import 'package:soko_fetch/features/merchant/screens/profile/profile_screen.dart';

import 'helpers.dart';
import 'ui_helpers.dart';

Order _order(String id, String status, {String payment = 'paid'}) => Order.fromJson({
      'id': '$id-0000-0000',
      'customer_id': 'cu1',
      'merchant_id': 'm1',
      'items': [
        {'item_id': 'i1', 'name': 'Sukuma wiki (bunch)', 'qty': 2, 'subtotal': 60},
        {'item_id': 'i2', 'name': 'Tomatoes (1 kg)', 'qty': 1, 'subtotal': 120},
      ],
      'item_count': 3,
      'subtotal': '180',
      'delivery_fee': '87.94',
      'total': '267.94',
      'merchant_commission': '36',
      'payment_method': 'mpesa',
      'payment_status': payment,
      'delivery_address': 'Kileleshwa, Othaya Road',
      'special_instructions': 'Please pack the tomatoes separately',
      'status': status,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

final _orders = [
  _order('aaaa1111', 'pending'),
  _order('bbbb2222', 'pending', payment: 'pending'),
  _order('cccc3333', 'preparing'),
  _order('dddd4444', 'ready_for_pickup'),
];

List<Override> _overrides() => [
      merchantProfileProvider.overrideWith((ref) async => MerchantProfile.fromJson({
            'id': 'm1',
            'shop_name': 'Mama Mboga Greens & Fresh Produce',
            'category': 'grocery',
            'address': 'Stall 12, Westlands Market, Nairobi',
            'status': 'active',
            'is_open': true,
            'rating': '4.7',
            'rating_count': 38,
            'avg_prep_minutes': 20,
            'commission_rate': '20',
            'payout_phone': '+254700000101',
          })),
      liveOrdersProvider.overrideWith((ref) async => _orders),
      todayEarningsProvider.overrideWith((ref) async => {
            'total_orders': 7,
            'gross_revenue': '4380',
            'commission_deducted': '876',
            'net_payout': '3504',
          }),
      weeklyEarningsProvider.overrideWith((ref) async => [
            for (var i = 1; i <= 7; i++)
              DailyEarnings.fromJson({
                'date': '2026-10-0$i',
                'total_orders': i,
                'gross_revenue': '${i * 600}',
                'commission_deducted': '${i * 120}',
                'net_payout': '${i * 480}',
              }),
          ]),
      menuProvider.overrideWith((ref) async => [
            for (final (id, name, cat, price, ok) in [
              ('i1', 'Sukuma wiki (bunch)', 'Vegetables', 30, true),
              ('i2', 'Tomatoes (1 kg)', 'Vegetables', 120, true),
              ('i3', 'Avocados (4 pcs) — Hass, ripe today', 'Fruit', 100, false),
            ])
              MenuItem.fromJson({
                'id': id,
                'name': name,
                'category': cat,
                'price': '$price',
                'is_available': ok,
              }),
          ]),
    ];

void main() {
  setUpAll(loadAppFont);
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.dio.httpClientAdapter =
        FakeAdapter((o) async => jsonBody(200, {'is_open': true}));
    // Keep-awake and sound plugins have no test implementation
    for (final channel in [
      'dev.fluttercommunity.plus/wakelock_plus',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });

  testWidgets('dashboard: new orders with accept, decline and payment wait',
      (tester) async {
    await pumpAt(tester, const DashboardScreen(), const Size(412, 915),
        overrides: _overrides());
    expect(find.text('New · 2'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Waiting for payment'), findsOneWidget);
    expect(find.text('Decline'), findsNWidgets(2));
  });

  testWidgets('tablet: side rail and order split view', (tester) async {
    await pumpAt(tester, const MerchantShell(), const Size(1280, 800),
        overrides: _overrides());
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // The first new order is open on the right
    expect(find.text('Accept'), findsOneWidget);
  });

  testWidgets('shop tab names the category', (tester) async {
    await pumpAt(tester, const ProfileScreen(), const Size(360, 800),
        overrides: _overrides());
    expect(find.text('Grocery'), findsOneWidget);
  });

  testWidgets("dashboard shows today's takings in full on a small phone",
      (tester) async {
    await pumpAt(tester, const DashboardScreen(), const Size(360, 800),
        overrides: _overrides());
    final takings = find.text('KES 4,380');
    expect(takings, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(takings).didExceedMaxLines,
        isFalse);
  });

  group('merchant screens lay out at every size', () {
    final screens = <String, Widget>{
      'dashboard': const DashboardScreen(),
      'shell': const MerchantShell(),
      'menu': const MenuScreen(),
      'earnings': const EarningsScreen(),
      'shop profile': const ProfileScreen(),
      'add item': const AddEditItemScreen(),
      'onboarding': const OnboardingScreen(),
    };
    for (final MapEntry(key: name, value: screen) in screens.entries) {
      for (final size in kScreenSizes) {
        testWidgets('$name at ${size.width.toInt()}x${size.height.toInt()}',
            (tester) async {
          expect(await pumpAt(tester, screen, size, overrides: _overrides()),
              isEmpty);
        });
      }
      testWidgets('$name with large text', (tester) async {
        expect(
            await pumpAt(tester, screen, const Size(360, 800),
                textScale: 1.3, overrides: _overrides()),
            isEmpty);
      });
    }
  });
}
