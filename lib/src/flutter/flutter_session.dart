import 'package:flutter/services.dart' show FlutterVersion;
import 'package:meta/meta.dart';
import 'package:test_api/hooks.dart' show OutsideTestException, TestHandle;

import '../core/config/gleon_session.dart';

/// This package as a gleon integration, and its per-process session.
abstract final class FlutterSession {
  /// Version of this package, recorded in case reports
  /// (`source.tool_version`). Keep in sync with `pubspec.yaml`; a test checks
  /// it.
  static const packageVersion = '0.5.0';

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

  /// The environment [process] takes instead of the process's: this
  /// package's own tests set an empty one, so the `GLEON_*` variables of the
  /// shell they run in never apply to them (`test/flutter_test_config.dart`).
  @visibleForTesting
  // ignore: avoid-global-state, set once by the test config, before any session.
  static GleonEnvironment? debugEnvironment;

  static GleonSession? _process;

  /// The session of this process: each golden belongs to the workspace above
  /// it (not the working directory, which a test may change); metrics, the
  /// artifacts directory, the run id and the canonical goldens follow
  /// `GLEON_METRICS`, `GLEON_ARTIFACTS_DIR`, `GLEON_RUN_ID` and
  /// `GLEON_REQUIRE_CANONICAL` of the process (read by the native engine),
  /// unless [debugEnvironment] was set before its first use.
  static GleonSession get process => _process ??= .new(
    integration: integration,
    environment: debugEnvironment,
  );

  /// The running test's full name, or null outside a test.
  static String? get currentTestName {
    try {
      return TestHandle.current.name;
    } on OutsideTestException {
      return null;
    }
  }
}
