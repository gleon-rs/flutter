// The integration is the input of a session; both mirror one native call.
// ignore_for_file: prefer-single-declaration-per-file

import 'dart:ffi';

import 'package:meta/meta.dart';

import '../native/gleon_ffi.dart';
import '../native/native_engine.dart';

/// Per-process gleon state held by the native engine: the workspaces of the
/// goldens (each golden belongs to the nearest directory above it with
/// `.gleon/gleon.yaml`), their configs (read again when they change) and the
/// `GLEON_METRICS` value.
final class GleonSession implements Finalizable {
  /// Opens a session; without [hasWorkspaces] no golden belongs to a
  /// workspace (tests of the behavior without one). The native engine reads
  /// `GLEON_METRICS` from the environment unless [metricsEnv] overrides it
  /// ([unsetMetricsEnv] for unset), as tests do.
  GleonSession({
    required GleonIntegration integration,
    bool hasWorkspaces = true,
    String? metricsEnv,
  }) : handle = NativeEngine.openSession(
         hasWorkspaces: hasWorkspaces,
         metricsEnv: metricsEnv,
         integration: integration,
       ) {
    NativeEngine.sessionFinalizer.attach(
      this,
      handle.cast<Void>(),
      detach: this,
    );
  }

  /// The `metricsEnv` override of an unset `GLEON_METRICS`.
  static const unsetMetricsEnv = '';

  /// The native session, released when this object is garbage collected.
  final Pointer<GleonSessionHandle> handle;
}

/// Who talks to the engine: recorded in case reports and used to name the
/// failure artifacts in the integration's own convention.
@immutable
final class GleonIntegration {
  /// Creates the description. Each artifact pattern contains `{name}`, the
  /// golden's file name without its extension.
  const GleonIntegration({
    required this.tool,
    required this.toolVersion,
    required this.goldenArtifact,
    required this.candidateArtifact,
    required this.diffArtifact,
    this.renderer,
  });

  /// Integration name, e.g. `gleon_flutter`.
  final String tool;

  /// Integration version.
  final String toolVersion;

  /// Renderer identifier, e.g. `flutter-3.47.5`.
  final String? renderer;

  /// File name of the golden copy, e.g. `{name}_masterImage.png`.
  final String goldenArtifact;

  /// File name of the candidate, e.g. `{name}_testImage.png`.
  final String candidateArtifact;

  /// File name of the diff image, e.g. `{name}_gleonDiff.png`.
  final String diffArtifact;
}
