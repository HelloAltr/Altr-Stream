// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Web implementation using window.location.reload() to refresh the SPA.
void reloadPlatformApp() {
  html.window.location.reload();
}
