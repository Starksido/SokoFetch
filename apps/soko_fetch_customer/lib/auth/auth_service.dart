@'
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../network/secure_client.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _localAuth = LocalAuthentication();

  // -- OTP request --------------------------------------------------------------
  Future<void> requestOtp(String phone) async {
    await SecureApiClient.instance.post('/auth/otp/request', data: {
      'phone': phone,
      'role':  'customer',
    });
  }

  // -- OTP verify + login ---------------------------------------------------------
  Future<AuthTokens> verifyOtp(String phone, String otpCode) async {
    final resp = await SecureApiClient.instance.post('/auth/otp/verify', data: {
      'phone':    phone,
      'otp_code': otpCode,
      'role':     'customer',
    });

    final tokens = AuthTokens.fromJson(resp.data as Map<String, dynamic>);

    await SecureApiClient.saveTokens(
      accessToken:  tokens.accessToken,
      refreshToken: tokens.refreshToken,
      userId:       tokens.user.userId,
      role:         tokens.user.role,
    );

    return tokens;
  }

  // -- Google Sign-In + login ------------------------------------------------
  Future<AuthTokens> signInWithGoogle(String idToken) async {
    final resp = await SecureApiClient.instance.post('/auth/google-login', data: {
      'id_token': idToken,
      'role':     'customer',
    });

    final tokens = AuthTokens.fromJson(resp.data as Map<String, dynamic>);

    await SecureApiClient.saveTokens(
      accessToken:  tokens.accessToken,
      refreshToken: tokens.refreshToken,
      userId:       tokens.user.userId,
      role:         tokens.user.role,
    );

    return tokens;
  }

  // -- Customer onboarding ------------------------------------------------------
  Future<void> onboardCustomer({required String fullName, String? email}) async {
    await SecureApiClient.instance.post('/customer/onboard', data: {
      'full_name': fullName,
      if (email != null) 'email': email,
    });
  }

  // -- Google account verification -----------------------------------------------
  Future<void> verifyGoogleAccount(String idToken) async {
    await SecureApiClient.instance.post('/customer/verify-google', data: {
      'id_token': idToken,
    });
  }

  // -- Biometric unlock -----------------------------------------------------------
  Future<bool> canUseBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      final available = await canUseBiometrics();
      if (!available) return false;

      return await _localAuth.authenticate(
        localizedReason: 'Confirm your identity to access Soko Fetch',
        options: const AuthenticationOptions(
          stickyAuth:          true,
          biometricOnly:       false,
          sensitiveTransaction: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // -- Session check --------------------------------------------------------------
  Future<bool> get isLoggedIn => SecureApiClient.isAuthenticated;

  // -- Logout -----------------------------------------------------------------------
  Future<void> logout() async {
    try {
      final refreshToken = await SecureApiClient.getRefreshToken();
      await SecureApiClient.instance.post('/auth/logout', data: {
        if (refreshToken != null) 'refresh_token': refreshToken,
      });
    } catch (_) {}
    await SecureApiClient.clearTokens();
  }
}
'@ | Set-Content -Path "lib\auth\auth_service.dart" -Encoding UTF8