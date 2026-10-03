class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.47:8000',
  );
  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://10.0.2.2:8000',
  );

  static const String keyAccessToken  = 'merchant_access_token';
  static const String keyRefreshToken = 'merchant_refresh_token';
  static const String keyUserId       = 'merchant_user_id';
  static const String keyUserRole     = 'merchant_user_role';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // How often to poll live orders when WebSocket is not available
  static const Duration pollInterval = Duration(seconds: 10);
}
