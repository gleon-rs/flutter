import 'dart:ui';

import 'package:gleon/gleon.dart';

import '../helpers/swatch.dart';

Matcher _throwsInvalid(String name, String message) => throwsA(
  isA<ArgumentError>()
      .having((error) => error.name, 'argument', name)
      .having((error) => error.message, 'reason', message),
);

const _ratio = 'must be between 0.0 and 1.0';
const _color = 'must be between 0 and 255';

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

  test('rejects out-of-range text tolerances', () {
    for (final (name, tolerance, message) in [
      ('maxDiffRatio', const TextTolerance(maxDiffRatio: -0.1), _ratio),
      ('maxDiffRatio', const TextTolerance(maxDiffRatio: .nan), _ratio),
      ('colorTolerance', const TextTolerance(colorTolerance: 256), _color),
      ('colorTolerance', const TextTolerance(colorTolerance: .nan), _color),
    ]) {
      expect(
        () => matchesGoldenFile(Swatch.golden, textTolerance: tolerance),
        _throwsInvalid(name, message),
        reason: '$tolerance',
      );
    }
  });

  test('a text tolerance needs an exact or pixel tolerance', () {
    expect(
      () => matchesGoldenFile(
        Swatch.golden,
        tolerance: const .ssim(),
        textTolerance: const TextTolerance(),
      ),
      _throwsInvalid(
        'textTolerance',
        'applies to exact and pixel tolerances, not ssim',
      ),
    );
    for (final tolerance in const <GoldenTolerance?>[
      null,
      .exact(),
      .pixel(),
    ]) {
      expect(
        () => matchesGoldenFile(
          Swatch.golden,
          tolerance: tolerance,
          textTolerance: const TextTolerance(
            colorTolerance: 0,
            maxDiffRatio: 1,
          ),
        ),
        returnsNormally,
        reason: '${tolerance ?? 'the rule'}',
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
      // Would wrap around to 705032704 as an unsigned 32-bit pixel.
      .fromLTWH(5_000_000_000, 0, 5, 5),
      .fromLTWH(0, 4_294_967_295, 1, 1),
    ]) {
      expect(
        () => matchesGoldenFile(Swatch.golden, ignoreRegions: [region]),
        _throwsInvalid(
          'ignoreRegions',
          'must be finite, non-empty and have coordinates between 0 and '
              '4294967295',
        ),
        reason: '$region',
      );
    }
    expect(
      () => matchesGoldenFile(
        Swatch.golden,
        ignoreRegions: const [.fromLTWH(4_294_967_294, 0, 1, 1)],
      ),
      returnsNormally,
      reason: 'the last pixel of the range',
    );
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
    expect(
      describe(
        matchesGoldenFile(
          'goldens/a.png',
          textTolerance: const TextTolerance(),
        ),
      ),
      endsWith('(gleon default tolerance, text color ±24, ≤ 10.00% per tile)'),
    );
  });
}
