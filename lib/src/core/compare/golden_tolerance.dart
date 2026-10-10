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
  const factory pixel({double maxDiffRatio}) = PixelTolerance;

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
    PixelTolerance(:final maxDiffRatio) =>
      'pixel ${Tolerances.atMost(maxDiffRatio)}',
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
  const PixelTolerance({this.maxDiffRatio = 0.01});

  /// Maximum fraction (0.0–1.0) of differing pixels.
  final double maxDiffRatio;

  @override
  int get hashCode => Object.hash(PixelTolerance, maxDiffRatio);

  @override
  bool operator ==(Object other) =>
      other is PixelTolerance && other.maxDiffRatio == maxDiffRatio;
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
