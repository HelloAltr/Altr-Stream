import 'dart:io';

import 'package:flutter/foundation.dart';

import 'backend_service.dart';
import 'engine_backend_service.dart';
import 'mock_backend_service.dart';

/// Global backend service reference.
///
/// Real mode is the strict default. [EngineBackendService] connects to the
/// real Go installer engine and host Docker daemon.
/// [MockBackendService] is ONLY used when explicitly requested via
/// `--dart-define=ALTR_MOCK=true` or the `ALTR_MOCK=true` environment variable.
BackendService backendService = initBackendService();

/// Initializes the backend service.
///
/// Returns [MockBackendService] ONLY when explicitly requested.
/// In all other cases, returns [EngineBackendService].
BackendService initBackendService({bool? forceMock}) {
  final explicitMock = forceMock ?? isMockModeEnabled();
  if (explicitMock) {
    debugPrint('[AltrStreamManager] Explicit mock mode active. Using MockBackendService.');
    return MockBackendService(currentScenario: MockScenario.running);
  }

  final engine = EngineBackendService();
  final path = engine.resolveEngineBinary();
  if (path != null) {
    debugPrint('[AltrStreamManager] Connected to real native engine at: $path');
  } else {
    debugPrint('[AltrStreamManager] Native engine binary not located on host. Real mode active — error states will be surfaced.');
  }
  return engine;
}

/// Returns true only if mock mode was explicitly enabled via compile-time define or env variable.
bool isMockModeEnabled() {
  const dartDefine = String.fromEnvironment('ALTR_MOCK', defaultValue: '');
  if (dartDefine.toLowerCase() == 'true' || dartDefine == '1') {
    return true;
  }
  final env = Platform.environment['ALTR_MOCK']?.toLowerCase();
  if (env == 'true' || env == '1') {
    return true;
  }
  return false;
}
