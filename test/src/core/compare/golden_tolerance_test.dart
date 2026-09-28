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

  test('every variant speaks the gleon-model Tolerance format', () {
    expect(const GoldenTolerance.exact().toNativeJson(), {'kind': 'exact'});
    expect(const GoldenTolerance.pixel(maxDiffRatio: 0.2).toNativeJson(), {
      'kind': 'pixel',
      'max_diff_ratio': 0.2,
    });
    expect(
      const GoldenTolerance.ssim(
        minSimilarity: 0.9,
        colorTolerance: 4,
      ).toNativeJson(),
      {'color_tolerance': 4.0, 'kind': 'ssim', 'min_similarity': 0.9},
    );
  });

  test('resolved tolerances round-trip', () {
    for (final tolerance in const <GoldenTolerance>[
      .exact(),
      .pixel(maxDiffRatio: 0.2),
      .ssim(minSimilarity: 0.6, colorTolerance: 64),
    ]) {
      expect(
        GoldenTolerance.fromNativeJson(tolerance.toNativeJson()),
        tolerance,
      );
    }
    expect(
      GoldenTolerance.fromNativeJson(const {
        'color_tolerance': 64,
        'kind': 'ssim',
        'min_similarity': 1,
      }),
      const GoldenTolerance.ssim(minSimilarity: 1, colorTolerance: 64),
      reason: 'integral JSON numbers are accepted',
    );
    expect(GoldenTolerance.fromNativeJson(const {'kind': 'fuzzy'}), isNull);
    expect(GoldenTolerance.fromNativeJson(const {'kind': 'pixel'}), isNull);
  });

  test('descriptions name the thresholds', () {
    expect('${const GoldenTolerance.exact()}', 'exact');
    expect('${const GoldenTolerance.pixel()}', 'pixel ≤ 1.00%');
    expect('${const GoldenTolerance.ssim()}', 'ssim ≥ 0.800, color ±8');
    const precise = GoldenTolerance.ssim(
      minSimilarity: 0.9995,
      colorTolerance: 7.5,
    );
    expect(
      '$precise',
      'ssim ≥ 0.9995, color ±7.5',
      reason: 'rounding must never misstate the threshold',
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
