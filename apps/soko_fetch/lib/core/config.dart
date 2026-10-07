// Environment-specific constants. Override with --dart-define, e.g.
//   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
class AppConfig {
  AppConfig._();

  static const String appName = 'Soko Fetch';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.47:8000',
  );

  // Google Maps needs an API key (see README). Until one is configured,
  // build with this off and map areas show a placeholder instead of a grey grid.
  static const bool mapsEnabled = bool.fromEnvironment('MAPS_ENABLED');

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Customer: how often the tracking screen polls GET /orders/{id}/tracking
  static const Duration trackingPollInterval = Duration(seconds: 10);

  // Merchant: how often live orders are polled
  static const Duration pollInterval = Duration(seconds: 10);

  // Courier: location updates while online, job board refresh
  static const Duration locationUpdateInterval = Duration(seconds: 5);
  static const Duration jobsPollInterval = Duration(seconds: 15);
}
