import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/pixel_region.dart';

import '../../../helpers/value_semantics.dart';

void main() {
  const region = PixelRegion(x: 1, y: 2, width: 3, height: 4);

  test('is a value', () {
    expectValueSemantics(
      region,
      equal: const PixelRegion(x: 1, y: 2, width: 3, height: 4),
      different: const PixelRegion(x: 1, y: 2, width: 3, height: 5),
    );
    expect('$region', '(1, 2) 3x4px');
  });

  test('covers a rectangle with whole pixels', () {
    expect(
      PixelRegion.outwards(left: 1.5, top: 2.25, right: 3.5, bottom: 4.75),
      const PixelRegion(x: 1, y: 2, width: 3, height: 3),
    );
    expect(PixelRegion.outwards(left: 1, top: 2, right: 4, bottom: 6), region);
  });

  test('covers only finite, non-negative rectangles (asserted)', () {
    expect(
      () => PixelRegion.outwards(left: -0.5, top: 0, right: 1, bottom: 1),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => PixelRegion.outwards(left: 0, top: 0, right: .nan, bottom: 1),
      throwsA(isA<AssertionError>()),
    );
  });
}
