import 'platform_reload_stub.dart'
    if (dart.library.html) 'platform_reload_web.dart';

/// Platform-agnostic application reload handler.
abstract class PlatformReload {
  /// Reloads the application web page in Flutter Web; no-op on other platforms.
  static void reload() => reloadPlatformApp();
}
