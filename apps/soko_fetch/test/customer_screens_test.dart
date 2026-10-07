import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_fetch/core/api_client.dart';
import 'package:soko_fetch/features/customer/models/models.dart';
import 'package:soko_fetch/features/customer/providers/providers.dart';
import 'package:soko_fetch/features/customer/screens/cart/cart_screen.dart';
import 'package:soko_fetch/features/customer/screens/checkout/checkout_screen.dart';
import 'package:soko_fetch/features/customer/screens/checkout/mpesa_payment_screen.dart';
import 'package:soko_fetch/features/customer/screens/merchant/merchant_screen.dart';
import 'package:soko_fetch/features/customer/screens/orders/orders_screen.dart';
import 'package:soko_fetch/features/customer/screens/tracking/tracking_screen.dart';
import 'package:soko_fetch/features/customer/shell.dart';

import 'helpers.dart';
import 'ui_helpers.dart';

Map<String, dynamic> _item(String id, String name, String category, num price,
        {String? description, bool available = true}) =>
    {
      'id': id,
      'merchant_id': 'm1',
      'name': name,
      'description': description,
      'category': category,
      'price': '$price',
      'effective_price': '$price',
      'is_available': available,
      'prep_minutes': 10,
    };

Map<String, dynamic> _shop(String id, String name,
        {bool open = true, double rating = 4.7, List<Map>? menu}) =>
    {
      'id': id,
      'shop_name': name,
      'category': 'grocery',
      'address': 'Stall 12, Westlands Market, Nairobi',
      'rating': '$rating',
      'rating_count': 38,
      'avg_prep_minutes': 20,
      'min_order_amount': '200',
      'is_open': open,
      'status': 'active',
      'menu_items': menu ?? [],
    };

final _menu = [
  _item('i1', 'Sukuma wiki (bunch)', 'vegetables', 30,
      description: 'Fresh from Kiambu farms this morning, washed and bundled'),
  _item('i2', 'Tomatoes (1 kg)', 'vegetables', 120),
  _item('i3', 'Avocados (4 pcs)', 'fruit', 100, available: false),
  _item('i4', 'Bananas (dozen)', 'fruit', 150),
];

final _shops = [
  Merchant.fromJson(_shop('m1', 'Mama Mboga Greens', menu: _menu)),
  Merchant.fromJson(_shop('m2', 'Kibanda Grill & Fresh Juice Corner', rating: 4.9)),
  Merchant.fromJson(_shop('m3', 'Westlands Pharmacy', open: false, rating: 0)),
];

final _orderJson = {
  'id': 'o1',
  'merchant_id': 'm1',
  'items': [
    {'item_id': 'i1', 'name': 'Sukuma wiki (bunch)', 'qty': 2, 'subtotal': 60},
    {'item_id': 'i2', 'name': 'Tomatoes (1 kg)', 'qty': 1, 'subtotal': 120},
  ],
  'subtotal': '180',
  'delivery_fee': '87.94',
  'surge_multiplier': '1',
  'total': '377.25',
  'payment_method': 'mpesa',
  'payment_status': 'paid',
  'delivery_address': 'Kileleshwa, Othaya Road, Apt 4B',
  'status': 'in_transit',
  'created_at': '2026-10-07T09:00:00Z',
  'estimated_delivery_at': '2026-10-07T09:45:00Z',
  'merchant_name': 'Mama Mboga Greens',
};

List<Override> _overrides() => [
      merchantsProvider.overrideWith((ref, category) async => _shops),
      merchantDetailProvider.overrideWith((ref, id) async => _shops.first),
      addressesProvider.overrideWith((ref) async => [
            DeliveryAddress.fromJson({
              'id': 'a1',
              'label': 'Home',
              'address_line': 'Kileleshwa, Othaya Road, Apt 4B',
              'city': 'Nairobi',
              'is_default': true,
            }),
          ]),
      customerProfileProvider.overrideWith((ref) async =>
          CustomerProfile.fromJson({'id': 'c1', 'full_name': 'Amina Wanjiku'})),
      ordersProvider.overrideWith((ref) async => [
            OrderSummary.fromJson({..._orderJson, 'item_count': 3}),
            OrderSummary.fromJson({
              ..._orderJson,
              'id': 'o2',
              'status': 'delivered',
              'item_count': 1,
              'merchant_name': 'Kibanda Grill & Fresh Juice Corner',
            }),
          ]),
      cartProvider.overrideWith((ref) => CartNotifier()
        ..replaceWith('m1', [
          CartItem(item: MenuItem.fromJson(_menu[0]), quantity: 2),
          CartItem(item: MenuItem.fromJson(_menu[1]), quantity: 1),
        ])),
    ];

