import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart' as flutter_test;

import '../core/compare/golden_tolerance.dart';
import 'gleon_matches_golden_file.dart';
import 'ignore_regions.dart';

/// Drop-in replacement for Flutter's `matchesGoldenFile`.
///
/// Accepts everything the SDK version accepts — a [String] or [Uri] `key`, an
/// optional `version`, and a `Finder`, `ui.Image`, `Future<ui.Image>`,
/// `List<int>` or `Future<List<int>>` as the actual value — and behaves the
/// same by default (exact comparison, goldens resolved relative to the test
/// file, `--update-goldens` rewrites them).
///
/// Additional parameters:
/// * [tolerance]: how much the image may deviate, see [GoldenTolerance]
///   (exact when omitted).
/// * [ignoreRegions]: regions excluded from the comparison, in pixels of the
///   golden PNG (measure them on the golden file).
///
/// Throws an [ArgumentError] for out-of-range tolerance values and invalid
/// regions, and for a `key` that is neither a [String] nor a [Uri].
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
  tolerance?.validate();

  return GleonMatchesGoldenFile(
    uri,
    version,
    tolerance: tolerance,
    masks: IgnoreRegions.toMasks(ignoreRegions ?? const []),
  );
}
