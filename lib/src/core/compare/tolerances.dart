// Descriptions use "≤": it reads better than ASCII in failures.
// ignore_for_file: avoid-non-ascii-symbols

import 'golden_tolerance.dart';

/// Validation and texts of [GoldenTolerance]s and text tolerances: package
/// internals, kept out of the public type.
abstract final class Tolerances {
  /// The most decimals a threshold is shown with, as in the native engine's
  /// messages: enough for any threshold a developer sets.
  static const _maxDecimals = 4;

  /// The digits of a fraction up to its trailing zeros.
  static final _withoutTrailingZeros = RegExp(r'^\d*?(?=0*$)');

  /// Throws an [ArgumentError] naming the parameter of [tolerance] that is
  /// out of range.
  static void validate(GoldenTolerance tolerance) {
    switch (tolerance) {
      case PixelTolerance(:final maxDiffRatio):
        _checkRatio(maxDiffRatio, 'maxDiffRatio');

      case SsimTolerance(:final colorTolerance, :final minSimilarity):
        _checkRatio(minSimilarity, 'minSimilarity');
        _checkColor(colorTolerance);

      // Nothing to configure, nothing to reject.
      case ExactTolerance():
    }
  }

  /// Throws an [ArgumentError] unless [share], a `textTolerance`, is between
  /// 0.0 and 1.0.
  static void validateText(double share) => _checkRatio(share, 'textTolerance');

  /// A `textTolerance` as in failure messages: `text ignored` at 1 (text
  /// never fails), else e.g. `text ≤ 10.00% per tile`.
  static String describeText(double share) =>
      share >= 1 ? 'text ignored' : 'text ≤ ${percent(share)}% per tile';

  /// [value] rounded to [max] decimals, trailing zeros dropped down to [min]
  /// (`8`, `7.5`, `0.800`); `-0.0` shows as `0`.
  static String decimal(double value, int min, {int max = _maxDecimals}) {
    final fixed = (value == 0 ? 0.0 : value).toStringAsFixed(max);
    if (fixed.split('.') case [final whole, final fraction]) {
      final significant =
          _withoutTrailingZeros.stringMatch(fraction) ?? fraction;
      final kept = significant.padRight(min, '0');

      return kept.isEmpty ? whole : '$whole.$kept';
    }

    return fixed; // `NaN`.
  }

  /// [ratio] as a percentage with 2 to 4 decimals (`1.00`, `0.0167`); a
  /// positive ratio too small to show is `<0.0001`, never a misleading `0.00`.
  static String percent(double ratio) {
    final text = decimal(ratio * 100, 2);

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
