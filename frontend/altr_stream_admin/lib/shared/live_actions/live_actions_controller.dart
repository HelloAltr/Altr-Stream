import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../core/updates/update_controller.dart';
import 'live_action_model.dart';

/// Coordinates contextual Live Actions in the app bar, aggregating Update, Reload,
/// and Feedback actions according to dynamic application state and priority.
class LiveActionsController extends ChangeNotifier {
  final UpdateController? updateController;
  final VoidCallback? onOpenFeedback;
  final VoidCallback? onOpenUpdateDialog;
  final VoidCallback? onTriggerReload;
  final bool showFeedbackAction;

  final Map<String, LiveAction> _customActions = {};

  LiveActionsController({
    this.updateController,
    this.onOpenFeedback,
    this.onOpenUpdateDialog,
    this.onTriggerReload,
    this.showFeedbackAction = true,
  }) {
    updateController?.addListener(_onUpdateControllerChanged);
  }

  @override
  void dispose() {
    updateController?.removeListener(_onUpdateControllerChanged);
    super.dispose();
  }

  void _onUpdateControllerChanged() {
    notifyListeners();
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

    // 1. Evaluate Update & Reload Actions from UpdateController
    if (updateController != null) {
      final chipState = updateController!.chipState;

      if (chipState == UpdateChipState.reloadRequired) {
        // Priority 3 (reload-required action)
        actions.add(
          LiveAction(
            id: 'reload',
            key: const ValueKey('app_bar_update_chip'),
            label: 'Reload required',
            icon: HugeIcons.strokeRoundedRefresh,
            priority: LiveActionPriority.reload,
            tooltip:
                'Update applied successfully. Click to reload application.',
            onTap: onTriggerReload ?? onOpenUpdateDialog,
          ),
        );
      } else if (chipState != UpdateChipState.idle) {
        // Priority 2 (update/install action)
        switch (chipState) {
          case UpdateChipState.updateAvailable:
            final targetVer = updateController!.targetVersion ?? '';
            actions.add(
              LiveAction(
                id: 'update',
                key: const ValueKey('app_bar_update_chip'),
                label: targetVer.isNotEmpty
                    ? 'Update Available · v$targetVer'
                    : 'Update Available',
                icon: HugeIcons.strokeRoundedDownload04,
                priority: LiveActionPriority.update,
                tooltip: targetVer.isNotEmpty
                    ? 'Update v$targetVer is available. Click to review.'
                    : 'An update is available. Click to review.',
                onTap: onOpenUpdateDialog,
              ),
            );
            break;

          case UpdateChipState.starting:
            actions.add(
              LiveAction(
                id: 'update',
                key: const ValueKey('app_bar_update_chip'),
                label: 'Starting update...',
                icon: const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                priority: LiveActionPriority.update,
                tooltip: 'Preparing update workflow...',
                onTap: onOpenUpdateDialog,
              ),
            );
            break;

          case UpdateChipState.updating:
            final pct = updateController!.progressPercent;
            actions.add(
              LiveAction(
                id: 'update',
                key: const ValueKey('app_bar_update_chip'),
                label: 'Updating $pct%',
                icon: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: pct > 0 ? (pct / 100.0).clamp(0.0, 1.0) : null,
                  ),
                ),
                priority: LiveActionPriority.update,
                tooltip: updateController!.statusMessage.isNotEmpty
                    ? updateController!.statusMessage
                    : 'Applying update ($pct%)...',
                onTap: onOpenUpdateDialog,
              ),
            );
            break;

          case UpdateChipState.rollingBack:
            final pct = updateController!.progressPercent;
            actions.add(
              LiveAction(
                id: 'update',
                key: const ValueKey('app_bar_update_chip'),
                label: pct > 0 ? 'Rolling back... ($pct%)' : 'Rolling back...',
                icon: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: pct > 0 ? (pct / 100.0).clamp(0.0, 1.0) : null,
                  ),
                ),
                priority: LiveActionPriority.update,
                tooltip: updateController!.statusMessage.isNotEmpty
                    ? updateController!.statusMessage
                    : 'Rolling back update to previous version...',
                onTap: onOpenUpdateDialog,
              ),
            );
            break;

          case UpdateChipState.error:
            actions.add(
              LiveAction(
                id: 'update',
                key: const ValueKey('app_bar_update_chip'),
                label: 'Update failed',
                icon: HugeIcons.strokeRoundedAlertCircle,
                priority: LiveActionPriority.update,
                tooltip:
                    updateController!.errorMessage ??
                    'Update encountered an error. Click for details.',
                onTap: onOpenUpdateDialog,
              ),
            );
            break;

          case UpdateChipState.idle:
          case UpdateChipState.reloadRequired:
            break;
        }
      }
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
