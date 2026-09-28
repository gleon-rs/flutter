import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/native/native_metrics.dart';
import 'package:gleon/src/core/report/case_outcome.dart';
import 'package:gleon/src/core/report/console_line.dart';

void main() {
  test('ssim lines show the gates with their headroom', () {
    expect(
      ConsoleLine.format(
        goldenPath: 'test/goldens/swatch.png',
        outcome: .match,
        tolerance: const .ssim(),
        totalMilliseconds: 12.4,
        metrics: const SsimMetrics(
          minSsim: 0.931,
          meanSsim: 0.99,
          peakExcess: 5.2,
          changedPixels: 10,
          failingPixels: 0,
          similarityHeadroom: 0.131,
          colorHeadroom: 2.8,
        ),
      ),
      'gleon ✓ test/goldens/swatch.png  ssim 0.931 (≥0.800, +0.131)  '
      'color 5.2 (≤8, +2.8)  12 ms',
    );
  });

  test('pixel lines show the differing share', () {
    expect(
      ConsoleLine.format(
        goldenPath: 'a.png',
        outcome: .mismatch,
        tolerance: const .pixel(),
        totalMilliseconds: 3,
        metrics: const PixelMetrics(
          totalPixels: 100,
          diffPixels: 2,
          diffRatio: 0.02,
          headroom: -0.01,
        ),
      ),
      'gleon ✗ a.png  pixel 2.00% (2 px, ≤1.00%, -1.00%)  3 ms',
    );
  });

  test('outcomes without metrics say what happened', () {
    String line(CaseOutcome outcome, [String? message]) => ConsoleLine.format(
      goldenPath: 'a.png',
      outcome: outcome,
      tolerance: const .exact(),
      totalMilliseconds: 1,
      message: message,
    );

    expect(line(.identical), 'gleon = a.png  identical  1 ms');
    expect(line(.updated), 'gleon ↻ a.png  updated  1 ms');
    expect(line(.error, 'bad PNG'), 'gleon ! a.png  bad PNG  1 ms');
    expect(line(.dimensionMismatch), 'gleon ≠ a.png  dimension_mismatch  1 ms');
  });

  test('fractional tolerances are printed in full', () {
    final line = ConsoleLine.format(
      goldenPath: 'a.png',
      outcome: .match,
      tolerance: const .ssim(colorTolerance: 7.5),
      totalMilliseconds: 1,
      metrics: const SsimMetrics(
        minSsim: 1,
        meanSsim: 1,
        peakExcess: 1,
        changedPixels: 1,
        failingPixels: 0,
        similarityHeadroom: 0.2,
        colorHeadroom: 6.5,
      ),
    );

    expect(line, contains('color 1.0 (≤7.5, +6.5)'));
  });
}
