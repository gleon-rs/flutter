import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show AsyncCallback, visibleForTesting;
import 'package:flutter_test/flutter_test.dart' as flutter_test;

import '../core/compare/golden_tolerance.dart';
import '../core/compare/tolerances.dart';
import '../core/config/gleon_session.dart';
import 'gleon_file_comparator.dart';
import 'gleon_matches_golden_file.dart';
import 'ignore_regions.dart';

/// The type of alchemist's `GoldenFileExpectation`, spelled without
/// alchemist: the assertion that ends every alchemist golden test, given what
/// it captured (`actual`) and the path of its golden (`golden`).
typedef AlchemistGoldenExpectation = AsyncCallback Function(
  Object actual,
  Object golden,
);

/// An alchemist golden file expectation that compares with gleon's
/// `matchesGoldenFile`; assign it to alchemist's `goldenFileExpectationFn`
/// in `test/flutter_test_config.dart` (see the README's "Golden harnesses").
/// Call `loadAppFonts()` there first: alchemist loads the app's fonts again
/// before each golden test, and text keeps the faces loaded first, which
/// `loadAppFonts` aligns to lay text out alike on every OS.
///
/// Alchemist passes the root `Finder` of each golden test unless its text is
/// obscured, so gleon captures the raw pixels with the boxes of their text,
/// like its own matcher with a widget. With `obscureText` (alchemist's
/// default for CI goldens) it passes an image of blocked text instead, which
/// gleon cannot compare as text: a failure then says how to compare the real
/// text, unless [shouldHintObscuredText] is false.
///
/// The [tolerance], [ignoreRegions] and [textTolerance] apply to every
/// alchemist golden, like the parameters of `matchesGoldenFile`; null leaves
/// them to the golden's `.gleon/gleon.yaml` rule. The [ignoreRegions] are in
/// pixels of the capture (alchemist renders at a device pixel ratio of 1).
/// The `diffThreshold` of alchemist does not apply (a failure says so): use
/// a tolerance instead.
///
/// Throws an [ArgumentError] for the values `matchesGoldenFile` refuses.
// ignore: prefer-static-class, a factory of a closure, like matchesGoldenFile.
AlchemistGoldenExpectation gleonAlchemistExpectation({
  GoldenTolerance? tolerance,
  List<ui.Rect>? ignoreRegions,
  double? textTolerance,
  bool shouldHintObscuredText = true,
}) => AlchemistExpectation.create(
  tolerance: tolerance,
  ignoreRegions: ignoreRegions,
  textTolerance: textTolerance,
  shouldHintObscuredText: shouldHintObscuredText,
);

/// The implementation of [gleonAlchemistExpectation].
abstract final class AlchemistExpectation {
  /// Appended to failures of goldens with obscured text.
  static const obscuredTextHint =
      'gleon: alchemist obscured the text of this golden (blocks instead of '
      'glyphs), so gleon cannot compare it as text. To compare real text '
      "under its text tolerance, set `obscureText: false` in alchemist's "
      'goldens config (`CiGoldensConfig`, `PlatformGoldensConfig`) and record '
      'the goldens again; `shouldHintObscuredText: false` silences this hint.';

  /// Appended to failures while a `LocalFileComparator` subclass other than
  /// gleon's is installed ([comparator] names its type): alchemist installs
  /// one for a `diffThreshold` above 0, whose threshold gleon never applies.
  static String thresholdNote(Type comparator) =>
      'gleon: the threshold of the golden file comparator ($comparator, '
      "alchemist's `diffThreshold`) does not apply to gleon's comparison; "
      'set a gleon tolerance instead (`.gleon/gleon.yaml` or '
      '`gleonAlchemistExpectation(tolerance: ...)`).';

  /// [gleonAlchemistExpectation], comparing in [session] (null: the
  /// process's, see `FlutterSession.process`).
  @visibleForTesting
  static AlchemistGoldenExpectation create({
    GoldenTolerance? tolerance,
    List<ui.Rect>? ignoreRegions,
    double? textTolerance,
    bool shouldHintObscuredText = true,
    GleonSession? session,
  }) {
    // Refused here, in the config, rather than by the first golden test.
    if (tolerance != null) Tolerances.validate(tolerance);
    if (textTolerance != null) Tolerances.validateText(textTolerance);
    final masks = IgnoreRegions.toMasks(ignoreRegions ?? const []);

    return (actual, golden) => () async {
      try {
        await flutter_test.expectLater(
          actual,
          GleonMatchesGoldenFile(
            GleonMatchesGoldenFile.uriOf(golden),
            null,
            tolerance: tolerance,
            masks: masks,
            textTolerance: textTolerance,
            session: session,
          ),
        );
      } on flutter_test.TestFailure catch (error, stackTrace) {
        // Alchemist keeps its comparator installed while the expectation runs.
        final comparator = flutter_test.goldenFileComparator;
        final notes = [
          // Only a widget comes with the boxes of its text.
          if (shouldHintObscuredText && actual is! flutter_test.Finder)
            obscuredTextHint,
          if (comparator is flutter_test.LocalFileComparator &&
              comparator.runtimeType != flutter_test.LocalFileComparator &&
              comparator is! GleonFileComparator)
            thresholdNote(comparator.runtimeType),
        ];
        if (notes.isEmpty) rethrow;
        Error.throwWithStackTrace(
          flutter_test.TestFailure(
            [error.message, ...notes].nonNulls.join('\n'),
          ),
          stackTrace,
        );
      }
    };
  }
}
