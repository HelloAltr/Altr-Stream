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

  /// Returns the FastAPI OpenAPI documentation URL derived from the configured API base URL.
  /// For local development, resolves to `http://localhost:8000/docs`.
  /// When served behind a reverse proxy (/api/v1), resolves to `/docs`.
  /// Can be overridden explicitly using `--dart-define=ALTR_DOCS_URL=...`.
  static String get apiDocsUrl {
    const customDocs = String.fromEnvironment('ALTR_DOCS_URL');
    if (customDocs.isNotEmpty) {
      return customDocs;
    }
    return _deriveDocsPath('/docs');
  }

  /// Alias for apiDocsUrl (Swagger UI)
  static String get swaggerDocsUrl => apiDocsUrl;

  /// Returns the FastAPI ReDoc documentation URL derived from the configured API base URL.
  /// For local development, resolves to `http://localhost:8000/redoc`.
  /// When served behind a reverse proxy (/api/v1), resolves to `/redoc`.
  /// Can be overridden explicitly using `--dart-define=ALTR_REDOC_URL=...`.
  static String get redocDocsUrl {
    const customRedoc = String.fromEnvironment('ALTR_REDOC_URL');
    if (customRedoc.isNotEmpty) {
      return customRedoc;
    }
    return _deriveDocsPath('/redoc');
  }

  /// Returns the OpenAPI JSON schema URL derived from the configured API base URL.
  /// For local development, resolves to `http://localhost:8000/openapi.json`.
  /// When served behind a reverse proxy (/api/v1), resolves to `/openapi.json`.
  /// Can be overridden explicitly using `--dart-define=ALTR_OPENAPI_URL=...`.
  static String get openApiJsonUrl {
    const customOpenApi = String.fromEnvironment('ALTR_OPENAPI_URL');
    if (customOpenApi.isNotEmpty) {
      return customOpenApi;
    }
    return _deriveDocsPath('/openapi.json');
  }

  static String _deriveDocsPath(String path) {
    final base = apiBaseUrl;
    if (base.endsWith('/api/v1')) {
      return '${base.substring(0, base.length - 7)}$path';
    } else if (base.endsWith('/api/v1/')) {
      return '${base.substring(0, base.length - 8)}$path';
    }
    if (base.startsWith('http://') || base.startsWith('https://')) {
      final uri = Uri.parse(base);
      return uri.replace(path: path, query: '', fragment: '').toString();
    }
    return path;
  }
}
