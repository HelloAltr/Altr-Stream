import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../platform/platform_reload.dart';

enum UpdateChipState {
  idle,
  updateAvailable,
  starting,
  updating,
  rollingBack,
  reloadRequired,
  error,
}

class UpdateController extends ChangeNotifier {
  static final Map<ApiClient?, UpdateController> _instances = {};

  static UpdateController get instance => instanceFor(null);

  static UpdateController instanceFor(ApiClient? client) {
    return _instances.putIfAbsent(client, () => UpdateController(apiClient: client));
  }

  static void setMock(UpdateController controller) {
    _instances[null] = controller;
    _instances[controller.apiClient] = controller;
  }

  static void reset() {
    for (final controller in _instances.values) {
      controller.dispose();
    }
    _instances.clear();
  }

  final ApiClient apiClient;

  UpdateStatusResponse? _currentStatus;
  UpdateCheckResponse? _latestCheck;
  bool _isChecking = false;
  bool _isStartingUpdate = false;
  String? _checkError;
  bool _reloadRequired = false;
  Timer? _pollTimer;
  bool _initialized = false;
  int _consecutivePollErrors = 0;
  static const int maxConsecutivePollErrors = 30; // 60s of complete container restart

  UpdateController({ApiClient? apiClient})
      : apiClient = apiClient ?? ApiClient();

  UpdateStatusResponse? get currentStatus => _currentStatus;
  UpdateCheckResponse? get latestCheck => _latestCheck;
  bool get isChecking => _isChecking;
  bool get isStartingUpdate => _isStartingUpdate;
  String? get checkError => _checkError;
  bool get isReloadRequired => _reloadRequired || isCompleted;

  String get state => _currentStatus?.state.toLowerCase() ?? 'idle';
  bool get isIdle => state == 'idle';
  bool get isRequested => state == 'requested';
  bool get isStaging => state == 'staging';
  bool get isApplying => state == 'applying';
  bool get isHealthCheck => state == 'health_check';
  bool get isRollingBack => state == 'rolling_back';
  bool get isRolledBack => state == 'rolled_back';
  bool get isCompleted => state == 'completed';
  bool get isFailed => state == 'failed' || isRolledBack;

  bool get isActive =>
      isRequested ||
      isStaging ||
      isApplying ||
      isHealthCheck ||
      isRollingBack ||
      _isStartingUpdate;

  bool get isCheckAvailable => _latestCheck?.checkAvailable ?? true;

  bool get isUpdateAvailable =>
      _latestCheck?.checkAvailable == true &&
      _latestCheck?.updateAvailable == true &&
      !isActive &&
      !isCompleted &&
      !isFailed;

  String? get targetVersion =>
      _currentStatus?.targetVersion ?? _latestCheck?.latestVersion;

  int get progressPercent {
    if (_isStartingUpdate && (_currentStatus == null || _currentStatus!.progressPercent == 0)) {
      return 10;
    }
    return _currentStatus?.progressPercent ?? 0;
  }

  String get statusMessage {
    if (_currentStatus != null && _currentStatus!.message.isNotEmpty) {
      return _currentStatus!.message;
    }
    if (_isStartingUpdate) {
      return 'Starting update...';
    }
    return '';
  }

  String? get errorMessage {
    if (_currentStatus != null) {
      if (isRolledBack) {
        final detail = _currentStatus!.error ??
            (_currentStatus!.message.isNotEmpty ? _currentStatus!.message : 'Update rolled back.');
        return 'Update rolled back: $detail';
      }
      if (_currentStatus!.error != null) {
        return _currentStatus!.error;
      }
      if (isFailed && _currentStatus!.message.isNotEmpty) {
        return 'Update failed: ${_currentStatus!.message}';
      }
    }
    return _checkError;
  }

  UpdateChipState get chipState {
    if (isFailed) return UpdateChipState.error;
    if (isCompleted) return UpdateChipState.reloadRequired;
    if (isRollingBack) return UpdateChipState.rollingBack;
    if (_isStartingUpdate || isRequested) return UpdateChipState.starting;
    if (isStaging || isApplying || isHealthCheck) {
      return UpdateChipState.updating;
    }
    if (isUpdateAvailable) return UpdateChipState.updateAvailable;
    return UpdateChipState.idle;
  }

  void clearError() {
    _checkError = null;
    if (_currentStatus != null && _currentStatus!.isFailed) {
      _currentStatus = null;
      clearTerminalStatus();
    }
    notifyListeners();
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await fetchStatus();
  }

  Future<void> fetchStatus() async {
    try {
      final status = await apiClient.getUpdateStatus();
      _consecutivePollErrors = 0;
      _currentStatus = status;
      _checkError = null;

      if (status.isActive) {
        _isStartingUpdate = false;
        _startPolling();
      } else {
        _isStartingUpdate = false;
        _stopPolling();
        if (status.isCompleted) {
          _reloadRequired = true;
        } else {
          _reloadRequired = false;
        }
      }
      notifyListeners();
    } catch (e) {
      // Retain existing active state across temporary network interruptions
      if (isActive && (_pollTimer == null || !_pollTimer!.isActive)) {
        _startPolling();
      }
    }
  }

  Future<void> checkForUpdates({String? channel, bool forceRefresh = false}) async {
    _isChecking = true;
    _checkError = null;
    notifyListeners();

    try {
      final checkRes = await apiClient.checkForUpdates(
        channel: channel,
        forceRefresh: forceRefresh,
      );
      _latestCheck = checkRes;
      if (!checkRes.checkAvailable) {
        _checkError = checkRes.message ?? 'Unable to check for updates right now.';
      }
    } catch (e) {
      _checkError = 'Update check failed: $e';
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<void> startUpdate() async {
    final ver = targetVersion;
    if (ver == null || ver.isEmpty) return;

    _isStartingUpdate = true;
    _checkError = null;
    notifyListeners();

    try {
      final status = await apiClient.applyUpdate(targetVersion: ver);
      _currentStatus = status;
      _isStartingUpdate = false;
      _startPolling();
      notifyListeners();
    } catch (e) {
      _isStartingUpdate = false;
      if (e.toString().contains('already active')) {
        await fetchStatus();
        return;
      }
      _checkError = 'Failed to start update: $e';
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = await apiClient.getUpdateStatus();
        _consecutivePollErrors = 0;
        _currentStatus = status;

        if (!status.isActive) {
          _stopPolling();
          if (status.isCompleted) {
            _reloadRequired = true;
          } else {
            _reloadRequired = false;
          }
        }
        notifyListeners();
      } catch (e) {
        _consecutivePollErrors++;
        // Container recreation causes temporary network disruption.
        // Retain last known active status and continue retrying.
        if (_consecutivePollErrors >= maxConsecutivePollErrors && isActive) {
          _stopPolling();
          _checkError = 'Connection to node timed out during update. Node may be restarting.';
          notifyListeners();
        }
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> clearTerminalStatus() async {
    try {
      final status = await apiClient.clearUpdateStatus();
      _currentStatus = status;
    } catch (_) {
      // Local fallback reset
      if (_currentStatus != null && _currentStatus!.isCompleted) {
        _currentStatus = UpdateStatusResponse(
          state: 'idle',
          currentVersion: _currentStatus!.currentVersion,
          progressPercent: 0,
          message: 'System is up to date.',
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        );
      }
    } finally {
      _reloadRequired = false;
      notifyListeners();
    }
  }

  Future<void> reloadNow() async {
    await clearTerminalStatus();
    PlatformReload.reload();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
