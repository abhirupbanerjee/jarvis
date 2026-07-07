/// Application-level constants that don't belong in .env or LLM config.
class AppConfig {
  AppConfig._();

  /// Displayed in Settings > About
  static const String appName = 'J.A.R.V.I.S.';

  /// From pubspec.yaml — update manually when version changes.
  static const String version = '1.0.0';
  static const int buildNumber = 1;

  static String get versionLabel => '$version (build $buildNumber)';
}
