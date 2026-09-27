import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart' as flutter_test;

import 'comparator.dart';
import 'config.dart';

/// Drop-in replacement for Flutter's `matchesGoldenFile`.
///
/// Accepts everything the SDK version accepts — a [String] or [Uri] `key`, an
/// optional `version`, and a `Finder`, `ui.Image`, `Future<ui.Image>`,
/// `List<int>` or `Future<List<int>>` as the actual value — and behaves the
/// same by default (exact comparison, goldens resolved relative to the test
/// file, `--update-goldens` rewrites them).
///
/// Additional parameters (falling back to [gleonGoldenDefaults]):
/// * [mode]: [GoldenMode.exact] (default), [GoldenMode.pixel] or
///   [GoldenMode.ssim].
/// * [threshold]: maximum fraction of differing pixels for
///   [GoldenMode.pixel].
/// * [minSimilarity]: minimum local SSIM for [GoldenMode.ssim] (default 0.8).
/// * [colorTolerance]: tolerated deviation beyond the local envelope, in
///   8-bit channel units, for [GoldenMode.ssim] (default 8).
/// * [ignoreRegions]: regions excluded from the comparison, in pixels of the
///   golden PNG (measure them on the golden file).
///
/// ```dart
/// await expectLater(
///   find.byType(MyWidget),
///   matchesGoldenFile('goldens/my_widget.png', mode: GoldenMode.ssim),
/// );
/// ```
flutter_test.MatchesGoldenFile matchesGoldenFile(
  Object key, {
  int? version,
  GoldenMode? mode,
  double? threshold,
  double? minSimilarity,
  double? colorTolerance,
  List<Rect>? ignoreRegions,
}) {
  final uri = switch (key) {
    Uri() => key,
    String() => Uri.parse(key),
    _ => throw ArgumentError(
      'Unexpected type for golden file: ${key.runtimeType}',
    ),
  };
  return GleonMatchesGoldenFile(
    uri,
    version,
    ResolvedGoldenOptions.resolve(
      defaults: gleonGoldenDefaults,
      mode: mode,
      threshold: threshold,
      minSimilarity: minSimilarity,
      colorTolerance: colorTolerance,
      ignoreRegions: ignoreRegions,
    ),
  );
}

/// The matcher created by [matchesGoldenFile].
///
/// Reuses Flutter's own [flutter_test.MatchesGoldenFile] for capturing,
/// encoding, version handling and `--update-goldens`, and only swaps the
/// comparison backend for the duration of the match.
class GleonMatchesGoldenFile extends flutter_test.MatchesGoldenFile {
  /// Creates the matcher; prefer [matchesGoldenFile].
  GleonMatchesGoldenFile(super.key, super.version, this.options);

  /// Resolved comparison options.
  final ResolvedGoldenOptions options;

  @override
  Future<String?> matchAsync(dynamic item) async {
    final original = flutter_test.goldenFileComparator;
    flutter_test.goldenFileComparator = GleonGoldenComparator(
      original,
      options,
    );
    try {
      return await super.matchAsync(item);
    } finally {
      flutter_test.goldenFileComparator = original;
    }
  }

  @override
  flutter_test.Description describe(flutter_test.Description description) =>
      super.describe(description).add(' (gleon ${options.describe()})');
}
