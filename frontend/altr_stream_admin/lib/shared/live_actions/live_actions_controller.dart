import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../core/auth/services/passcode_service.dart';
import '../../core/updates/update_controller.dart';
import 'live_action_model.dart';

/// Coordinates contextual Live Actions in the app bar, aggregating Sudo,
/// and Feedback actions according to dynamic application state and priority.
class LiveActionsController extends ChangeNotifier {
  final UpdateController? updateController;
  final VoidCallback? onOpenFeedback;
  final VoidCallback? onOpenUpdateDialog;
  final VoidCallback? onTriggerReload;
  final VoidCallback? onRequestLockSudo;
  final bool showFeedbackAction;

  final Map<String, LiveAction> _customActions = {};

  DateTime? _sudoExpiresAt;
  Timer? _sudoTimer;

  bool get isSudoActive =>
      _sudoExpiresAt != null && DateTime.now().isBefore(_sudoExpiresAt!);

  int get sudoRemainingSeconds {
    if (!isSudoActive || _sudoExpiresAt == null) return 0;
    final diff = _sudoExpiresAt!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  void activateSudo({int durationSeconds = 300}) {
    _sudoExpiresAt = DateTime.now().add(Duration(seconds: durationSeconds));
    _sudoTimer?.cancel();
    _sudoTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!isSudoActive) {
        _sudoTimer?.cancel();
        _sudoTimer = null;
        _sudoExpiresAt = null;
        notifyListeners();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void lockSudo() {
    _sudoTimer?.cancel();
    _sudoTimer = null;
    _sudoExpiresAt = null;
    PasscodeService().lockSudo();
    notifyListeners();
  }

  LiveActionsController({
    this.updateController,
    this.onOpenFeedback,
    this.onOpenUpdateDialog,
    this.onTriggerReload,
    this.onRequestLockSudo,
    this.showFeedbackAction = true,
  });

  @override
  void dispose() {
    _sudoTimer?.cancel();
    super.dispose();
  }

  /// Register or override an arbitrary contextual Live Action.
  void registerAction(LiveAction action) {
    _customActions[action.id] = action;
    notifyListeners();
  }

  /// Remove a custom Live Action by ID.
  void removeAction(String id) {
    if (_customActions.remove(id) != null) {
      notifyListeners();
    }
  }

  /// Returns all currently active and visible Live Actions, sorted by priority.
  List<LiveAction> get activeActions {
    final actions = <LiveAction>[];

    // 0. Sudo Mode Grace Period Live Activity (Priority Critical / Top)
    if (isSudoActive) {
      final mins = (sudoRemainingSeconds ~/ 60).toString().padLeft(2, '0');
      final secs = (sudoRemainingSeconds % 60).toString().padLeft(2, '0');
      actions.add(
        LiveAction(
          id: 'sudo',
          key: const ValueKey('app_bar_sudo_chip'),
          label: 'Sudo · $mins:$secs',
          icon: HugeIcons.strokeRoundedSecurityLock,
          priority: LiveActionPriority.critical,
          tooltip:
              'Sudo mode active (expires in $mins:$secs). Click to lock elevated privileges.',
          backgroundColor: Colors.amber.withValues(alpha: 0.15),
          foregroundColor: Colors.amber.shade400,
          borderColor: Colors.amber.withValues(alpha: 0.5),
          onTap: onRequestLockSudo ?? lockSudo,
        ),
      );
    }

    // 2. Evaluate Feedback Action
    if (showFeedbackAction && onOpenFeedback != null) {
      actions.add(
        LiveAction(
          id: 'feedback',
          key: const ValueKey('live_action_feedback'),
          label: 'Feedback',
          icon: HugeIcons.strokeRoundedMessageQuestion,
          priority: LiveActionPriority.feedback,
          tooltip: 'Share Beta feedback or report an issue',
          onTap: onOpenFeedback,
        ),
      );
    }

    // 3. Add Custom Registered Actions
    for (final custom in _customActions.values) {
      if (custom.isVisible) {
        actions.add(custom);
      }
    }

    // 4. Sort strictly by priority rank ascending (0 is highest priority)
    actions.sort((a, b) => a.priority.rank.compareTo(b.priority.rank));

    return actions;
  }
}
