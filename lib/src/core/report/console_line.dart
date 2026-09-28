// "≥", "≤" read better than ASCII in console lines.
// ignore_for_file: avoid-non-ascii-symbols

import '../compare/golden_tolerance.dart';
import '../native/native_metrics.dart';
import 'case_outcome.dart';

/// The one-line console summary of a golden comparison, e.g.
/// `gleon ✓ test/goldens/swatch.png  ssim 0.931 (≥0.800, +0.131)  color 5.2
/// (≤8, +2.8)  12 ms`.
abstract final class ConsoleLine {
  /// Formats the line for [goldenPath] (relative to the workspace root).
  static String format({
    required String goldenPath,
    required CaseOutcome outcome,
    required GoldenTolerance tolerance,
    required double totalMilliseconds,
    NativeMetrics? metrics,
    String? message,
  }) {
    final detail = switch ((metrics, tolerance)) {
      (
        SsimMetrics(
          :final colorHeadroom,
          :final minSsim,
          :final peakExcess,
          :final similarityHeadroom,
        ),
        SsimTolerance(:final colorTolerance, :final minSimilarity),
      ) =>
        'ssim ${minSsim.toStringAsFixed(3)} '
            '(≥${GoldenTolerance.exactDecimal(minSimilarity, 3)}, '
            '${_signed(similarityHeadroom, 3)})  '
            'color ${peakExcess.toStringAsFixed(1)} '
            '(≤${GoldenTolerance.exactDecimal(colorTolerance, 0)}, '
            '${_signed(colorHeadroom, 1)})',
      (final PixelMetrics pixel, PixelTolerance(:final maxDiffRatio)) => _pixel(
        pixel,
        maxDiffRatio,
      ),
      (final PixelMetrics pixel, ExactTolerance()) => _pixel(pixel, 0),
      _ => _withoutMetrics(outcome, message),
    };

    return 'gleon ${outcome.symbol} $goldenPath  $detail  '
        '${totalMilliseconds.round()} ms';
  }

  static String _withoutMetrics(CaseOutcome outcome, String? message) =>
      switch (outcome) {
        .identical => 'identical',
        .updated => 'updated',
        .match ||
        .mismatch ||
        .dimensionMismatch ||
        .error => message ?? outcome.json,
      };

  static String _signed(double value, int digits) => value.isNegative
      ? value.toStringAsFixed(digits)
      : '+${value.toStringAsFixed(digits)}';

  /// The measured share against [maxDiffRatio], the threshold of the
  /// tolerance itself.
  static String _pixel(PixelMetrics metrics, double maxDiffRatio) {
    final PixelMetrics(:diffPixels, :diffRatio, :headroom) = metrics;

    return 'pixel ${(diffRatio * 100).toStringAsFixed(2)}% ($diffPixels px, '
        '≤${GoldenTolerance.exactDecimal(maxDiffRatio, 2, shift: 2)}%, '
        '${_signed(headroom * 100, 2)}%)';
  }
}
