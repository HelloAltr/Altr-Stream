import 'dart:io';

String? readStorage(String key) {
  try {
    final file = File('.$key.json');
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  } catch (_) {}
  return null;
}

void writeStorage(String key, String? value) {
  try {
    final file = File('.$key.json');
    if (value == null) {
      if (file.existsSync()) file.deleteSync();
    } else {
      file.writeAsStringSync(value);
    }
  } catch (_) {}
}
