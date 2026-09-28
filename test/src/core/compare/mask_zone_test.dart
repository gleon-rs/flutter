import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/mask_zone.dart';
import 'package:gleon/src/core/compare/pixel_region.dart';
import 'package:gleon/src/core/compare/zone_length.dart';

import '../../../helpers/value_semantics.dart';

void main() {
  test('parses pixel and percentage extents like gleon-model', () {
    expect(
      MaskZone.fromNativeJson(const {
        'height': '20',
        'width': '25%',
        'x': 1,
        'y': 2,
      }),
      const MaskZone(
        x: 1,
        y: 2,
        width: PercentLength(25),
        height: PixelLength(20),
      ),
    );
    expect(
      MaskZone.fromNativeJson(const {
        'height': 'x%',
        'width': 1,
        'x': 0,
        'y': 0,
      }),
      isNull,
    );
    expect(MaskZone.fromNativeJson(const {'x': 0}), isNull);
  });

  test('serializes back to the native zone format', () {
    const zone = MaskZone(
      x: 1,
      y: 2,
      width: PercentLength(25),
      height: PixelLength(20),
    );

    expect(zone.toNativeJson(), {
      'height': 20,
      'width': '25.0%',
      'x': 1,
      'y': 2,
    });
    expect(
      MaskZone.fromRegion(const PixelRegion(x: 3, y: 4, width: 5, height: 6))
          .toNativeJson(),
      {'height': 6, 'width': 5, 'x': 3, 'y': 4},
    );
  });

  test('zones and lengths are values', () {
    const zone = MaskZone(
      x: 1,
      y: 2,
      width: PercentLength(25),
      height: PixelLength(20),
    );
    expectValueSemantics(
      zone,
      equal: MaskZone.fromNativeJson(zone.toNativeJson()) ?? zone,
      different: const MaskZone(
        x: 1,
        y: 2,
        width: PercentLength(25),
        height: PixelLength(21),
      ),
    );
    expect('$zone', '(1, 2) 25.0% x 20px');
    expectValueSemantics<ZoneLength>(
      const PixelLength(3),
      equal: const PixelLength(3),
      different: const PercentLength(3),
    );
    expectValueSemantics<ZoneLength>(
      const PercentLength(3),
      equal: const PercentLength(3),
      different: const PercentLength(4),
    );
  });
}
