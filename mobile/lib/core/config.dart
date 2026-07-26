abstract final class AppConfig {
  static const displayName = 'inspíraT';
  static const technicalName = 'inspirat';
  static const packageId = 'com.inspirat.app';
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );
}
