class AppConfig {
  AppConfig._();
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://192.168.100.47:8000');
  static const String wsBaseUrl  = String.fromEnvironment('WS_BASE_URL',  defaultValue: 'ws://10.0.2.2:8000');
  static const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');
  static const String keyAccessToken  = 'courier_access_token';
  static const String keyRefreshToken = 'courier_refresh_token';
  static const String keyUserId       = 'courier_user_id';
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration locationUpdateInterval = Duration(seconds: 5);
}
