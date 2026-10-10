import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/golden_tolerance.dart';
import 'package:gleon/src/core/compare/tolerances.dart';

import '../../../helpers/value_semantics.dart';

void main() {
  test('defaults match the documented values', () {
    expect(const GoldenTolerance.pixel(), const PixelTolerance());
    expect(const PixelTolerance().maxDiffRatio, 0.01);
    expect(const PixelTolerance().channelTolerance, 0);
    expect(const PixelTolerance().antiAlias, isFalse);
    expect(const PixelTolerance().edgeThreshold, 0);
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
      'pixel <0.0001%',
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

  test('pixel options are described like the engine does, when on', () {
    const options = GoldenTolerance.pixel(
      channelTolerance: 4,
      antiAlias: true,
      edgeThreshold: 64,
    );
    expect(
      '$options',
      'pixel ≤ 1.00%, ±4 per channel, aa ignored, edges >64 ignored',
    );
    expect(
      '${const GoldenTolerance.pixel(maxDiffRatio: 0, antiAlias: true)}',
      'pixel ≤ 0.00%, aa ignored',
    );
    expect(
      '${const GoldenTolerance.pixel(edgeThreshold: 255)}',
      'pixel ≤ 1.00%',
      reason: '255 hides nothing',
    );
  });

  test('text tolerances are described per tile', () {
    expect(Tolerances.describeText(1), 'text ignored');
    expect(Tolerances.describeText(0.0625), 'text ≤ 6.25% per tile');
    expect(Tolerances.describeText(0), 'text ≤ 0.00% per tile');
    expect(Tolerances.describeText(1e-9), 'text <0.0001% per tile');
  });

  test('out-of-range values are rejected by name', () {
    Matcher rejects(String name) => throwsA(
      isA<ArgumentError>().having((error) => error.name, 'name', name),
    );

    expect(() => Tolerances.validate(const .exact()), returnsNormally);
    expect(
      () => Tolerances.validate(const .pixel(maxDiffRatio: 1)),
      returnsNormally,
    );
    expect(
      () => Tolerances.validate(const .pixel(maxDiffRatio: 1.5)),
      rejects('maxDiffRatio'),
    );
    expect(
      () => Tolerances.validate(const .ssim(minSimilarity: -1)),
      rejects('minSimilarity'),
    );
    expect(
      () => Tolerances.validate(const .ssim(colorTolerance: .infinity)),
      rejects('colorTolerance'),
    );
    for (final tolerance in const [
      PixelTolerance(edgeThreshold: 255),
      PixelTolerance(channelTolerance: 255),
    ]) {
      expect(() => Tolerances.validate(tolerance), returnsNormally);
    }
    for (final byte in [-1, 256]) {
      expect(
        () => Tolerances.validate(PixelTolerance(channelTolerance: byte)),
        rejects('channelTolerance'),
      );
      expect(
        () => Tolerances.validate(PixelTolerance(edgeThreshold: byte)),
        rejects('edgeThreshold'),
      );
    }
    expect(() => Tolerances.validateText(0.5), returnsNormally);
    expect(() => Tolerances.validateText(.nan), rejects('textTolerance'));
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
    for (final different in const <GoldenTolerance>[
      .pixel(channelTolerance: 1),
      .pixel(antiAlias: true),
      .pixel(edgeThreshold: 1),
    ]) {
      expectValueSemantics<GoldenTolerance>(
        const .pixel(),
        equal: const PixelTolerance(),
        different: different,
      );
    }
  });
}
