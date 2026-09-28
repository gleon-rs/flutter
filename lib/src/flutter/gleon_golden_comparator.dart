import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import '../core/compare/golden_tolerance.dart';
import '../core/compare/mask_zone.dart';
import '../core/compare/pixel_region.dart';
import '../core/config/gleon_config_exception.dart';
import '../core/config/gleon_session.dart';
import '../core/config/golden_plan.dart';
import '../core/native/native_engine.dart';
import '../core/native/native_report.dart';
import 'case_recorder.dart';
import 'failure_artifacts.dart';

/// A [GoldenFileComparator] that compares with the gleon engine while
/// delegating golden path resolution and `--update-goldens` writes to the
/// comparator it wraps (normally Flutter's [LocalFileComparator]), so golden
/// files live exactly where they would without this package.
///
/// With a `.gleon/gleon.yaml` workspace, the golden's rule supplies the
/// tolerance and masks unless the matcher call overrides them, and case
/// reports are recorded when metrics are enabled.
class GleonGoldenComparator extends GoldenFileComparator {
  /// Wraps [delegate]; [tolerance] and [masks] come from the matcher call.
  /// [session] defaults to [GleonSession.process].
  GleonGoldenComparator(
    this.delegate, {
    this.tolerance,
    this.masks = const [],
    GleonSession? session,
  }) : session = session ?? .process;

  /// The comparator that was installed before (owns paths and updates).
  final GoldenFileComparator delegate;

  /// The tolerance of the matcher call (see [GoldenPlan.of]).
  final GoldenTolerance? tolerance;

  /// Regions of the matcher call excluded from the comparison, in whole
  /// pixels of the golden.
  final List<PixelRegion> masks;

  /// Workspace and environment of this process.
  final GleonSession session;

  @override
  Uri getTestUri(Uri key, int? version) => delegate.getTestUri(key, version);

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    final stopwatch = Stopwatch()..start();
    await delegate.update(golden, imageBytes);
    final local = delegate;
    if (local is! LocalFileComparator) return;
    await _recorder(_goldenFile(local, golden)).record(
      outcome: .updated,
      golden: imageBytes,
      // ignore: no-equal-arguments, after an update the golden is the candidate.
      candidate: imageBytes,
      elapsed: stopwatch.elapsed,
    );
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final stopwatch = Stopwatch()..start();
    final local = delegate;
    if (local is! LocalFileComparator) {
      throw TestFailure(
        'gleon: matchesGoldenFile needs the default LocalFileComparator, but '
        'goldenFileComparator is ${local.runtimeType}. Custom comparators '
        'are not supported yet.',
      );
    }
    final goldenFile = _goldenFile(local, golden);
    if (!goldenFile.existsSync()) {
      throw TestFailure(
        'Could not be compared against non-existent file: "$golden"',
      );
    }
    final recorder = _recorder(goldenFile);
    final goldenBytes = await goldenFile.readAsBytes();

    // Identical encodings are identical pixels: skip decoding entirely.
    if (_isSameBytes(goldenBytes, imageBytes)) {
      await recorder.record(
        outcome: .identical,
        golden: goldenBytes,
        candidate: imageBytes,
        elapsed: stopwatch.elapsed,
      );

      return true;
    }

    return await _isNativeMatch(
      recorder,
      local: local,
      golden: golden,
      bytes: (golden: goldenBytes, test: imageBytes),
      stopwatch: stopwatch,
    );
  }

  Future<bool> _isNativeMatch(
    CaseRecorder recorder, {
    required LocalFileComparator local,
    required Uri golden,
    required ({Uint8List golden, Uint8List test}) bytes,
    required Stopwatch stopwatch,
  }) async {
    final (golden: goldenBytes, test: imageBytes) = bytes;
    final report = NativeEngine.compare(
      baseline: goldenBytes,
      candidate: imageBytes,
      tolerance: recorder.plan.tolerance,
      masks: recorder.plan.masks,
    );
    await recorder.record(
      outcome: CaseRecorder.outcomeOf(report),
      golden: goldenBytes,
      candidate: imageBytes,
      elapsed: stopwatch.elapsed,
      report: report,
    );
    final plan = recorder.plan;
    switch (report) {
      case NativeMatch():
        return true;

      case NativeError(:final message):
        throw TestFailure(
          'Golden "$golden": gleon could not compare: $message',
        );

      case NativeDimensionMismatch(:final summary):
        throw TestFailure(
          await _failure(
            'image sizes differ: $summary.',
            basedir: local.basedir,
            golden: golden,
            plan: plan,
            bytes: bytes,
          ),
        );

      case NativeMismatch(:final diffPng, :final summary):
        throw TestFailure(
          await _failure(
            '$summary (gleon ${plan.tolerance}).',
            basedir: local.basedir,
            golden: golden,
            plan: plan,
            bytes: bytes,
            diffPng: diffPng,
          ),
        );
    }
  }

  CaseRecorder _recorder(File goldenFile) {
    final warning = session.takeMissingWorkspaceWarning();
    if (warning != null) debugPrint(warning);
    try {
      return CaseRecorder(
        GoldenPlan.of(
          session,
          goldenFile,
          tolerance: tolerance,
          masks: [for (final mask in masks) MaskZone.fromRegion(mask)],
        ),
        session.workspace,
      );
    } on GleonConfigException catch (error, stackTrace) {
      Error.throwWithStackTrace(TestFailure('$error'), stackTrace);
    }
  }

  /// Writes the failure artifacts and returns the failure message for
  /// [reason].
  static Future<String> _failure(
    String reason, {
    required Uri basedir,
    required Uri golden,
    required GoldenPlan plan,
    required ({Uint8List golden, Uint8List test}) bytes,
    Uint8List? diffPng,
  }) async {
    final feedback = await FailureArtifacts.write(
      basedir: basedir,
      golden: golden,
      goldenBytes: bytes.golden,
      testBytes: bytes.test,
      diffPng: diffPng,
    );

    return [
      'Golden "$golden": $reason$feedback',
      // One-line pointer for suites without a workspace.
      if (!plan.hasWorkspace) _workspaceTip,
    ].join('\n');
  }

  static const _workspaceTip =
      'Tip: tolerances can be set per golden in .gleon/gleon.yaml, the same '
      'file as the gleon CLI.';

  static File _goldenFile(LocalFileComparator local, Uri golden) =>
      // Same resolution as LocalFileComparator: the key relative to basedir.
      .fromUri(local.basedir.resolve(golden.path));

  /// The fast path of every unchanged golden: an index loop, measured 12x
  /// faster than `.indexed` (which allocates a record per byte) in AOT.
  static bool _isSameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    // ignore: prefer-for-in, see above.
    for (int index = 0; index < a.length; index += 1) {
      // ignore: avoid-unsafe-collection-methods, both have the same length.
      if (a[index] != b[index]) return false;
    }

    return true;
  }
}
