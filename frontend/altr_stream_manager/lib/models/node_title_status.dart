import 'package:flutter/material.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'node_status.dart';
export 'node_status.dart';


/// Master operational status driving all UI states for Altr Stream Manager.
enum NodeTitleStatus {
  discovering,
  dockerNotInstalled,
  dockerStopped,
  dockerPaused,
  dockerStarting,
  dockerError,
  nodeNotInstalled,
  nodeStopped,
  nodePaused,
  nodeRunning,
  nodeInstalling,
  nodeUpdating,
  nodeUpdateFailed,
  nodeFailing,
  nodeFailed,
  nodeRepairing,
  nodeRepairFailed,
  nodeUninstalling;

  /// Determines the [NodeTitleStatus] from the live [NodeStatus].
  static NodeTitleStatus fromNodeStatus(NodeStatus status) {
    if (status.dockerDiag.state == DockerState.unknown && status.nodeState == NodeState.unknown) {
      return NodeTitleStatus.discovering;
    }

    // 1. Docker daemon prerequisites strictly take precedence over container state.
    // A failed daemon connection is never equated with the node being corrupt or permanently failed.
    switch (status.dockerDiag.state) {
      case DockerState.notInstalled:
        return NodeTitleStatus.dockerNotInstalled;
      case DockerState.stopped:
        return NodeTitleStatus.dockerStopped;
      case DockerState.paused:
        return NodeTitleStatus.dockerPaused;
      case DockerState.starting:
        return NodeTitleStatus.dockerStarting;
      case DockerState.error:
        return NodeTitleStatus.dockerError;
      case DockerState.unknown:
        return NodeTitleStatus.discovering;
      case DockerState.ready:
        break; // Daemon is active; proceed to independently evaluate container runtime state.
    }

    // 2. Docker daemon is ready: now evaluate Altr Stream container runtime state.
    if (status.nodeState == NodeState.error) {
      return NodeTitleStatus.nodeFailed;
    }

    switch (status.nodeState) {
      case NodeState.installing:
        return NodeTitleStatus.nodeInstalling;
      case NodeState.updating:
        return NodeTitleStatus.nodeUpdating;
      case NodeState.notInstalled:
        return NodeTitleStatus.nodeNotInstalled;
      case NodeState.stopped:
        return NodeTitleStatus.nodeStopped;
      case NodeState.paused:
        return NodeTitleStatus.nodePaused;
      case NodeState.error:
        return NodeTitleStatus.nodeFailed;
      case NodeState.running:
        if (!status.healthy && status.technicalIssues.isNotEmpty) {
          return NodeTitleStatus.nodeFailing;
        }
        return NodeTitleStatus.nodeRunning;
      case NodeState.unknown:
        if (!status.isInstalled) {
          return NodeTitleStatus.nodeNotInstalled;
        }
        return NodeTitleStatus.nodeStopped;
    }
  }
}

/// Extension to derive Docker and Node statuses and activity from the master [NodeTitleStatus].
extension NodeTitleStatusX on NodeTitleStatus {
  DockerState get dockerState {
    switch (this) {
      case NodeTitleStatus.discovering:
        return DockerState.unknown;
      case NodeTitleStatus.dockerNotInstalled:
        return DockerState.notInstalled;
      case NodeTitleStatus.dockerStopped:
        return DockerState.stopped;
      case NodeTitleStatus.dockerPaused:
        return DockerState.paused;
      case NodeTitleStatus.dockerStarting:
        return DockerState.starting;
      case NodeTitleStatus.dockerError:
        return DockerState.error;
      default:
        return DockerState.ready;
    }
  }

  NodeState get nodeState {
    switch (this) {
      case NodeTitleStatus.discovering:
        return NodeState.unknown;
      case NodeTitleStatus.dockerNotInstalled:
      case NodeTitleStatus.dockerStopped:
      case NodeTitleStatus.dockerPaused:
      case NodeTitleStatus.dockerStarting:
      case NodeTitleStatus.dockerError:
      case NodeTitleStatus.nodeStopped:
        return NodeState.stopped;
      case NodeTitleStatus.nodePaused:
        return NodeState.paused;
      case NodeTitleStatus.nodeNotInstalled:
        return NodeState.notInstalled;
      case NodeTitleStatus.nodeRunning:
        return NodeState.running;
      case NodeTitleStatus.nodeInstalling:
        return NodeState.installing;
      case NodeTitleStatus.nodeUpdating:
        return NodeState.updating;
      case NodeTitleStatus.nodeUpdateFailed:
      case NodeTitleStatus.nodeFailing:
      case NodeTitleStatus.nodeFailed:
      case NodeTitleStatus.nodeRepairFailed:
        return NodeState.error;
      case NodeTitleStatus.nodeRepairing:
      case NodeTitleStatus.nodeUninstalling:
        return NodeState.stopped;
    }
  }

