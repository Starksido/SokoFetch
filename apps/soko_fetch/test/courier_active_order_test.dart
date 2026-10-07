import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_fetch/features/courier/models/models.dart';
import 'package:soko_fetch/features/courier/providers/providers.dart';
import 'package:soko_fetch/features/courier/screens/dispatch/home_screen.dart';

final _profile = CourierProfile.fromJson({
  'id': 'c1',
  'user_id': 'u1',
  'status': 'active',
  'vehicle_type': 'motorcycle',
  'full_name': 'Juma',
  'is_online': true,
  'rating': '5.0',
  'total_earned': '0',
  'pending_payout': '0',
  'documents': [],
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

/// Layout errors inside the active-order card. Test fonts draw every letter
/// as a full square, so text rows elsewhere (e.g. the online card's stats)
/// can overflow here although they fit on a phone; those are ignored.
Future<List<String>> _pumpHome(
    WidgetTester tester, String status, Size screen) async {
  final cardErrors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (text.contains('_ActiveOrderCard')) cardErrors.add(text);
  };
  addTearDown(() => FlutterError.onError = previous);

  tester.view.physicalSize = screen * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      courierProfileProvider.overrideWith((ref) async => _profile),
      activeOrderProvider.overrideWith((ref) async => _order(status)),
    ],
    child: const MaterialApp(home: HomeScreen()),
  ));
  await tester.pumpAndSettle();
  return cardErrors;
}

void main() {
  testWidgets('in transit: confirm delivery and navigate to the customer',
      (tester) async {
    expect(await _pumpHome(tester, 'in_transit', const Size(360, 800)), isEmpty);
    expect(find.text('Confirm Delivery'), findsOneWidget);
    expect(find.text('Navigate to Customer'), findsOneWidget);
  });

  // Regression: with the keyboard up the card had ~235px and overflowed
  for (final status in ['in_transit', 'ready_for_pickup', 'confirmed']) {
    testWidgets('$status card fits a short screen by scrolling', (tester) async {
      expect(await _pumpHome(tester, status, const Size(360, 420)), isEmpty);

      final button = status == 'in_transit'
          ? 'Navigate to Customer'
          : 'Navigate to Merchant';
      await tester.scrollUntilVisible(find.text(button), 100,
          scrollable: find.byType(Scrollable).last);
      expect(find.text(button).hitTestable(), findsOneWidget);
    });
  }
}
