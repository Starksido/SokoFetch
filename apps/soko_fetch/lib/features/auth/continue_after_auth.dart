import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import 'auth_service.dart';

/// After a phone or Google verification: existing users go to their area,
/// new users go to the role picker.
Future<void> continueAfterAuth(
    BuildContext context, WidgetRef ref, AuthResult result) async {
  switch (result) {
    case NeedsRole(:final signupToken):
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/auth/role',
        ModalRoute.withName('/welcome'),
        arguments: signupToken,
      );
    case LoggedIn(:final user):
      ref.read(currentUserProvider.notifier).state = user;
      String destination;
      try {
        destination = await AuthService.instance.landingRoute(user.role);
      } catch (_) {
        destination = AuthService.homeRoute(user.role);
      }
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(destination, (_) => false);
  }
}
