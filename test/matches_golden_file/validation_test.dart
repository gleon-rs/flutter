import 'dart:ui';

import 'package:gleon/gleon.dart';

import '../helpers/swatch.dart';

Matcher _throwsInvalid(String name, String message) => throwsA(
  isA<ArgumentError>()
      .having((error) => error.name, 'argument', name)
      .having((error) => error.message, 'reason', message),
);

void main() {
  test('rejects out-of-range pixel ratios', () {
    for (final ratio in [-0.1, 1.5, double.nan]) {
      expect(
        () => matchesGoldenFile(
          Swatch.golden,
          tolerance: .pixel(maxDiffRatio: ratio),
        ),
        _throwsInvalid('maxDiffRatio', 'must be between 0.0 and 1.0'),
        reason: '$ratio',
      );
    }
  });

  test('rejects out-of-range SSIM settings', () {
    expect(
      () => matchesGoldenFile(
        Swatch.golden,
        tolerance: const .ssim(minSimilarity: 2),
      ),
      _throwsInvalid('minSimilarity', 'must be between 0.0 and 1.0'),
    );
    for (final tolerance in [-1.0, 256.0, double.infinity, double.nan]) {
      expect(
        () => matchesGoldenFile(
          Swatch.golden,
          tolerance: .ssim(colorTolerance: tolerance),
        ),
        _throwsInvalid('colorTolerance', 'must be between 0 and 255'),
        reason: '$tolerance',
      );
    }
  });

  test('accepts the whole valid range', () {
    for (final tolerance in const <GoldenTolerance>[
      .exact(),
      .pixel(maxDiffRatio: 0),
      .pixel(maxDiffRatio: 1),
      .ssim(minSimilarity: 0, colorTolerance: 0),
      .ssim(minSimilarity: 1, colorTolerance: 255),
    ]) {
      expect(
        () => matchesGoldenFile(Swatch.golden, tolerance: tolerance),
        returnsNormally,
        reason: '$tolerance',
      );
    }
  });

  test('rejects invalid ignore regions', () {
    for (final region in const <Rect>[
      .fromLTWH(-1, 0, 5, 5),
      .fromLTWH(0, -1, 5, 5),
      .fromLTWH(0, 0, 0, 5),
      .fromLTRB(0, 0, .infinity, 5),
    ]) {
      expect(
        () => matchesGoldenFile(Swatch.golden, ignoreRegions: [region]),
        _throwsInvalid(
          'ignoreRegions',
          'must be finite, non-empty and have non-negative coordinates',
        ),
        reason: '$region',
      );
    }
  });

  test('rejects unsupported key types like Flutter', () {
    expect(() => matchesGoldenFile(42), throwsArgumentError);
  });

  test('the matcher description names the tolerance', () {
    String describe(Matcher matcher) =>
        '${StringDescription()..addDescriptionOf(matcher)}';

    expect(
      describe(matchesGoldenFile('goldens/a.png')),
      endsWith('(gleon default tolerance)'),
    );
    expect(
      describe(matchesGoldenFile('goldens/a.png', tolerance: const .ssim())),
      endsWith('(gleon ssim ≥ 0.800, color ±8)'),
    );
  });
}