/// Screens that call the API themselves (tracking, M-Pesa) get canned replies.
void _serveOrder() {
  // The API client reads the stored token before every request
  FlutterSecureStorage.setMockInitialValues({});
  ApiClient.instance.dio.httpClientAdapter = FakeAdapter((o) async {
    if (o.path.endsWith('/tracking')) {
      return jsonBody(200, {
        'order_id': 'o1',
        'status': 'in_transit',
        'courier_assigned': true,
        'courier_name': 'Juma',
        'vehicle_type': 'motorcycle',
      });
    }
    if (o.path.endsWith('/delivery-code')) {
      return jsonBody(200, {'order_id': 'o1', 'delivery_code': '9835'});
    }
    return jsonBody(200, _orderJson);
  });
}

void main() {
  setUpAll(loadAppFont);
  setUp(_serveOrder);

  final screens = <String, (Widget, Object?)>{
    'home': (const CustomerShell(), null),
    'shop page': (const MerchantScreen(), 'm1'),
    'cart': (const CartScreen(), null),
    'checkout': (const CheckoutScreen(), null),
    'm-pesa': (const MpesaPaymentScreen(), 'o1'),
    'orders': (const OrdersScreen(), null),
    'tracking': (const TrackingScreen(), 'o1'),
  };

  group('customer screens lay out at every size', () {
    for (final MapEntry(key: name, value: (screen, args)) in screens.entries) {
      for (final size in kScreenSizes) {
        testWidgets('$name at ${size.width.toInt()}x${size.height.toInt()}',
            (tester) async {
          final errors = await pumpAt(tester, screen, size,
              arguments: args, overrides: _overrides());
          expect(errors, isEmpty);
        });
      }
      testWidgets('$name with large text', (tester) async {
        final errors = await pumpAt(tester, screen, const Size(360, 800),
            textScale: 1.3, arguments: args, overrides: _overrides());
        expect(errors, isEmpty);
      });
    }
  });

  testWidgets('shop page: menu rows, sold out, cart bar', (tester) async {
    await pumpAt(tester, const MerchantScreen(), const Size(412, 915),
        arguments: 'm1', overrides: _overrides());
    await tester.pumpAndSettle();
    expect(find.text('Mama Mboga Greens'), findsWidgets);
    expect(find.text('Sukuma wiki (bunch)'), findsOneWidget);
    expect(find.text('Sold out'), findsOneWidget);
    // Cart from the overrides: 3 items, KES 180
    expect(find.text('View cart'), findsOneWidget);
    expect(find.text('KES 180'), findsWidgets);
  });

  testWidgets('home: shell tabs and shops', (tester) async {
    await pumpAt(tester, const CustomerShell(), const Size(412, 915),
        overrides: _overrides());
    await tester.pumpAndSettle();
    expect(find.text('Home · Kileleshwa, Othaya Road, Apt 4B'), findsOneWidget);
    expect(find.text('Popular near you'), findsOneWidget);
    expect(find.text('All shops'), findsOneWidget);
    for (final label in ['Home', 'Browse', 'Orders', 'Account']) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
  });

  testWidgets('tracking shows the delivery code and rider', (tester) async {
    await pumpAt(tester, const TrackingScreen(), const Size(412, 915),
        arguments: 'o1', overrides: _overrides());
    // Order, tracking and delivery code arrive over several frames
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('On the way to you'), findsOneWidget);
    expect(find.text('9835'), findsOneWidget);
    expect(find.text('Juma'), findsOneWidget);
  });
}

