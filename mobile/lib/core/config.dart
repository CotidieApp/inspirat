abstract final class AppConfig {
  static const displayName = 'inspíraT';
  static const technicalName = 'inspirat';
  static const packageId = 'com.inspirat.app';
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://inspirat-api.onrender.com/api/v1',
  );
  static const isDevBuild = bool.fromEnvironment('DEV_BUILD');
}
