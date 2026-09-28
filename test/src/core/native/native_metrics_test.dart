import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/pixel_region.dart';
import 'package:gleon/src/core/native/native_metrics.dart';

import '../../../helpers/value_semantics.dart';

void main() {
  const pixel = PixelMetrics(
    totalPixels: 100,
    diffPixels: 2,
    diffRatio: 0.02,
    headroom: -0.01,
  );
  const ssim = SsimMetrics(
    minSsim: 0.9,
    meanSsim: 0.99,
    peakExcess: 5,
    changedPixels: 3,
    failingPixels: 0,
    similarityHeadroom: 0.1,
    colorHeadroom: 3,
    changedRegion: PixelRegion(x: 0, y: 0, width: 1, height: 3),
  );

  test('metrics are values', () {
    expectValueSemantics<NativeMetrics>(
      pixel,
      equal: NativeMetrics.fromJson(pixel.toJson()) ?? ssim,
      different: ssim,
    );
    expectValueSemantics<NativeMetrics>(
      ssim,
      equal: NativeMetrics.fromJson(ssim.toJson()) ?? pixel,
      different: const SsimMetrics(
        minSsim: 0.9,
        meanSsim: 0.99,
        peakExcess: 5,
        changedPixels: 3,
        failingPixels: 0,
        similarityHeadroom: 0.1,
        colorHeadroom: 3,
      ),
    );
  });

  test('unknown kinds are rejected', () {
    expect(NativeMetrics.fromJson(const {'kind': 'fuzzy'}), isNull);
    expect(NativeMetrics.fromJson(null), isNull);
  });
}
