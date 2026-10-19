/// Real-time progress updates during install, update, or repair operations.
class InstallProgress {
  final String stage;
  final int stageIndex;
  final int totalStages;
  final int percent;
  final String message;
  final bool isFailed;
  final bool isDone;
  final String? error;

  const InstallProgress({
    required this.stage,
    required this.stageIndex,
    required this.totalStages,
    required this.percent,
    required this.message,
    this.isFailed = false,
    this.isDone = false,
    this.error,
  });

  factory InstallProgress.initial({String stage = 'Preparing...'}) {
    return InstallProgress(
      stage: stage,
      stageIndex: 0,
      totalStages: 5,
      percent: 0,
      message: 'Starting operation...',
    );
  }

  factory InstallProgress.completed({String message = 'Operation completed successfully.'}) {
    return InstallProgress(
      stage: 'Done',
      stageIndex: 5,
      totalStages: 5,
      percent: 100,
      message: message,
      isDone: true,
    );
  }

  factory InstallProgress.failed(String error) {
    return InstallProgress(
      stage: 'Failed',
      stageIndex: 0,
      totalStages: 5,
      percent: 0,
      message: error,
      isFailed: true,
      error: error,
    );
  }

  factory InstallProgress.fromJson(Map<String, dynamic> json) {
    return InstallProgress(
      stage: json['stage'] as String? ?? 'Processing',
      stageIndex: json['stage_index'] as int? ?? 1,
      totalStages: json['total_stages'] as int? ?? 5,
      percent: json['percent'] as int? ?? 0,
      message: json['message'] as String? ?? '',
      isDone: (json['percent'] as int? ?? 0) >= 100,
      isFailed: (json['percent'] as int? ?? 0) < 0,
      error: json['error'] as String?,
    );
  }

  /// Parses pipe-delimited progress line formatted by Go engine:
  /// percent|stageIndex|totalStages|stage|message
  static InstallProgress? tryParseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split('|');
    if (parts.length >= 5) {
      final pct = int.tryParse(parts[0]) ?? 0;
      final idx = int.tryParse(parts[1]) ?? 0;
      final total = int.tryParse(parts[2]) ?? 5;
      final stage = parts[3];
      final msg = parts.sublist(4).join('|');
      return InstallProgress(
        stage: stage,
        stageIndex: idx,
        totalStages: total,
        percent: pct,
        message: msg,
        isFailed: pct < 0,
        isDone: pct >= 100,
        error: pct < 0 ? msg : null,
      );
    }
    return null;
  }
}
