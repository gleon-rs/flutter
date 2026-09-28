import 'dart:io';

import '../native/native_engine.dart';
import 'gleon_workspace.dart';
import 'golden_resolution.dart';

/// Per-process gleon state: the workspace found from the working directory
/// (the config is read once) and the `GLEON_METRICS` value.
final class GleonSession {
  /// Creates a session; tests inject their own workspace and environment.
  GleonSession({required this.workspace, required this.metricsEnv});

  /// Name of the environment variable that overrides `metrics.enabled`.
  static const metricsEnvName = 'GLEON_METRICS';

  /// The session of this process, created on first use.
  static final process = GleonSession(
    workspace: GleonWorkspace.find(.current),
    metricsEnv: Platform.environment[metricsEnvName],
  );

  /// The workspace, or null without `.gleon/gleon.yaml`.
  final GleonWorkspace? workspace;

  /// Raw `GLEON_METRICS` value, or null when unset.
  final String? metricsEnv;

  bool _isWarned = false;

  /// Resolves the rule of [golden] (an existing file), or returns null when
  /// there is no workspace or [golden] lies outside it.
  GoldenResolution? resolve(File golden) {
    final current = workspace;
    if (current == null) return null;
    final path = current.relativePath(golden);
    if (path == null) return null;

    return NativeEngine.resolve(
      yaml: current.configText,
      path: path,
      metricsEnv: metricsEnv,
    );
  }

  /// A warning, returned once per session, when metrics are requested through
  /// `GLEON_METRICS` but there is no workspace to record them in.
  String? takeMissingWorkspaceWarning() {
    final value = metricsEnv?.trim().toLowerCase();
    final isRequested =
        value != null && value.isNotEmpty && value != '0' && value != 'false';
    if (_isWarned || workspace != null || !isRequested) return null;
    _isWarned = true;

    return 'gleon: $metricsEnvName is set but there is no .gleon/gleon.yaml: '
        'create it (same format as the gleon CLI, see `gleon init`); metrics '
        'are written to .gleon/runs/latest/cases/.';
  }
}
