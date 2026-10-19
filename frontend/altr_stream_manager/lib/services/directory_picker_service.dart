import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service providing native operating system folder selection.
///
/// Uses macOS Finder folder chooser, Windows Explorer FolderBrowserDialog,
/// or Linux directory chooser without requiring external binary dependencies or Podfiles.
class DirectoryPickerService {
  /// Opens the native directory chooser.
  ///
  /// Returns the absolute path of the chosen directory, or null if cancelled.
  static Future<String?> pickDirectory({String? initialDirectory}) async {
    try {
      if (Platform.isMacOS) {
        return await _pickDirectoryMacOS(initialDirectory);
      } else if (Platform.isWindows) {
        return await _pickDirectoryWindows(initialDirectory);
      } else if (Platform.isLinux) {
        return await _pickDirectoryLinux(initialDirectory);
      }
    } catch (e) {
      debugPrint('[DirectoryPickerService] Failed to open native directory picker: $e');
    }
    return null;
  }

  static Future<String?> _pickDirectoryMacOS(String? initialDirectory) async {
    try {
      final defaultClause = (initialDirectory != null && Directory(initialDirectory).existsSync())
          ? 'default location POSIX file "$initialDirectory"'
          : '';
      final script =
          'POSIX path of (choose folder with prompt "Select Altr Stream installation directory" $defaultClause)';
      final result = await Process.run('osascript', ['-e', script]);
      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty) {
          // Normalize trailing slash
          return path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[DirectoryPickerService] macOS picker error: $e');
      return null;
    }
  }

  static Future<String?> _pickDirectoryWindows(String? initialDirectory) async {
    try {
      final initialPath = (initialDirectory != null && Directory(initialDirectory).existsSync())
          ? initialDirectory.replaceAll("'", "''")
          : '';
      final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
\$dialog.Description = "Select Altr Stream installation directory"
if ("$initialPath" -ne "") { \$dialog.SelectedPath = "$initialPath" }
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    Write-Output \$dialog.SelectedPath
}
''';
      final result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty) {
          return path.endsWith('\\') && path.length > 3 ? path.substring(0, path.length - 1) : path;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[DirectoryPickerService] Windows picker error: $e');
      return null;
    }
  }

  static Future<String?> _pickDirectoryLinux(String? initialDirectory) async {
    try {
      final result = await Process.run('zenity', [
        '--file-selection',
        '--directory',
        '--title=Select Altr Stream installation directory',
      ]);
      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        return path.isNotEmpty ? path : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Validates whether [directoryPath] is a valid, writable location for installation.
  static Future<String?> validateDirectory(String directoryPath) async {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty) {
      return 'Directory path cannot be empty.';
    }

    try {
      final dir = Directory(trimmed);
      if (dir.existsSync()) {
        // Test write permissions by creating and deleting a temporary test marker
        final testFile = File('${dir.path}/.altr_write_test_${DateTime.now().millisecondsSinceEpoch}');
        try {
          await testFile.writeAsString('test');
          if (await testFile.exists()) {
            await testFile.delete();
          }
        } catch (_) {
          return 'Permission denied: Selected directory is not writable. Please choose a directory with write access.';
        }
      } else {
        // Check if parent directory exists and is writable
        final parent = dir.parent;
        if (!parent.existsSync()) {
          return 'Parent directory does not exist: ${parent.path}';
        }
        final testFile = File('${parent.path}/.altr_write_test_${DateTime.now().millisecondsSinceEpoch}');
        try {
          await testFile.writeAsString('test');
          if (await testFile.exists()) {
            await testFile.delete();
          }
        } catch (_) {
          return 'Permission denied: Cannot create directory in ${parent.path}.';
        }
      }
      return null; // Valid!
    } catch (e) {
      return 'Invalid directory: $e';
    }
  }
}
