import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'screens/cart/cart_screen.dart';
import 'screens/checkout/checkout_screen.dart';
import 'screens/checkout/mpesa_payment_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/merchant/merchant_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/orders/orders_screen.dart';
import 'screens/orders/rate_order_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/tracking/tracking_screen.dart';

Route<dynamic>? customerRoute(RouteSettings s) {
  final Widget? page = switch (s.name) {
    '/customer' => const HomeScreen(),
    '/customer/onboarding' => const OnboardingScreen(),
    '/customer/shop' => const MerchantScreen(),
    '/customer/cart' => const CartScreen(),
    '/customer/checkout' => const CheckoutScreen(),
    '/customer/mpesa-payment' => const MpesaPaymentScreen(),
    '/customer/tracking' => const TrackingScreen(),
    '/customer/orders' => const OrdersScreen(),
    '/customer/rate-order' => const RateOrderScreen(),
    '/customer/profile' => const ProfileScreen(),
    _ => null,
  };
  if (page == null) return null;
  return MaterialPageRoute(
    builder: (_) => Theme(data: AppTheme.customer, child: page),
    settings: s,
  );
}
