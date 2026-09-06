import 'package:flutter/foundation.dart';

class AppConfig {
  static const String appName = 'Altr Stream Admin';
  static const String appVersion = 'v0.1.0';

  /// Determines the base API URL depending on web vs standalone environment.
  /// When served via Nginx in Docker (release mode), relative URL `/api/v1` is proxied to backend.
  /// For local development (`flutter run -d web-server`), defaults to `http://localhost:8000/api/v1`.
  /// Can be overridden explicitly using `--dart-define=ALTR_API_URL=...`.
  static String get apiBaseUrl {
    const customUrl = String.fromEnvironment('ALTR_API_URL');
    if (customUrl.isNotEmpty) {
      return customUrl;
    }
    if (kIsWeb) {
      // In web release mode or behind reverse proxy, use relative API path
      if (kReleaseMode) {
        return '/api/v1';
      }
      // In local development web server, point to local FastAPI
      return 'http://localhost:8000/api/v1';
    }
    return 'http://localhost:8000/api/v1';
  }
}
