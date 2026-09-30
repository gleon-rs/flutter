import 'dart:async';

import 'package:flutter_test/flutter_test.dart' as flutter_test;

import '../core/compare/golden_tolerance.dart';
import '../core/compare/pixel_region.dart';
import '../core/config/gleon_session.dart';
import 'flutter_session.dart';
import 'gleon_golden_comparator.dart';

/// The matcher created by `matchesGoldenFile`.
///
/// Reuses Flutter's own [flutter_test.MatchesGoldenFile] for capturing,
/// encoding, version handling and `--update-goldens`, and only swaps the
/// comparison backend for the duration of the match.
class GleonMatchesGoldenFile extends flutter_test.MatchesGoldenFile {
  /// Creates the matcher; prefer `matchesGoldenFile`, which validates the
  /// arguments.
  const GleonMatchesGoldenFile(
    super.key,
    super.version, {
    this.tolerance,
    this.masks = const [],
    this.session,
  });

  /// The requested tolerance; null means the golden's `.gleon/gleon.yaml`
  /// rule, else exact.
  final GoldenTolerance? tolerance;

  /// Regions excluded from the comparison, in whole pixels of the golden.
  final List<PixelRegion> masks;

  /// Workspace and environment; [FlutterSession.process] when null (tests
  /// inject their own).
  final GleonSession? session;

  /// The turn of the match currently holding `goldenFileComparator`, if any;
  /// it completes when the match releases it.
  static Completer<void>? _inFlight;

  @override
  Future<String?> matchAsync(Object? item) async {
    // `goldenFileComparator` is process-global: overlapping matches (possible
    // for byte inputs; Flutter already serializes Finder captures) would wrap
    // or restore each other's comparator, so they take turns. Only an actual
    // overlap waits: awaiting a future of an earlier test would schedule the
    // continuation in that test's finished (fake async) zone.
    while (_inFlight != null) {
      await _inFlight?.future;
    }
    final turn = Completer<void>();
    _take(turn);
    final original = flutter_test.goldenFileComparator;
    try {
      // Inside the `try`: finding the workspace may throw, and the turn must
      // still be released.
      flutter_test.goldenFileComparator = GleonGoldenComparator(
        original,
        tolerance: tolerance,
        masks: masks,
        session: session,
      );

      return await super.matchAsync(item);
    } finally {
      flutter_test.goldenFileComparator = original;
      _release(turn);
    }
  }

  /// Takes the [turn]. A match abandoned by a timed-out test never reaches
  /// its `finally`, so the turn is also released when that test ends: later
  /// tests never block, and matches already waiting for it wake up.
  static void _take(Completer<void> turn) {
    _inFlight = turn;
    // Outside a test (`addTearDown` would throw) nothing can abandon it.
    if (FlutterSession.currentTestName != null) {
      flutter_test.addTearDown(() => _release(turn));
    }
  }

  /// Releases [turn] (once; a later call is a no-op) and wakes its waiters.
  static void _release(Completer<void> turn) {
    if (identical(_inFlight, turn)) _inFlight = null;
    if (!turn.isCompleted) turn.complete();
  }

  @override
  flutter_test.Description describe(flutter_test.Description description) =>
      super
          .describe(description)
          .add(' (gleon ${tolerance ?? 'default tolerance'})');
}