  bool get isProgressActive {
    switch (this) {
      case NodeTitleStatus.discovering:
      case NodeTitleStatus.dockerStarting:
      case NodeTitleStatus.nodeInstalling:
      case NodeTitleStatus.nodeUpdating:
      case NodeTitleStatus.nodeRepairing:
      case NodeTitleStatus.nodeUninstalling:
        return true;
      default:
        return false;
    }
  }
}

IconData buildAltrNodeTitleStatusIcon(NodeTitleStatus status) {
  switch (status) {
    case NodeTitleStatus.discovering:
      return HugeIconsStroke.loading03;
    case NodeTitleStatus.dockerNotInstalled:
    case NodeTitleStatus.nodeNotInstalled:
      return HugeIconsStroke.download02;
    case NodeTitleStatus.dockerStopped:
    case NodeTitleStatus.nodeStopped:
      return HugeIconsStroke.stopCircle;
    case NodeTitleStatus.dockerPaused:
    case NodeTitleStatus.nodePaused:
      return HugeIconsStroke.pauseCircle;
    case NodeTitleStatus.dockerStarting:
      return HugeIconsStroke.loading03;
    case NodeTitleStatus.dockerError:
      return HugeIconsStroke.alert02;
    case NodeTitleStatus.nodeRunning:
      return HugeIconsStroke.checkmarkBadge01;
    case NodeTitleStatus.nodeInstalling:
    case NodeTitleStatus.nodeUpdating:
      return HugeIconsStroke.arrowDownBig;
    case NodeTitleStatus.nodeUpdateFailed:
    case NodeTitleStatus.nodeRepairFailed:
      return HugeIconsStroke.cancelCircleHalfDot;
    case NodeTitleStatus.nodeFailing:
      return HugeIconsStroke.alert01;
    case NodeTitleStatus.nodeFailed:
      return HugeIconsStroke.multiplicationSignCircle;
    case NodeTitleStatus.nodeRepairing:
      return HugeIconsStroke.tools;
    case NodeTitleStatus.nodeUninstalling:
      return HugeIconsStroke.clean;
  }
}

String buildAltrNodeTitleStatusText(NodeTitleStatus status, BuildContext context) {
  switch (status) {
    case NodeTitleStatus.discovering:
      return "Checking System Status...";
    case NodeTitleStatus.dockerNotInstalled:
      return "Docker Desktop not Installed";
    case NodeTitleStatus.dockerStopped:
      return "Docker Desktop not Running";
    case NodeTitleStatus.dockerPaused:
      return "Docker Desktop Paused";
    case NodeTitleStatus.dockerStarting:
      return "Docker Desktop Starting";
    case NodeTitleStatus.dockerError:
      return "Docker Desktop Error";
    case NodeTitleStatus.nodeNotInstalled:
      return "Altr Stream not Installed";
    case NodeTitleStatus.nodeStopped:
      return "Altr Stream Stopped";
    case NodeTitleStatus.nodePaused:
      return "Altr Stream Paused";
    case NodeTitleStatus.nodeRunning:
      return "Altr Stream Running";
    case NodeTitleStatus.nodeInstalling:
      return "Altr Stream Installing";
    case NodeTitleStatus.nodeUpdating:
      return "Altr Stream Updating";
    case NodeTitleStatus.nodeUpdateFailed:
      return "Altr Stream Update Failed";
    case NodeTitleStatus.nodeFailing:
      return "Altr Stream Failing";
    case NodeTitleStatus.nodeFailed:
      return "Altr Stream Failed";
    case NodeTitleStatus.nodeRepairing:
      return "Altr Stream Repairing";
    case NodeTitleStatus.nodeRepairFailed:
      return "Altr Stream Repair Failed";
    case NodeTitleStatus.nodeUninstalling:
      return "Altr Stream Uninstalling";
  }
}

String buildAltrNodeSubtitleStatusText(
  NodeTitleStatus status,
  String dashboardAddress,
  BuildContext context,
) {
  switch (status) {
    case NodeTitleStatus.discovering:
      return "Discovering Docker and runtime environment, please wait...";
    case NodeTitleStatus.dockerNotInstalled:
      return "Docker Desktop is required for Altr Stream. Install Docker Desktop and try again.";
    case NodeTitleStatus.dockerStopped:
      return "Start Docker Desktop and try again";
    case NodeTitleStatus.dockerPaused:
      return "Resume Docker Desktop and try again";
    case NodeTitleStatus.dockerStarting:
      return "Waiting for Docker daemon to become ready, please wait...";
    case NodeTitleStatus.dockerError:
      return "Docker Desktop error detected. Run Diagnose & Fix for details.";
    case NodeTitleStatus.nodeNotInstalled:
      return "Install Altr Stream and try again";
    case NodeTitleStatus.nodeStopped:
      return "Start Altr Stream and try again";
    case NodeTitleStatus.nodePaused:
      return "Resume Altr Stream and try again";
    case NodeTitleStatus.nodeRunning:
      return "Web Interface available at $dashboardAddress";
    case NodeTitleStatus.nodeInstalling:
      return "Altr Stream is installing, please wait";
    case NodeTitleStatus.nodeUpdating:
      return "Altr Stream is updating, please wait";
    case NodeTitleStatus.nodeUpdateFailed:
      return "Altr Stream update failed, please try later";
    case NodeTitleStatus.nodeFailing:
      return "Altr Stream is failing, check health";
    case NodeTitleStatus.nodeFailed:
      return "Altr Stream failed, try repairing node";
    case NodeTitleStatus.nodeRepairing:
      return "Altr Stream is repairing, please wait";
    case NodeTitleStatus.nodeRepairFailed:
      return "Altr Stream repair failed, try again later";
    case NodeTitleStatus.nodeUninstalling:
      return "Altr Stream is uninstalling, please wait";
  }
}

