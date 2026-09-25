import 'package:flutter/foundation.dart';

class AppConfig {
  static const String appName = 'Altr Stream Admin';

  /// Canonical fallback application/node version when `--dart-define=ALTR_APP_VERSION` is omitted.
  static const String defaultAppVersion = '0.13.4-alpha';

  /// Build-time injected version override via `--dart-define=ALTR_APP_VERSION=...`.
  /// This serves as a compile-time transport mechanism, not an independent version authority.
  static const String _buildTimeVersion = String.fromEnvironment('ALTR_APP_VERSION');

  /// Runtime node version observed from the connected backend `/health` endpoint.
  static String? _runtimeNodeVersion;

  /// Sets the runtime node version observed from the connected backend.
  static void setRuntimeNodeVersion(String? version) {
    if (version != null && version.trim().isNotEmpty) {
      _runtimeNodeVersion = version.trim();
    }
  }

  /// Resets the runtime node version (primarily for testing).
  @visibleForTesting
  static void resetRuntimeNodeVersion() {
    _runtimeNodeVersion = null;
  }

  /// Returns whether a custom build-time override was supplied via `--dart-define`.
  static bool get hasBuildTimeOverride => _buildTimeVersion.isNotEmpty;

  /// Returns the canonical Node version string.
  ///
  /// Priority:
  /// 1. Runtime backend version from connected node `/health` endpoint (live node authority).
  /// 2. Build-time override if provided via `--dart-define=ALTR_APP_VERSION=...` (compile-time transport fallback).
  /// 3. Canonical default fallback [defaultAppVersion] (`0.13.4-alpha`).
  static String get appVersion {
    if (_runtimeNodeVersion != null && _runtimeNodeVersion!.isNotEmpty) {
      return _runtimeNodeVersion!;
    }
    if (_buildTimeVersion.isNotEmpty) {
      return _buildTimeVersion;
    }
    return defaultAppVersion;
  }

  /// Returns the formatted version string prefixed with 'v' if needed (e.g. `v0.13.4-alpha`).
  static String get formattedAppVersion {
    final v = appVersion;
    return v.startsWith('v') ? v : 'v$v';
  }

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
