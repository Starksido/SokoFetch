// lib/config/app_config.dart
// All environment-specific constants in one place.
// Switch between dev and prod by changing the active Config.

class AppConfig {
  // ── API ────────────────────────────────────────────────────────────────────
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.47:8000', // Android emulator → localhost
  );

  // Certificate SHA-256 fingerprint for pinning (update on cert rotation)
  static const String certFingerprint = String.fromEnvironment(
    'CERT_SHA256',
    defaultValue: 'AA:BB:CC:DD:EE:FF', // Replace with real cert fingerprint
  );

  // ── Maps ───────────────────────────────────────────────────────────────────
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_KEY',
    defaultValue: '',
  );

  // ── Flutterwave ────────────────────────────────────────────────────────────
  static const String flutterwavePublicKey = String.fromEnvironment(
    'FLW_PUBLIC_KEY',
    defaultValue: '',
  );

  // ── App constants ──────────────────────────────────────────────────────────
  static const String appName           = 'Soko Fetch';
  static const Duration connectTimeout  = Duration(seconds: 10);
  static const Duration receiveTimeout  = Duration(seconds: 30);
  static const Duration locationInterval = Duration(seconds: 5);

  // ── Secure storage keys ────────────────────────────────────────────────────
  static const String keyAccessToken  = 'soko_fetch_access_token';
  static const String keyRefreshToken = 'soko_fetch_refresh_token';
  static const String keyUserId       = 'soko_fetch_user_id';
  static const String keyUserRole     = 'soko_fetch_user_role';

  // ── WebSocket ──────────────────────────────────────────────────────────────
  static String trackingWsUrl(String orderId) =>
      '${apiBaseUrl.replaceFirst('http', 'ws')}/ws/order/$orderId/tracking';
}
