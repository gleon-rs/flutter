// Descriptions use "≤", "≥" and "±": they read better than ASCII in failures.
// ignore_for_file: avoid-non-ascii-symbols

import 'package:meta/meta.dart';

import 'tolerances.dart';

/// How much a test image may deviate from its golden.
///
/// Without a tolerance, `matchesGoldenFile` compares exactly, like Flutter.
/// Values are validated when a matcher is created: out-of-range values throw
/// an [ArgumentError]. Dot shorthands keep call sites short:
///
/// ```dart
/// import "package:gleon/gleon.dart";
///
/// void main() {
///   testWidgets("card", (tester) async {
///     await expectLater(
///       find.text("Card"),
///       matchesGoldenFile(
///         "goldens/card.png",
///         tolerance: const .ssim(minSimilarity: 0.9),
///       ),
///     );
///   });
/// }
/// ```
@immutable
@pragma('vm:deeply-immutable')
sealed class GoldenTolerance {
  /// Base constructor of the variants.
  const GoldenTolerance();

  /// Every pixel must be identical. Same behavior as Flutter's default
  /// `matchesGoldenFile`, and the default of this package.
  const factory exact() = ExactTolerance;

  /// Passes when at most [maxDiffRatio] (0.0–1.0) of the pixels differ.
  ///
  /// The options, all off by default and never applied to text, let some
  /// differing pixels count as equal: rendering noise of shapes (GPU drift,
  /// anti-aliasing, sub-pixel geometry), not a substitute for
  /// [GoldenTolerance.ssim] or per-platform goldens:
  ///
  /// * `channelTolerance` (0–254): no RGBA byte differs by more than this;
  /// * `antiAlias`: the pixel looks anti-aliased in either image (the
  ///   detection of pixelmatch);
  /// * `edgeThreshold` (0–254): the Sobel gradient of the golden's luma there
  ///   exceeds this. Every change on edges passes too (a missing glyph or
  ///   small icon, a 1px move); the lower the value, the more pixels are
  ///   edges.
  const factory pixel({
    double maxDiffRatio,
    int channelTolerance,
    bool antiAlias,
    int edgeThreshold,
  }) = PixelTolerance;

  /// Tolerates rendering noise (anti-aliasing, sub-pixel geometry, glyph
  /// weight, imperceptible color drift) while catching changed, added or
  /// removed content, color and alpha changes and blur.
  ///
  /// Two gates must pass: every local neighborhood keeps an SSIM of at least
  /// [minSimilarity] (0.0–1.0, at half resolution), and no patch of pixels
  /// deviates from its local 3x3 envelope by more than [colorTolerance]
  /// (8-bit channel units, 0–255).
  ///
  /// Known limits: glyphs moved by half a pixel or more (typical of different
  /// operating systems' font engines) fail, so keep per-platform goldens;
  /// low-contrast color changes of one-pixel lines can pass.
  const factory ssim({double minSimilarity, double colorTolerance}) =
      SsimTolerance;

  /// The thresholds as shown in matcher descriptions and failure messages
  /// (`ssim ≥ 0.800, color ±8`). One exhaustive switch, so a new variant
  /// cannot fall back to `Instance of ...`.
  @override
  String toString() => switch (this) {
    ExactTolerance() => 'exact',
    final PixelTolerance pixel => Tolerances.describePixel(pixel),
    SsimTolerance(:final colorTolerance, :final minSimilarity) =>
      'ssim \u2265 ${Tolerances.decimal(minSimilarity, 3)}, '
          'color \u00b1${Tolerances.decimal(colorTolerance, 0, max: 2)}',
  };
}

/// Every pixel must be identical; see [GoldenTolerance.exact].
@immutable
@pragma('vm:deeply-immutable')
final class ExactTolerance extends GoldenTolerance {
  /// Creates the exact tolerance.
  const ExactTolerance();

  @override
  int get hashCode => 'exact'.hashCode;

  @override
  bool operator ==(Object other) => other is ExactTolerance;
}

/// A maximum fraction of differing pixels; see [GoldenTolerance.pixel].
@immutable
@pragma('vm:deeply-immutable')
final class PixelTolerance extends GoldenTolerance {
  /// Creates a pixel tolerance.
  const PixelTolerance({
    this.maxDiffRatio = 0.01,
    this.channelTolerance = 0,
    this.antiAlias = false,
    this.edgeThreshold = 0,
  });

  /// Maximum fraction (0.0–1.0) of differing pixels.
  final double maxDiffRatio;

  /// A differing pixel outside text counts as equal when no RGBA byte
  /// differs by more than this (0–254; 0: off).
  final int channelTolerance;

  /// Whether a differing pixel outside text that looks anti-aliased in
  /// either image counts as equal.
  // ignore: prefer-boolean-prefixes, the name of the engine's `anti_alias` key.
  final bool antiAlias;

  /// A differing pixel outside text counts as equal when the Sobel gradient
  /// of the golden's luma there exceeds this (0–254; 0: off). Unnormalized
  /// like Skia Gold's: a sharp step of 16 luma levels gives 64.
  final int edgeThreshold;

  @override
  int get hashCode => Object.hash(
    PixelTolerance,
    maxDiffRatio,
    channelTolerance,
    antiAlias,
    edgeThreshold,
  );

  @override
  bool operator ==(Object other) =>
      other is PixelTolerance &&
      other.maxDiffRatio == maxDiffRatio &&
      other.channelTolerance == channelTolerance &&
      other.antiAlias == antiAlias &&
      other.edgeThreshold == edgeThreshold;
}

/// Rendering-noise tolerant comparison; see [GoldenTolerance.ssim].
@immutable
@pragma('vm:deeply-immutable')
final class SsimTolerance extends GoldenTolerance {
  /// Creates an SSIM tolerance.
  const SsimTolerance({this.minSimilarity = 0.8, this.colorTolerance = 8});

  /// Minimum local SSIM (0.0–1.0).
  final double minSimilarity;

  /// Tolerated deviation beyond the local envelope, in 8-bit channel units
  /// (0–255).
  final double colorTolerance;

  @override
  int get hashCode => Object.hash(SsimTolerance, minSimilarity, colorTolerance);

  @override
  bool operator ==(Object other) =>
      other is SsimTolerance &&
      other.minSimilarity == minSimilarity &&
      other.colorTolerance == colorTolerance;
}
