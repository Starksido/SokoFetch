import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_fetch/features/courier/models/models.dart';
import 'package:soko_fetch/features/courier/providers/providers.dart';
import 'package:soko_fetch/features/courier/screens/delivery/proof_screen.dart';
import 'package:soko_fetch/features/courier/screens/dispatch/home_screen.dart';
import 'package:soko_fetch/features/courier/screens/documents/documents_screen.dart';
import 'package:soko_fetch/features/courier/screens/earnings/earnings_screen.dart';
import 'package:soko_fetch/features/courier/screens/profile/profile_screen.dart';

import 'ui_helpers.dart';

CourierProfile _profile({String status = 'active', int docs = 5}) =>
    CourierProfile.fromJson({
      'id': 'c1',
      'user_id': 'u1',
      'status': status,
      'vehicle_type': 'motorcycle',
      'vehicle_plate': 'KMDA 123A',
      'full_name': 'Juma Otieno',
      'is_online': true,
      'rating': '4.9',
      'total_earned': '12480',
      'pending_payout': '640',
      'total_deliveries': 132,
      'documents': [
        for (final d in kRequiredDocs.take(docs))
          {
            'id': d,
            'doc_type': d,
            'is_verified': status == 'active',
            'uploaded_at': '2026-10-07T08:00:00Z',
          },
      ],
    });

Order _order(String status) => Order.fromJson({
      'id': 'o1',
      'merchant_id': 'm1',
      'customer_id': 'cu1',
      'status': status,
      'payment_method': 'mpesa',
      'delivery_address': 'Kileleshwa, Othaya Road, Apt 4B',
      'delivery_notes': 'Call on arrival',
      'special_instructions': 'Fragile: eggs',
      'items': [],
      'item_count': 3,
      'total': '377.25',
      'courier_payout': '87.94',
      'subtotal': '300',
      'delivery_latitude': '-1.2789',
      'delivery_longitude': '36.7848',
      'created_at': '2026-10-07T09:00:00Z',
      'merchant_name': 'Mama Mboga Greens',
      'merchant_address': 'Stall 12, Westlands Market',
      'merchant_lat': '-1.2676',
      'merchant_lon': '36.8108',
    });

final _jobs = [
  CourierJob.fromJson({
    'order_id': 'o2',
    'status': 'ready_for_pickup',
    'merchant_name': 'Kibanda Grill & Fresh Juice Corner',
    'merchant_address': 'Moi Avenue, opposite Hilton, Nairobi CBD',
    'item_count': 2,
    'courier_payout': '61.62',
    'pickup_distance_km': 1.4,
    'delivery_distance_km': 3.8,
  }),
  CourierJob.fromJson({
    'order_id': 'o3',
    'status': 'preparing',
    'merchant_name': 'Mama Mboga Greens',
    'merchant_address': 'Stall 12, Westlands Market',
    'item_count': 1,
    'courier_payout': '97.29',
  }),
];

List<Override> _overrides(
        {CourierProfile? profile, Order? order, bool online = false}) =>
    [
      courierProfileProvider.overrideWith((ref) async => profile ?? _profile()),
      activeOrderProvider.overrideWith((ref) async => order),
      earningsProvider.overrideWith((ref) async => {
            'deliveries': 6,
            'earned': '512.40',
            'pending_payout': '640',
            'total_earned': '12480',
          }),
      earningsHistoryProvider.overrideWith((ref) async => [
            for (var i = 1; i <= 14; i++)
              EarningsDay.fromJson({
                'date': '2026-10-${i.toString().padLeft(2, '0')}',
                'deliveries': i % 3,
                'earned': '${(i % 3) * 85}',
              }),
          ]),
      availableJobsProvider.overrideWith((ref) async => _jobs),
      onlineProvider.overrideWith((ref) => OnlineNotifier()..set(online)),
    ];

void main() {
  setUpAll(loadAppFont);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('in transit: confirm delivery and navigate to the customer',
      (tester) async {
    final errors = await pumpAt(tester, const HomeScreen(), const Size(360, 800),
        overrides: _overrides(order: _order('in_transit')));
    expect(errors, isEmpty);
    expect(find.text('Confirm Delivery'), findsOneWidget);
    expect(find.text('Navigate to Customer'), findsOneWidget);
  });

  // Regression: with the keyboard up the card had ~235px and overflowed
  for (final status in ['in_transit', 'ready_for_pickup', 'confirmed']) {
    testWidgets('$status card fits a short screen by scrolling', (tester) async {
      final errors = await pumpAt(
          tester, const HomeScreen(), const Size(360, 420),
          overrides: _overrides(order: _order(status)));
      expect(errors, isEmpty);

      final button = status == 'in_transit'
          ? 'Navigate to Customer'
          : 'Navigate to Merchant';
      // Drag the delivery sheet until the button is built and on screen
      await tester.scrollUntilVisible(find.text(button), 120,
          scrollable: find
              .descendant(
                  of: find.byType(DraggableScrollableSheet),
                  matching: find.byType(Scrollable))
              .first);
      await tester.ensureVisible(find.text(button));
      await tester.pumpAndSettle();
      expect(find.text(button).hitTestable(), findsOneWidget);
    });
  }

  testWidgets('online with no delivery lists jobs to accept', (tester) async {
    await pumpAt(tester, const HomeScreen(), const Size(412, 915),
        overrides: _overrides(online: true));
    expect(find.text("You're online"), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Kibanda Grill & Fresh Juice Corner'), findsOneWidget);
    expect(find.text('Accept'), findsWidgets);
  });

  testWidgets('offline shows the Go button and today\'s earnings', (tester) async {
    await pumpAt(tester, const HomeScreen(), const Size(412, 915),
        overrides: _overrides());
    expect(find.text('GO'), findsOneWidget);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('KES 512.40'), findsOneWidget);
  });

  group('courier screens lay out at every size', () {
    final cases = <String, (Widget, List<Override>, Object?)>{
      'offline home': (const HomeScreen(), _overrides(), null),
      'job board': (const HomeScreen(), _overrides(online: true), null),
      'ready for pickup':
          (const HomeScreen(), _overrides(order: _order('ready_for_pickup')), null),
      'documents needed': (
        const HomeScreen(),
        _overrides(profile: _profile(status: 'registered', docs: 2)),
        null
      ),
      'earnings': (const EarningsScreen(), _overrides(), null),
      'profile': (const ProfileScreen(), _overrides(), null),
      'documents': (
        const DocumentsScreen(),
        _overrides(profile: _profile(status: 'documents_submitted', docs: 3)),
        null
      ),
      'proof': (const ProofOfDeliveryScreen(), _overrides(), _order('in_transit')),
    };
    for (final MapEntry(key: name, value: (screen, overrides, args))
        in cases.entries) {
      for (final size in kScreenSizes) {
        testWidgets('$name at ${size.width.toInt()}x${size.height.toInt()}',
            (tester) async {
          expect(
              await pumpAt(tester, screen, size,
                  overrides: overrides, arguments: args),
              isEmpty);
        });
      }
      testWidgets('$name with large text', (tester) async {
        expect(
            await pumpAt(tester, screen, const Size(360, 800),
                textScale: 1.3, overrides: overrides, arguments: args),
            isEmpty);
      });
    }
  });
}
