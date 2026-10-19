/// System and node runtime constants for Altr Stream Manager.
class AppConstants {
  AppConstants._();

  static const String appTitle = 'Altr Stream';
  static const String appSubtitle = 'Local Production Node Manager';
  static const String appVersion = '1.0.1-beta';
  static const String defaultNodeVersion = '1.0.0-beta';
  static const int defaultPort = 8000;
  static const String defaultLocalWebUrl = 'http://localhost:8000';

  static const String defaultDockerImage = 'ghcr.io/helloaltr/altr-stream:1.0.0-beta';
  static const String containerName = 'altr-stream';
  static const String dataVolumeName = 'altr_stream_data';
}
