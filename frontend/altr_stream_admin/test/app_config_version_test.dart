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

    test('defaultAppVersion is canonical 0.13.2-alpha', () {
      expect(AppConfig.defaultAppVersion, '0.13.2-alpha');
    });

    test('appVersion returns default or injected environment variable', () {
      const injected = String.fromEnvironment('ALTR_APP_VERSION');
      if (injected.isNotEmpty) {
        expect(AppConfig.hasBuildTimeOverride, isTrue);
        expect(AppConfig.appVersion, injected);
      } else {
        expect(AppConfig.hasBuildTimeOverride, isFalse);
        expect(AppConfig.appVersion, '0.13.2-alpha');
      }
    });

    test('formattedAppVersion properly prefixes v to version strings', () {
      expect(AppConfig.formattedAppVersion.startsWith('v'), isTrue);
      if (!AppConfig.hasBuildTimeOverride) {
        expect(AppConfig.formattedAppVersion, 'v0.13.2-alpha');
      }
    });

    test('setRuntimeNodeVersion updates appVersion when no build-time override is present', () {
      if (!AppConfig.hasBuildTimeOverride) {
        AppConfig.setRuntimeNodeVersion('1.2.0');
        expect(AppConfig.appVersion, '1.2.0');
        expect(AppConfig.formattedAppVersion, 'v1.2.0');

        // Reset restores defaultAppVersion
        AppConfig.resetRuntimeNodeVersion();
        expect(AppConfig.appVersion, '0.13.2-alpha');
        expect(AppConfig.formattedAppVersion, 'v0.13.2-alpha');
      } else {
        // If an explicit build-time override is present, it takes precedence
        AppConfig.setRuntimeNodeVersion('1.2.0');
        expect(AppConfig.appVersion, const String.fromEnvironment('ALTR_APP_VERSION'));
      }
    });

    test('setRuntimeNodeVersion ignores null and empty strings', () {
      if (!AppConfig.hasBuildTimeOverride) {
        AppConfig.setRuntimeNodeVersion(null);
        expect(AppConfig.appVersion, '0.13.2-alpha');

        AppConfig.setRuntimeNodeVersion('   ');
        expect(AppConfig.appVersion, '0.13.2-alpha');
      }
    });
  });
}