String buildDockerStatusText(DockerState status, BuildContext context) {
  switch (status) {
    case DockerState.notInstalled:
      return "Not Installed";
    case DockerState.stopped:
      return "Not Running";
    case DockerState.paused:
      return "Paused";
    case DockerState.ready:
      return "Running";
    case DockerState.starting:
      return "Starting...";
    case DockerState.error:
      return "Error";
    case DockerState.unknown:
      return "Checking...";
  }
}

String buildAltrNodeStatusText(NodeState status, BuildContext context) {
  switch (status) {
    case NodeState.notInstalled:
      return "Not Installed";
    case NodeState.stopped:
      return "Node Stopped";
    case NodeState.paused:
      return "Node Paused";
    case NodeState.running:
      return "Running";
    case NodeState.installing:
      return "Installing...";
    case NodeState.updating:
      return "Updating...";
    case NodeState.error:
      return "Failed";
    case NodeState.unknown:
      return "Checking...";
  }
}

Color buildAltrNodeTitleStatusColor(NodeTitleStatus status, BuildContext context) {
  final brightness = View.of(context).platformDispatcher.platformBrightness;
  final isLight = brightness == Brightness.light;

  final red = isLight ? Colors.red.shade700 : Colors.red;
  final orange = isLight ? Colors.orange.shade800 : Colors.orange;
  final green = isLight ? Colors.green.shade700 : Colors.lightGreen;
  final blue = isLight ? Colors.blue.shade700 : Colors.lightBlue;

  switch (status) {
    case NodeTitleStatus.dockerNotInstalled:
    case NodeTitleStatus.dockerStopped:
    case NodeTitleStatus.dockerError:
    case NodeTitleStatus.nodeNotInstalled:
    case NodeTitleStatus.nodeStopped:
    case NodeTitleStatus.nodeUpdateFailed:
    case NodeTitleStatus.nodeFailed:
    case NodeTitleStatus.nodeRepairFailed:
      return red;
    case NodeTitleStatus.discovering:
      return isLight ? Colors.grey.shade700 : Colors.grey.shade400;
    case NodeTitleStatus.dockerPaused:
    case NodeTitleStatus.nodePaused:
    case NodeTitleStatus.dockerStarting:
    case NodeTitleStatus.nodeFailing:
      return orange;
    case NodeTitleStatus.nodeRunning:
      return green;
    case NodeTitleStatus.nodeInstalling:
    case NodeTitleStatus.nodeUpdating:
    case NodeTitleStatus.nodeRepairing:
    case NodeTitleStatus.nodeUninstalling:
      return blue;
  }
}

Color buildDockerStatusColor(DockerState status, BuildContext context) {
  final brightness = View.of(context).platformDispatcher.platformBrightness;
  final isLight = brightness == Brightness.light;

  final red = isLight ? Colors.red.shade700 : Colors.red;
  final orange = isLight ? Colors.orange.shade800 : Colors.orange;
  final green = isLight ? Colors.green.shade700 : Colors.lightGreen;

  switch (status) {
    case DockerState.ready:
      return green;
    case DockerState.paused:
    case DockerState.starting:
      return orange;
    case DockerState.stopped:
    case DockerState.notInstalled:
    case DockerState.error:
      return red;
    case DockerState.unknown:
      return isLight ? Colors.grey.shade600 : Colors.grey.shade400;
  }
}

Color buildAltrNodeStatusColor(NodeState status, BuildContext context) {
  final brightness = View.of(context).platformDispatcher.platformBrightness;
  final isLight = brightness == Brightness.light;

  final red = isLight ? Colors.red.shade700 : Colors.red;
  final orange = isLight ? Colors.orange.shade800 : Colors.orange;
  final green = isLight ? Colors.green.shade700 : Colors.lightGreen;
  final blue = isLight ? Colors.blue.shade700 : Colors.lightBlue;

  switch (status) {
    case NodeState.running:
      return green;
    case NodeState.paused:
      return orange;
    case NodeState.installing:
    case NodeState.updating:
      return blue;
    case NodeState.stopped:
    case NodeState.notInstalled:
    case NodeState.error:
      return red;
    case NodeState.unknown:
      return isLight ? Colors.grey.shade600 : Colors.grey.shade400;
  }
}
