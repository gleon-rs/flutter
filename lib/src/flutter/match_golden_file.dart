import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart' as flutter_test;

import '../core/compare/golden_tolerance.dart';
import '../core/compare/tolerances.dart';
import 'gleon_matches_golden_file.dart';
import 'ignore_regions.dart';

/// Drop-in replacement for Flutter's `matchesGoldenFile`.
///
/// Accepts everything the SDK version accepts — a [String] or [Uri] `key`, an
/// optional `version`, and a `Finder`, `ui.Image`, `Future<ui.Image>`,
/// `List<int>` or `Future<List<int>>` as the actual value — and behaves the
/// same by default (exact comparison, goldens resolved relative to the test
/// file, `--update-goldens` rewrites them); goldens of several platforms:
/// see the README's "Real text".
///
/// Additional parameters:
/// * [tolerance]: how much the image may deviate, see [GoldenTolerance]
///   (exact when omitted).
/// * [ignoreRegions]: regions excluded from the comparison, in pixels of the
///   golden PNG (measure them on the golden file).
/// * [textTolerance]: how much the text of a widget (a `Finder`) may differ,
///   while everything else is compared under [tolerance] (under `ssim` the
///   text is left out of both of its gates): the largest share (0.0–1.0) of
///   differing pixels in any 16x16 tile of text. Null uses the `text_tolerance` of the golden's `.gleon/gleon.yaml`
///   rule, else the golden's default (see the README's "Real text"). A
///   value set here always applies (1 turns text comparison off). Byte and
///   image inputs have no text boxes: their text is compared like every
///   other pixel.
///
/// Throws an [ArgumentError] for out-of-range tolerance values, invalid
/// regions, and a `key` that is neither a [String] nor a [Uri].
///
/// ```dart
/// import "package:flutter/widgets.dart";
/// import "package:gleon/gleon.dart";
///
/// void main() {
///   testWidgets("card", (tester) async {
///     await tester.pumpWidget(const Placeholder());
///     await expectLater(
///       find.byType(Placeholder),
///       matchesGoldenFile("goldens/card.png", tolerance: const .ssim()),
///     );
///   });
/// }
/// ```
// ignore: prefer-static-class, a drop-in for flutter_test's top-level function.
flutter_test.MatchesGoldenFile matchesGoldenFile(
  Object key, {
  int? version,
  GoldenTolerance? tolerance,
  List<Rect>? ignoreRegions,
  double? textTolerance,
}) {
  final uri = switch (key) {
    Uri() => key,
    String() => Uri.parse(key),
    _ => throw ArgumentError.value(
      key,
      'key',
      'Unexpected type for golden file: ${key.runtimeType}',
    ),
  };
  if (tolerance != null) Tolerances.validate(tolerance);
  if (textTolerance != null) Tolerances.validateText(textTolerance);

  return GleonMatchesGoldenFile(
    uri,
    version,
    tolerance: tolerance,
    masks: IgnoreRegions.toMasks(ignoreRegions ?? const []),
    textTolerance: textTolerance,
  );
}
