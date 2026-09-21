import 'local_storage_stub.dart'
    if (dart.library.html) 'local_storage_web.dart'
    if (dart.library.io) 'local_storage_io.dart';

/// Zero-dependency platform-agnostic key-value local storage adapter.
/// Uses HTML5 localStorage on Web, local JSON file on VM/Desktop/Docker,
/// and in-memory map in stub/headless environments.
abstract class LocalStorageAdapter {
  static String? read(String key) => readStorage(key);
  static void write(String key, String? value) => writeStorage(key, value);
}
