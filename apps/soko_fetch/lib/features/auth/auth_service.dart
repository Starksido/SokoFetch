import 'package:dio/dio.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';

/// What came back from verifying a phone or Google account.
sealed class AuthResult {}

/// An existing account: the session has been saved.
class LoggedIn extends AuthResult {
  LoggedIn(this.user);
  final UserProfile user;
}

/// A new account: the identity is verified but no account exists yet. The
/// user picks a role and the account is created with [signupToken].
class NeedsRole extends AuthResult {
  NeedsRole(this.signupToken);
  final String signupToken;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  ApiClient get _api => ApiClient.instance;
  final _localAuth = LocalAuthentication();

  Future<void> requestOtp(String phone) =>
      _api.post('/auth/otp/request', data: {'phone': phone});

  Future<AuthResult> verifyOtp(String phone, String code) async {
    final resp = await _api
        .post('/auth/otp/verify', data: {'phone': phone, 'otp_code': code});
    return _handle(resp.data as Map<String, dynamic>);
  }

  Future<AuthResult> signInWithGoogle(String idToken) async {
    final resp =
        await _api.post('/auth/google-login', data: {'id_token': idToken});
    return _handle(resp.data as Map<String, dynamic>);
  }

  /// Creates the account with the role the user picked.
  Future<UserProfile> signup(String signupToken, String role) async {
    final resp = await _api.post('/auth/signup',
        data: {'signup_token': signupToken, 'role': role});
    final tokens = AuthTokens.fromJson(resp.data as Map<String, dynamic>);
    await Session.start(tokens);
    return tokens.user;
  }

  Future<AuthResult> _handle(Map<String, dynamic> data) async {
    if (data['needs_role'] == true) {
      return NeedsRole(data['signup_token'] as String);
    }
    final tokens = AuthTokens.fromJson(data);
    await Session.start(tokens);
    return LoggedIn(tokens.user);
  }

  // ── Where each role lands ─────────────────────────────────────────────────
  static String homeRoute(String role) => '/$role';

  /// The role's home, or its onboarding if this account has no profile yet
  /// (GET /{role}/me returns 404).
  Future<String> landingRoute(String role) async {
    try {
      await _api.get('/$role/me');
      return homeRoute(role);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return '/$role/onboarding';
      rethrow;
    }
  }

  // ── Biometric unlock (customers) ──────────────────────────────────────────
  /// True if the device has a screen lock or biometrics we can ask for.
  Future<bool> canUseDeviceLock() async {
    try {
      // Never let a misbehaving plugin keep the user on the splash screen
      return await _localAuth
          .isDeviceSupported()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockWithDeviceLock() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Confirm your identity to open Soko Fetch',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          sensitiveTransaction: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
