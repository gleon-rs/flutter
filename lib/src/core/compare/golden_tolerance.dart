// Descriptions use "≤", "≥" and "±": they read better than ASCII in failures.
// ignore_for_file: avoid-non-ascii-symbols

import 'package:meta/meta.dart';

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

  /// Throws an [ArgumentError] for out-of-range values.
  void validate();

  /// The `Tolerance` JSON of `gleon-model` (`{"kind": "ssim", ...}`), used
  /// for the native `gleon_compare` options and in case reports.
  Map<String, Object> toNativeJson();

  /// The thresholds as shown in matcher descriptions and failure messages
  /// (`ssim ≥ 0.800, color ±8`). One exhaustive switch, so a new variant
  /// cannot fall back to `Instance of ...`.
  @override
  String toString() => switch (this) {
    ExactTolerance() => 'exact',
    PixelTolerance(:final maxDiffRatio) =>
      'pixel \u2264 ${(maxDiffRatio * 100).toStringAsFixed(2)}%',
    SsimTolerance(:final colorTolerance, :final minSimilarity) =>
      'ssim \u2265 ${_exact(minSimilarity, 3)}, '
          'color \u00b1${_exact(colorTolerance, 0)}',
  };

  /// Parses a `gleon-model` `Tolerance` (as resolved from `.gleon/gleon.yaml`)
  /// with patterns, or returns null for another shape.
  static GoldenTolerance? fromNativeJson(Object? json) => switch (json) {
    {'kind': 'exact'} => const .exact(),
    {'kind': 'pixel', 'max_diff_ratio': final num maxDiffRatio} => .pixel(
      maxDiffRatio: maxDiffRatio.toDouble(),
    ),
    {
      'color_tolerance': final num colorTolerance,
      'kind': 'ssim',
      'min_similarity': final num minSimilarity,
    } =>
      .ssim(
        minSimilarity: minSimilarity.toDouble(),
        colorTolerance: colorTolerance.toDouble(),
      ),
    _ => null,
  };

  /// [value] with [digits] decimals, or in full when rounding would misstate
  /// it (a message must never show a different threshold than the one used).
  static String _exact(double value, int digits) {
    final fixed = value.toStringAsFixed(digits);

    return double.parse(fixed) == value ? fixed : value.toString();
  }

  static void _checkRatio(double value, String name) {
    if (value.isNaN || value < 0 || value > 1) {
      throw ArgumentError.value(value, name, 'must be between 0.0 and 1.0');
    }
  }
}

/// Every pixel must be identical; see [GoldenTolerance.exact].
final class ExactTolerance extends GoldenTolerance {
  /// Creates the exact tolerance.
  const ExactTolerance();

  @override
  int get hashCode => 'exact'.hashCode;

  @override
  // ignore: no-empty-block, nothing to configure means nothing to reject.
  void validate() {}

  @override
  Map<String, Object> toNativeJson() => const {'kind': 'exact'};

  @override
  bool operator ==(Object other) => other is ExactTolerance;
}

/// A maximum fraction of differing pixels; see [GoldenTolerance.pixel].
final class PixelTolerance extends GoldenTolerance {
  /// Creates a pixel tolerance.
  const PixelTolerance({this.maxDiffRatio = 0.01});

  /// Maximum fraction (0.0–1.0) of differing pixels.
  final double maxDiffRatio;

  @override
  int get hashCode => Object.hash(PixelTolerance, maxDiffRatio);

  @override
  void validate() => GoldenTolerance._checkRatio(maxDiffRatio, 'maxDiffRatio');

  @override
  Map<String, Object> toNativeJson() => {
    'kind': 'pixel',
    'max_diff_ratio': maxDiffRatio,
  };

  @override
  bool operator ==(Object other) =>
      other is PixelTolerance && other.maxDiffRatio == maxDiffRatio;
}

/// Rendering-noise tolerant comparison; see [GoldenTolerance.ssim].
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
  void validate() {
    GoldenTolerance._checkRatio(minSimilarity, 'minSimilarity');
    if (!colorTolerance.isFinite ||
        colorTolerance < 0 ||
        colorTolerance > 255) {
      throw ArgumentError.value(
        colorTolerance,
        'colorTolerance',
        'must be between 0 and 255',
      );
    }
  }

  @override
  Map<String, Object> toNativeJson() => {
    'color_tolerance': colorTolerance,
    'kind': 'ssim',
    'min_similarity': minSimilarity,
  };

  @override
  bool operator ==(Object other) =>
      other is SsimTolerance &&
      other.minSimilarity == minSimilarity &&
      other.colorTolerance == colorTolerance;
}
