import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_theme.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/phone_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/merchant/merchant_screen.dart';
import 'screens/cart/cart_screen.dart';
import 'screens/checkout/checkout_screen.dart';
import 'screens/checkout/mpesa_payment_screen.dart';
import 'screens/tracking/tracking_screen.dart';
import 'screens/orders/orders_screen.dart';
import 'screens/orders/rate_order_screen.dart';
import 'screens/profile/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:        Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(const ProviderScope(child: SokoFetchApp()));
}

class SokoFetchApp extends StatelessWidget {
  const SokoFetchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:        'Soko Fetch',
      debugShowCheckedModeBanner: false,
      theme:        AppTheme.light,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return _route(const SplashScreen(), settings);
          case '/auth/phone':
            return _route(const PhoneScreen(), settings);
          case '/auth/otp':
            return _route(const OtpScreen(), settings);
          case '/home':
            return _route(const HomeScreen(), settings);
          case '/onboarding':
            return _route(const OnboardingScreen(), settings);
          case '/merchant':
            return _route(const MerchantScreen(), settings);
          case '/cart':
            return _route(const CartScreen(), settings);
          case '/checkout':
            return _route(const CheckoutScreen(), settings);
          case '/mpesa-payment':
            return _route(const MpesaPaymentScreen(), settings);
          case '/tracking':
            return _route(const TrackingScreen(), settings);
          case '/orders':
            return _route(const OrdersScreen(), settings);
          case '/rate-order':
            return _route(const RateOrderScreen(), settings);
          case '/profile':
            return _route(const ProfileScreen(), settings);
          default:
            return _route(const HomeScreen(), settings);
        }
      },
    );
  }

  PageRoute _route(Widget page, RouteSettings settings) =>
      MaterialPageRoute(builder: (_) => page, settings: settings);
}
