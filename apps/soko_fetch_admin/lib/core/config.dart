// Override with --dart-define, e.g.
//   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// Content is centred and capped at this width on wide screens
  static const double maxContentWidth = 960;
}
