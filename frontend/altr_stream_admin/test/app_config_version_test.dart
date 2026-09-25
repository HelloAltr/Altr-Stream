import 'package:flutter_test/flutter_test.dart';
import 'package:altr_stream_admin/core/config/app_config.dart';

void main() {
  group('AppConfig Single-Node Versioning', () {
    setUp(() {
      AppConfig.resetRuntimeNodeVersion();
    });

    tearDown(() {
      AppConfig.resetRuntimeNodeVersion();
    });

    test('defaultAppVersion is canonical 0.13.4-alpha', () {
      expect(AppConfig.defaultAppVersion, '0.13.4-alpha');
    });

    test('appVersion returns default or injected environment variable', () {
      const injected = String.fromEnvironment('ALTR_APP_VERSION');
      if (injected.isNotEmpty) {
        expect(AppConfig.hasBuildTimeOverride, isTrue);
        expect(AppConfig.appVersion, injected);
      } else {
        expect(AppConfig.hasBuildTimeOverride, isFalse);
        expect(AppConfig.appVersion, '0.13.4-alpha');
      }
    });

    test('formattedAppVersion properly prefixes v to version strings', () {
      expect(AppConfig.formattedAppVersion.startsWith('v'), isTrue);
      if (!AppConfig.hasBuildTimeOverride) {
        expect(AppConfig.formattedAppVersion, 'v0.13.4-alpha');
      }
    });

    test('setRuntimeNodeVersion updates appVersion and takes precedence over build-time define', () {
      AppConfig.setRuntimeNodeVersion('1.2.0');
      expect(AppConfig.appVersion, '1.2.0');
      expect(AppConfig.formattedAppVersion, 'v1.2.0');

      // Reset restores fallback (build-time override if provided, else canonical default)
      AppConfig.resetRuntimeNodeVersion();
      if (AppConfig.hasBuildTimeOverride) {
        expect(AppConfig.appVersion, const String.fromEnvironment('ALTR_APP_VERSION'));
      } else {
        expect(AppConfig.appVersion, '0.13.4-alpha');
        expect(AppConfig.formattedAppVersion, 'v0.13.4-alpha');
      }
    });

    test('setRuntimeNodeVersion ignores null and empty strings', () {
      AppConfig.setRuntimeNodeVersion(null);
      if (!AppConfig.hasBuildTimeOverride) {
        expect(AppConfig.appVersion, '0.13.4-alpha');
      }

      AppConfig.setRuntimeNodeVersion('   ');
      if (!AppConfig.hasBuildTimeOverride) {
        expect(AppConfig.appVersion, '0.13.4-alpha');
      }
    });
  });
}
