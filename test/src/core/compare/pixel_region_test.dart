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

  test('round-trips the engine Region JSON', () {
    expect(PixelRegion.fromNativeJson(region.toNativeJson()), region);
    expect(PixelRegion.fromNativeJson(const {'x': 1}), isNull);
    expect(PixelRegion.fromNativeJson(null), isNull);
  });
}
