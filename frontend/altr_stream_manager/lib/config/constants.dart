/// System and node runtime constants for Altr Stream Manager.
class AppConstants {
  AppConstants._();

  static const String appTitle = 'Altr Stream';
  static const String appSubtitle = 'Local Production Node Manager';
  static const String appVersion = '1.1.0';
  static const String defaultNodeVersion = '1.1.0';
  static const int defaultPort = 8000;
  static const String defaultLocalWebUrl = 'http://localhost:8000';

  static const String defaultDockerImage = 'ghcr.io/helloaltr/altr-stream:1.1.0';
  static const String containerName = 'altr-stream';
  static const String dataVolumeName = 'altr_stream_data';
  static const double dialogStandardWidth = 360.0;
}

/// Standard uniform dialog width across all Altr Stream Manager dialogs (360px).
const double kDialogStandardWidth = 360.0;
