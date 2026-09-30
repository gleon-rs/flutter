import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/golden_tolerance.dart';

import '../../../helpers/value_semantics.dart';

void main() {
  test('defaults match the documented values', () {
    expect(const GoldenTolerance.pixel(), const PixelTolerance());
    expect(const PixelTolerance().maxDiffRatio, 0.01);
    expect(const SsimTolerance().minSimilarity, 0.8);
    expect(const SsimTolerance().colorTolerance, 8);
  });

  test('descriptions name the thresholds', () {
    expect('${const GoldenTolerance.exact()}', 'exact');
    expect('${const GoldenTolerance.pixel()}', 'pixel ≤ 1.00%');
    expect('${const GoldenTolerance.ssim()}', 'ssim ≥ 0.800, color ±8');
    const precise = GoldenTolerance.ssim(
      minSimilarity: 0.9995,
      colorTolerance: 7.5,
    );
    expect('$precise', 'ssim ≥ 0.9995, color ±7.5');
    expect(
      '${const GoldenTolerance.ssim(minSimilarity: 0.99995)}',
      startsWith('ssim ≥ 1.000,'),
      reason: 'four decimals are what a developer acts on',
    );
    expect(
      '${const GoldenTolerance.pixel(maxDiffRatio: 0.07)}',
      'pixel ≤ 7.00%',
      reason: 'rounding hides the floating point error of 0.07 * 100',
    );
    expect(
      '${const GoldenTolerance.pixel(maxDiffRatio: 1)}',
      'pixel ≤ 100.00%',
    );
    expect(
      '${const GoldenTolerance.pixel(maxDiffRatio: 0.00001)}',
      'pixel ≤ 0.001%',
    );
    expect(
      '${const GoldenTolerance.pixel(maxDiffRatio: 1e-9)}',
      'pixel ≤ <0.0001%',
      reason: 'a positive threshold never reads as zero',
    );
    expect(
      // ignore: prefer_int_literals, only a double literal is negative zero.
      '${const GoldenTolerance.pixel(maxDiffRatio: -0.0)}',
      'pixel ≤ 0.00%',
    );
    expect(
      '${const GoldenTolerance.pixel(maxDiffRatio: .nan)}',
      'pixel ≤ NaN%',
    );
  });

  test('values compare by content', () {
    expect(
      const GoldenTolerance.ssim(minSimilarity: 0.9),
      const SsimTolerance(minSimilarity: 0.9),
    );
    expect(
      const GoldenTolerance.ssim(minSimilarity: 0.9).hashCode,
      const SsimTolerance(minSimilarity: 0.9).hashCode,
    );
    expect(
      const GoldenTolerance.pixel(),
      isNot(const GoldenTolerance.pixel(maxDiffRatio: 0.02)),
    );
    expect(const GoldenTolerance.exact(), const ExactTolerance());
  });

  test('every variant is a value', () {
    expectValueSemantics<GoldenTolerance>(
      const .exact(),
      equal: const ExactTolerance(),
      different: const .pixel(maxDiffRatio: 0),
    );
    expectValueSemantics<GoldenTolerance>(
      const .pixel(maxDiffRatio: 0.2),
      equal: const PixelTolerance(maxDiffRatio: 0.2),
      different: const .pixel(maxDiffRatio: 0.3),
    );
  });
}
