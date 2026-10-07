import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/auth/otp_screen.dart';
import 'features/auth/role_picker_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/auth/welcome_screen.dart';
import 'features/courier/routes.dart';
import 'features/customer/routes.dart';
import 'features/merchant/routes.dart';

class SokoFetchApp extends StatelessWidget {
  const SokoFetchApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Soko Fetch',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: '/',
        onGenerateRoute: onGenerateRoute,
      );
}

/// Each role owns the routes under its prefix: /customer, /merchant and
/// /courier. Admins use the separate admin web panel (apps/soko_fetch_admin).
Route<dynamic> onGenerateRoute(RouteSettings s) {
  final name = s.name ?? '/';
  Widget? page = switch (name) {
    '/welcome' => const WelcomeScreen(),
    '/auth/otp' => const OtpScreen(),
    '/auth/role' => const RolePickerScreen(),
    _ => null,
  };
  if (page != null) {
    return MaterialPageRoute(builder: (_) => page, settings: s);
  }

  final route = _under(name, '/customer', s, customerRoute) ??
      _under(name, '/merchant', s, merchantRoute) ??
      _under(name, '/courier', s, courierRoute);
  return route ??
      MaterialPageRoute(builder: (_) => const SplashScreen(), settings: s);
}

Route<dynamic>? _under(String name, String prefix, RouteSettings s,
    Route<dynamic>? Function(RouteSettings) routes) {
  if (name == prefix || name.startsWith('$prefix/')) return routes(s);
  return null;
}
