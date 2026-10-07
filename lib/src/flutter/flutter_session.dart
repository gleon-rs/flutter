import 'package:flutter/services.dart' show FlutterVersion;
import 'package:test_api/hooks.dart' show OutsideTestException, TestHandle;

import '../core/config/gleon_session.dart';

/// This package as a gleon integration, and its per-process session.
abstract final class FlutterSession {
  /// Version of this package, recorded in case reports
  /// (`source.tool_version`). Keep in sync with `pubspec.yaml`; a test checks
  /// it.
  static const packageVersion = '0.2.0';

  /// How this package names itself and, like Flutter's `LocalFileComparator`,
  /// its failure artifacts.
  static final integration = GleonIntegration(
    tool: 'gleon_flutter',
    toolVersion: packageVersion,
    goldenArtifact: '{name}_masterImage.png',
    candidateArtifact: '{name}_testImage.png',
    diffArtifact: '{name}_gleonDiff.png',
    renderer: switch (FlutterVersion.version) {
      final version? => 'flutter-$version',
      null => null,
    },
  );

  /// The session of this process: each golden belongs to the workspace above
  /// it (not the working directory, which a test may change); metrics, the
  /// artifacts directory and the run id follow `GLEON_METRICS`,
  /// `GLEON_ARTIFACTS_DIR` and `GLEON_RUN_ID` of the process (read by the
  /// native engine).
  static final process = GleonSession(integration: integration);

  /// The running test's full name, or null outside a test.
  static String? get currentTestName {
    try {
      return TestHandle.current.name;
    } on OutsideTestException {
      return null;
    }
  }
}
