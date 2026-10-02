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

  /// Throws an [ArgumentError] for out-of-range values.
  void validate();

  /// The thresholds as shown in matcher descriptions and failure messages
  /// (`ssim ≥ 0.800, color ±8`). One exhaustive switch, so a new variant
  /// cannot fall back to `Instance of ...`.
  @override
  String toString() => switch (this) {
    ExactTolerance() => 'exact',
    PixelTolerance(:final maxDiffRatio) =>
      'pixel \u2264 ${_percent(maxDiffRatio)}%',
    SsimTolerance(:final colorTolerance, :final minSimilarity) =>
      'ssim \u2265 ${_decimal(minSimilarity, 3)}, '
          'color \u00b1${_decimal(colorTolerance, 0, max: 2)}',
  };

  /// The most decimals a threshold is shown with, as in the native engine's
  /// messages: enough for any threshold a developer sets.
  static const _maxDecimals = 4;

  /// [value] rounded to [max] decimals, trailing zeros dropped down to [min]
  /// (`8`, `7.5`, `0.800`); `-0.0` shows as `0`.
  static String _decimal(double value, int min, {int max = _maxDecimals}) {
    final fixed = (value == 0 ? 0.0 : value).toStringAsFixed(max);
    if (fixed.split('.') case [final whole, final fraction]) {
      final significant =
          _withoutTrailingZeros.stringMatch(fraction) ?? fraction;
      final kept = significant.padRight(min, '0');

      return kept.isEmpty ? whole : '$whole.$kept';
    }

    return fixed; // `NaN`.
  }

  /// The digits of a fraction up to its trailing zeros.
  static final _withoutTrailingZeros = RegExp(r'^\d*?(?=0*$)');

  /// [ratio] as a percentage with 2 to 4 decimals (`1.00`, `0.0167`); a
  /// positive ratio too small to show is `<0.0001`, never a misleading `0.00`.
  static String _percent(double ratio) {
    final text = _decimal(ratio * 100, 2);

    return ratio > 0 && double.parse(text) == 0 ? '<0.0001' : text;
  }

  static void _checkRatio(double value, String name) {
    if (value.isNaN || value < 0 || value > 1) {
      throw ArgumentError.value(value, name, 'must be between 0.0 and 1.0');
    }
  }

  static void _checkColor(double value) {
    if (!value.isFinite || value < 0 || value > 255) {
      throw ArgumentError.value(
        value,
        'colorTolerance',
        'must be between 0 and 255',
      );
    }
  }
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
  // ignore: no-empty-block, nothing to configure means nothing to reject.
  void validate() {}

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
  void validate() => GoldenTolerance._checkRatio(maxDiffRatio, 'maxDiffRatio');

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
  void validate() {
    GoldenTolerance._checkRatio(minSimilarity, 'minSimilarity');
    GoldenTolerance._checkColor(colorTolerance);
  }

  @override
  bool operator ==(Object other) =>
      other is SsimTolerance &&
      other.minSimilarity == minSimilarity &&
      other.colorTolerance == colorTolerance;
}

/// How much the text of a captured widget may deviate from its golden, while
/// everything else is compared under the [GoldenTolerance] (which must be
/// exact or pixel).
///
/// Operating systems rasterize the same glyphs a little differently (hinting,
/// anti-aliasing); with the app's real fonts (`loadAppFonts`) that is the
/// only difference between them, and only inside the boxes of text. There a
/// pixel counts as equal while no channel differs by more than
/// [colorTolerance], and the text passes while every 16x16 tile has at most
/// [maxDiffRatio] differing pixels: noise is spread thin, a changed word is
/// a dense cluster.
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
///         textTolerance: const TextTolerance(maxDiffRatio: 0.05),
///       ),
///     );
///   });
/// }
/// ```
@immutable
@pragma('vm:deeply-immutable')
// ignore: prefer-single-declaration-per-file, shares GoldenTolerance's format.
final class TextTolerance {
  /// Creates a text tolerance.
  const TextTolerance({this.colorTolerance = 24, this.maxDiffRatio = 0.1});

  /// Largest difference of any channel of a text pixel, in 8-bit units
  /// (0–255).
  final double colorTolerance;

  /// Largest fraction (0.0–1.0) of differing pixels in any 16x16 tile of
  /// text.
  final double maxDiffRatio;

  @override
  int get hashCode => Object.hash(TextTolerance, colorTolerance, maxDiffRatio);

  /// Throws an [ArgumentError] for out-of-range values.
  void validate() {
    GoldenTolerance._checkRatio(maxDiffRatio, 'maxDiffRatio');
    GoldenTolerance._checkColor(colorTolerance);
  }

  /// The thresholds as in failure messages (`text color ±24, ≤ 10.00% per
  /// tile`).
  @override
  String toString() =>
      'text color ±${GoldenTolerance._decimal(colorTolerance, 0, max: 2)}'
      ', ≤ ${GoldenTolerance._percent(maxDiffRatio)}% per tile';

  @override
  bool operator ==(Object other) =>
      other is TextTolerance &&
      other.colorTolerance == colorTolerance &&
      other.maxDiffRatio == maxDiffRatio;
}
