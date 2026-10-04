import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart' as flutter_test;

import '../core/compare/golden_tolerance.dart';
import '../core/compare/pixel_region.dart';
import '../core/config/gleon_session.dart';
import 'flutter_session.dart';
import 'gleon_golden_comparator.dart';
import 'text_regions.dart';

/// The matcher created by `matchesGoldenFile`.
///
/// Reuses Flutter's own [flutter_test.MatchesGoldenFile] for version
/// handling and image or byte inputs, and only swaps the comparison backend
/// for the duration of the match. A widget (a `Finder`) is captured like
/// Flutter does, but compared as raw pixels with the boxes of its text (a PNG
/// is encoded only to keep it: for a failure, or a pass against another
/// platform's golden with metrics on), and written by `--update-goldens`
/// with the engine's failure as the message, like a comparison.
class GleonMatchesGoldenFile extends flutter_test.MatchesGoldenFile {
  /// Creates the matcher; prefer `matchesGoldenFile`, which validates the
  /// arguments.
  const GleonMatchesGoldenFile(
    super.key,
    super.version, {
    this.tolerance,
    this.masks = const [],
    this.textTolerance,
    this.session,
  });

  /// The requested tolerance; null means the golden's `.gleon/gleon.yaml`
  /// rule, else exact.
  final GoldenTolerance? tolerance;

  /// Regions excluded from the comparison, in whole pixels of the golden.
  final List<PixelRegion> masks;

  /// The tolerance of text, a share of a tile (0.0–1.0); null means the
  /// golden's `.gleon/gleon.yaml` rule, else the golden's default (see
  /// `matchesGoldenFile`).
  final double? textTolerance;

  /// Workspace and environment; [FlutterSession.process] when null (tests
  /// inject their own).
  final GleonSession? session;

  @override
  Future<String?> matchAsync(Object? item) async {
    // `goldenFileComparator` is process-global: overlapping matches (possible
    // for byte inputs; Flutter already serializes Finder captures) would wrap
    // or restore each other's comparator, so they take turns. Only an actual
    // overlap waits: awaiting a future of an earlier test would schedule the
    // continuation in that test's finished (fake async) zone.
    while (_Turn._current != null) {
      await _Turn._current?.done;
    }
    final turn = _Turn.take();
    try {
      // A match abandoned by a timed-out test never reaches its `finally`,
      // so its turn also finishes when that test ends: later tests get their
      // own comparator and never block. Registering throws for a test that
      // already closed; the `finally` still finishes.
      if (FlutterSession.currentTestName != null) {
        flutter_test.addTearDown(() => _Turn.finish(turn));
      }
      // Finding the workspace may throw too.
      final comparator = GleonGoldenComparator(
        turn.original,
        tolerance: tolerance,
        masks: masks,
        textTolerance: textTolerance,
        session: session,
      );
      turn.installed = comparator;
      flutter_test.goldenFileComparator = comparator;

      return await switch (item) {
        final flutter_test.Finder finder => _matchWidget(finder, comparator),
        _ => super.matchAsync(item),
      };
    } finally {
      _Turn.finish(turn);
    }
  }

  @override
  flutter_test.Description describe(flutter_test.Description description) {
    final text = switch (textTolerance) {
      final share? => ', ${GoldenTolerance.describeText(share)}',
      null => _noText,
    };

    return super
        .describe(description)
        .add(' (gleon ${tolerance ?? 'default tolerance'}$text)');
  }

  static const _noText = '';

  /// Captures the widget of [finder] like Flutter's matcher and compares its
  /// raw pixels and text regions, or writes it (`--update-goldens`); the same
  /// messages for a bad finder. A failure is the message in both modes
  /// (Flutter's own update path would report it as a framework exception).
  Future<String?> _matchWidget(
    flutter_test.Finder finder,
    GleonGoldenComparator comparator,
  ) {
    final found = finder.evaluate();
    if (found.isEmpty) {
      return .value('could not be rendered because no widget was found');
    }
    final element = found.singleOrNull;
    if (element == null) return .value('matched too many widgets');
    final golden = comparator.getTestUri(key, version);
    final isUpdate = flutter_test.autoUpdateGoldenFiles;
    // Before capturing (nothing to dispose if it throws) and before awaiting
    // anything: the tree must be the one captured.
    final textRegions = isUpdate
        ? const <PixelRegion>[]
        : TextRegions.captured(element);
    final capture = flutter_test.captureImage(element);

    return flutter_test.TestWidgetsFlutterBinding.instance.runAsync<String?>(
      () => isUpdate
          ? _updateCapture(capture, golden, comparator)
          : _compareCapture(capture, golden, comparator, textRegions),
    );
  }

  /// Writes the image of [capture] as [golden]; a failure is the message.
  static Future<String?> _updateCapture(
    Future<ui.Image> capture,
    Uri golden,
    GleonGoldenComparator comparator,
  ) async {
    final image = await capture;
    try {
      final png = await image.toByteData(format: .png);
      if (png == null) return 'could not encode the screenshot.';
      await comparator.update(golden, Uint8List.sublistView(png));

      return null;
    } on flutter_test.TestFailure catch (error) {
      return error.message;
    } finally {
      image.dispose();
    }
  }

  /// Compares the image of [capture] as raw pixels; a failure is the message.
  static Future<String?> _compareCapture(
    Future<ui.Image> capture,
    Uri golden,
    GleonGoldenComparator comparator,
    List<PixelRegion> textRegions,
  ) async {
    final image = await capture;
    try {
      final pixels = await image.toByteData(format: .rawStraightRgba);
      if (pixels == null) return 'could not read the pixels of the screenshot.';
      comparator.compareRaw(
        golden,
        Uint8List.sublistView(pixels),
        width: image.width,
        height: image.height,
        textRegions: textRegions,
      );

      return null;
    } on flutter_test.TestFailure catch (error) {
      return error.message;
    } finally {
      image.dispose();
    }
  }
}

/// One match's hold on `goldenFileComparator`: matches take turns, and each
/// turn puts back the comparator it found.
final class _Turn {
  /// Takes the turn of the current comparator.
  factory _Turn.take() => _current = _Turn._(flutter_test.goldenFileComparator);

  _Turn._(this.original);

  /// The comparator before this turn.
  final flutter_test.GoldenFileComparator original;

  /// The comparator this turn installed, once it did.
  GleonGoldenComparator? installed;

  /// The turn of the match currently holding `goldenFileComparator`, if any.
  static _Turn? _current;

  final _done = Completer<void>();

  /// Completes when the turn finishes.
  Future<void> get done => _done.future;

  /// Puts back the comparator [turn] found, unless something else replaced
  /// the one it installed since, and wakes the matches waiting for it; a
  /// second call is a no-op.
  static void finish(_Turn turn) {
    if (turn.installed case final installed?
        when identical(flutter_test.goldenFileComparator, installed)) {
      flutter_test.goldenFileComparator = turn.original;
    }
    if (identical(_current, turn)) _current = null;
    if (!turn._done.isCompleted) turn._done.complete();
  }
}
