import 'package:flutter/material.dart';

import 'admin_home_screen.dart';
import 'rider_review_screen.dart';

Route<dynamic>? adminRoute(RouteSettings s) {
  final Widget? page = switch (s.name) {
    '/admin' => const AdminHomeScreen(),
    '/admin/rider' => const RiderReviewScreen(),
    _ => null,
  };
  if (page == null) return null;
  return MaterialPageRoute(builder: (_) => page, settings: s);
}
