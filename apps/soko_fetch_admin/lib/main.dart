import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'core/ui/ui.dart';
import 'features/login/login_screen.dart';
import 'features/review/admin_home_screen.dart';
import 'features/review/rider_review_screen.dart';

void main() {
  Session.init();
  runApp(const SessionScope(child: AdminApp()));
}

/// Rebuilds the whole panel with fresh providers on login, logout and
/// session expiry.
class SessionScope extends StatelessWidget {
  const SessionScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: sessionGeneration,
        builder: (_, generation, __) =>
            ProviderScope(key: ValueKey(generation), child: child),
      );
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Soko Fetch Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        // Keep content readable on wide desktop screens
        builder: (context, child) => ColoredBox(
          color: SfColors.surface2,
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppConfig.maxContentWidth),
              child: child,
            ),
          ),
        ),
        onGenerateRoute: (s) => MaterialPageRoute(
          settings: s,
          // A rider page opened from the address bar has no rider id
          builder: (_) => s.name == '/rider' && s.arguments is String
              ? const RiderReviewScreen()
              : const AuthGate(),
        ),
      );
}

/// Login screen or the panel, depending on whether this tab has a session.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: Session.isLoggedIn,
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Scaffold(body: SfLoader());
          }
          return snap.data! ? const AdminHomeScreen() : const LoginScreen();
        },
      );
}
