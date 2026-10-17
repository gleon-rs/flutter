import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/golden_tolerance.dart';
import 'package:gleon/src/core/compare/tolerances.dart';

import '../../../helpers/value_semantics.dart';

void main() {
  test('defaults match the documented values', () {
    expect(
      const GoldenTolerance.pixel(maxDiffRatio: 0.01),
      isA<PixelTolerance>()
          .having((pixel) => pixel.maxDiffRatio, 'maxDiffRatio', 0.01)
          .having((pixel) => pixel.channelTolerance, 'channelTolerance', 0)
          .having((pixel) => pixel.antiAlias, 'antiAlias', isFalse)
          .having((pixel) => pixel.edgeThreshold, 'edgeThreshold', 0),
    );
    expect(
      const GoldenTolerance.ssim(),
      isA<SsimTolerance>()
          .having((ssim) => ssim.minSimilarity, 'minSimilarity', 0.8)
          .having((ssim) => ssim.colorTolerance, 'colorTolerance', 8),
    );
  });

  test('descriptions name the thresholds', () {
    expect('${const GoldenTolerance.exact()}', 'exact');
    expect(
      '${const GoldenTolerance.pixel(maxDiffRatio: 0.01)}',
      'pixel ≤ 1.00%',
    );
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
      maxDiffRatio: 0.01,
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
    for (final tolerance in const <GoldenTolerance>[
      .pixel(maxDiffRatio: 0, edgeThreshold: 254),
      .pixel(maxDiffRatio: 0, channelTolerance: 254),
    ]) {
      expect(() => Tolerances.validate(tolerance), returnsNormally);
    }
    // 255 would compare nothing or hide nothing: invalid, like in `.gleon/gleon.yaml`.
    for (final byte in [-1, 255, 256]) {
      expect(
        () => Tolerances.validate(
          GoldenTolerance.pixel(maxDiffRatio: 0, channelTolerance: byte),
        ),
        rejects('channelTolerance'),
      );
      expect(
        () => Tolerances.validate(
          GoldenTolerance.pixel(maxDiffRatio: 0, edgeThreshold: byte),
        ),
        rejects('edgeThreshold'),
      );
    }
    expect(() => Tolerances.validateText(0.5), returnsNormally);
    expect(() => Tolerances.validateText(.nan), rejects('textTolerance'));
  });

  test('values compare by content', () {
    // Not `const`: equal values, not one canonical instance.
    // ignore: prefer_const_constructors, see above.
    final ssim = GoldenTolerance.ssim(minSimilarity: 0.9);
    expect(ssim, const GoldenTolerance.ssim(minSimilarity: 0.9));
    expect(
      ssim.hashCode,
      const GoldenTolerance.ssim(minSimilarity: 0.9).hashCode,
    );
    expect(
      const GoldenTolerance.pixel(maxDiffRatio: 0.01),
      isNot(const GoldenTolerance.pixel(maxDiffRatio: 0.02)),
    );
    // ignore: prefer_const_constructors, see above.
    expect(GoldenTolerance.exact(), const GoldenTolerance.exact());
  });

  test('every variant is a value', () {
    expectValueSemantics<GoldenTolerance>(
      const .exact(),
      // ignore: prefer_const_constructors, an equal value, not the instance.
      equal: GoldenTolerance.exact(),
      different: const .pixel(maxDiffRatio: 0),
    );
    expectValueSemantics<GoldenTolerance>(
      const .pixel(maxDiffRatio: 0.2),
      // ignore: prefer_const_constructors, an equal value, not the instance.
      equal: GoldenTolerance.pixel(maxDiffRatio: 0.2),
      different: const .pixel(maxDiffRatio: 0.3),
    );
    for (final different in const <GoldenTolerance>[
      .pixel(maxDiffRatio: 0.01, channelTolerance: 1),
      .pixel(maxDiffRatio: 0.01, antiAlias: true),
      .pixel(maxDiffRatio: 0.01, edgeThreshold: 1),
    ]) {
      expectValueSemantics<GoldenTolerance>(
        const .pixel(maxDiffRatio: 0.01),
        // ignore: prefer_const_constructors, an equal value, not the instance.
        equal: GoldenTolerance.pixel(maxDiffRatio: 0.01),
        different: different,
      );
    }
  });
}
