final Map<String, String> _memoryStorage = {};

String? readStorage(String key) => _memoryStorage[key];

void writeStorage(String key, String? value) {
  if (value == null) {
    _memoryStorage.remove(key);
  } else {
    _memoryStorage[key] = value;
  }
}
