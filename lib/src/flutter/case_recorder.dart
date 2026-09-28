import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show FlutterVersion;
import 'package:test_api/hooks.dart' show OutsideTestException, TestHandle;

import '../core/config/gleon_workspace.dart';
import '../core/config/golden_plan.dart';
import '../core/config/golden_resolution.dart';
import '../core/native/native_metrics.dart';
import '../core/native/native_report.dart';
import '../core/report/case_outcome.dart';
import '../core/report/case_report.dart';
import '../core/report/case_source.dart';
import '../core/report/console_line.dart';
import '../core/report/png_info.dart';

/// Records the case report (and console line) of one comparison when its
/// [plan] asks for it: metrics enabled and a `.gleon/gleon.yaml` rule matches.
final class CaseRecorder {
  /// Creates the recorder for [plan] in [workspace].
  const CaseRecorder(this.plan, this.workspace);

  /// What the comparison uses and whether it records.
  final GoldenPlan plan;

  /// The workspace to record into.
  final GleonWorkspace? workspace;

  /// Version of this package, recorded in case reports
  /// (`source.tool_version`). Keep in sync with `pubspec.yaml`; a test checks
  /// it.
  static const packageVersion = '0.1.0';

  /// The running test's full name, or null outside a test.
  static String? get currentTestName {
    try {
      return TestHandle.current.name;
    } on OutsideTestException {
      return null;
    }
  }

  /// Records [outcome] of the PNG bytes of [golden] against [candidate] after
  /// [elapsed]; the native [report] supplies metrics, message and timings when
  /// it ran. The images are only hashed when a case is actually recorded.
  Future<void> record({
    required CaseOutcome outcome,
    required Uint8List golden,
    required Uint8List candidate,
    required Duration elapsed,
    NativeReport? report,
  }) async {
    final GoldenPlan(:goldenPath, :resolved, :tolerance) = plan;
    final root = workspace;
    final name = resolved?.matched?.name;
    if (resolved == null ||
        !resolved.shouldRecordCase ||
        name == null ||
        root == null ||
        goldenPath == null) {
      return;
    }
    final (metrics, message) = _details(report);
    final totalMilliseconds = elapsed.inMicroseconds / 1000;
    await _report(
      resolved,
      target: (name: name, path: goldenPath),
      images: (candidate: .of(candidate), golden: .of(golden)),
      outcome: outcome,
      totalMilliseconds: totalMilliseconds,
      report: report,
    ).write(root);
    if (resolved.metrics.isConsoleEnabled) {
      debugPrint(
        ConsoleLine.format(
          goldenPath: goldenPath,
          outcome: outcome,
          tolerance: tolerance,
          totalMilliseconds: totalMilliseconds,
          metrics: metrics,
          message: message,
        ),
      );
    }
  }

  CaseReport _report(
    ResolvedGolden resolved, {
    required ({String name, String path}) target,
    required ({PngInfo candidate, PngInfo golden}) images,
    required CaseOutcome outcome,
    required double totalMilliseconds,
    NativeReport? report,
  }) {
    final ResolvedGolden(:platform, :policyVersion) = resolved;
    final (metrics, message) = _details(report);
    final comparison = switch (report) {
      final NativeComparison ran => ran,
      NativeError() || null => null,
    };

    return CaseReport(
      name: target.name,
      goldenPath: target.path,
      golden: images.golden,
      candidate: images.candidate,
      source: CaseSource(
        tool: 'gleon_flutter',
        toolVersion: packageVersion,
        renderer: switch (FlutterVersion.version) {
          final version? => 'flutter-$version',
          null => null,
        },
      ),
      platform: platform,
      tolerance: plan.tolerance,
      masks: plan.masks,
      policyVersion: comparison?.policyVersion ?? policyVersion,
      outcome: outcome,
      totalMilliseconds: totalMilliseconds,
      recordedAt: DateTime.now(),
      testName: currentTestName,
      message: message,
      metrics: metrics,
      nativeMilliseconds: comparison?.timings.totalMilliseconds,
    );
  }

  /// The case outcome of a native [report].
  static CaseOutcome outcomeOf(NativeReport report) => switch (report) {
    NativeMatch() => .match,
    NativeMismatch() => .mismatch,
    NativeDimensionMismatch() => .dimensionMismatch,
    NativeError() => .error,
  };

  static (NativeMetrics?, String?) _details(NativeReport? report) =>
      switch (report) {
        NativeMatch(:final metrics) => (metrics, null),
        NativeMismatch(:final metrics, :final summary) => (metrics, summary),
        NativeDimensionMismatch(:final summary) => (null, summary),
        NativeError(:final message) => (null, message),
        null => (null, null),
      };
}
