// Descriptions use "≤", "≥" and "±": they read better than ASCII in failures.
// ignore_for_file: avoid-non-ascii-symbols

import 'dart:math' as math;

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
      'pixel \u2264 ${exactDecimal(maxDiffRatio, 2, shift: 2)}%',
    SsimTolerance(:final colorTolerance, :final minSimilarity) =>
      'ssim \u2265 ${exactDecimal(minSimilarity, 3)}, '
          'color \u00b1${exactDecimal(colorTolerance, 0)}',
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

  /// A threshold [value] with its decimal point moved [shift] places right
  /// (2 for a percentage) and [digits] decimals, or with more when fewer would
  /// misstate it: a message must never show a different threshold than the
  /// one used. Shared with the console line.
  ///
  /// The value itself is rounded and must parse back exactly; the point is
  /// then moved as text, since `value * 100` is not exact (`0.07 * 100` is
  /// `7.000000000000001`).
  @internal
  static String exactDecimal(double value, int digits, {int shift = 0}) {
    if (value >= 0) {
      for (
        int decimals = digits + shift;
        decimals <= _maxDecimals;
        decimals += 1
      ) {
        final fixed = value.toStringAsFixed(decimals);
        if (double.parse(fixed) == value) return _movePoint(fixed, shift);
      }
    }

    // NaN, negative, or too small for fixed notation.
    return '${value * math.pow(10, shift)}';
  }

  /// The most decimals `toStringAsFixed` accepts.
  static const _maxDecimals = 20;

  /// [fixed] (`0.0700`, at least [shift] decimals) with its point moved
  /// [shift] places right (`7.00`).
  static String _movePoint(String fixed, int shift) {
    final parts = RegExp('^(\\d+)\\.(\\d{$shift})(\\d*)\$')
        .firstMatch(fixed)
        ?.groups([1, 2, 3]);
    if (parts case [final whole?, final moved?, final rest?]) {
      // BigInt drops the leading zeros (`007` is `7`) at any length.
      final digits = BigInt.parse('$whole$moved');

      return rest.isEmpty ? '$digits' : '$digits.$rest';
    }

    return fixed; // No decimals to move (`8`).
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
