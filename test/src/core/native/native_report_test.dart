import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/pixel_region.dart';
import 'package:gleon/src/core/native/native_metrics.dart';
import 'package:gleon/src/core/native/native_report.dart';
import 'package:gleon/src/core/native/native_timings.dart';

import '../../../helpers/value_semantics.dart';

void main() {
  final diff = Uint8List.fromList(const [1, 2, 3]);
  const timings = {'compare': 300, 'decode': 1200, 'encode': 0};
  const pixelMetrics = {
    'diff_pixels': 1,
    'diff_ratio': 1 / 6000,
    'headroom': -1 / 6000,
    'kind': 'pixel',
    'total_pixels': 6000,
  };
  const ssimMetrics = {
    'changed_pixels': 1,
    'changed_region': {'height': 1, 'width': 1, 'x': 10, 'y': 10},
    'failing_pixels': 1,
    'failing_region': {'height': 1, 'width': 1, 'x': 10, 'y': 10},
    'headroom': {'color': -138.0, 'similarity': -0.3},
    'kind': 'ssim',
    'mean_ssim': 0.99,
    'min_ssim': 0.5,
    'peak_excess': 146.0,
  };

  TypeMatcher<NativeMismatch> isMismatch(String summary) =>
      isA<NativeMismatch>().having(
        (mismatch) => mismatch.summary,
        'summary',
        summary,
      );

  test('parses a match with its metrics and timings', () {
    const json = {
      'abi': 4,
      'metrics': pixelMetrics,
      'policy_version': 2,
      'regions': [
        {'kind': 'image', 'metrics': pixelMetrics},
      ],
      'timings_us': timings,
      'verdict': 'match',
    };

    expect(
      NativeReport.parse(json, null),
      isA<NativeMatch>()
          .having((match) => match.policyVersion, 'policy', 2)
          .having((match) => match.timings.totalMilliseconds, 'native ms', 1.5)
          .having(
            (match) => match.metrics,
            'metrics',
            const PixelMetrics(
              totalPixels: 6000,
              diffPixels: 1,
              diffRatio: 1 / 6000,
              headroom: -1 / 6000,
            ),
          ),
    );
  });

  test('parses a pixel mismatch', () {
    const json = {
      'baseline': {'height': 60, 'width': 100},
      'metrics': pixelMetrics,
      'policy_version': 2,
      'timings_us': timings,
      'verdict': 'mismatch',
    };

    expect(
      NativeReport.parse(json, diff),
      isMismatch('0.02% (1 of 6000px) differ')
          .having((mismatch) => mismatch.diffPng, 'diff image', diff),
    );
  });

  test('parses an SSIM mismatch with its failing region', () {
    const json = {
      'baseline': {'height': 60, 'width': 100},
      'metrics': ssimMetrics,
      'policy_version': 2,
      'timings_us': timings,
      'verdict': 'mismatch',
    };
    final report = NativeReport.parse(json, diff);

    expect(
      report,
      isMismatch(
        'changed area at (10, 10) 1x1px: min local SSIM 0.5000, colors '
        'deviate by up to 146.0 (8-bit units)',
      ),
    );
    expect(
      report,
      isA<NativeMismatch>().having(
        (mismatch) => mismatch.metrics.toJson(),
        'metrics JSON (round-trips into case reports)',
        ssimMetrics,
      ),
    );
  });

  test('an SSIM failure without a region or color excess', () {
    const metrics = SsimMetrics(
      minSsim: 0.7,
      meanSsim: 0.99,
      peakExcess: 2,
      changedPixels: 4,
      failingPixels: 0,
      similarityHeadroom: -0.1,
      colorHeadroom: 6,
      changedRegion: PixelRegion(x: 0, y: 0, width: 2, height: 2),
    );

    expect(metrics.describe(), 'min local SSIM 0.7000');
    expect(metrics.toJson().containsKey('failing_region'), isFalse);
  });

  test('parses a dimension mismatch', () {
    const json = {
      'baseline': {'height': 60, 'width': 100},
      'candidate': {'height': 61, 'width': 100},
      'policy_version': 2,
      'regions': <Object>[],
      'timings_us': timings,
      'verdict': 'dimension_mismatch',
    };

    expect(
      NativeReport.parse(json, null),
      isA<NativeDimensionMismatch>().having(
        (mismatch) => mismatch.summary,
        'summary',
        'golden is 100x60px, test image is 100x61px',
      ),
    );
  });

  test('parses an error', () {
    const json = {'error': 'baseline image: bad PNG', 'verdict': 'error'};

    expect(
      NativeReport.parse(json, null),
      isA<NativeError>().having(
        (error) => error.message,
        'message',
        'baseline image: bad PNG',
      ),
    );
  });

  test('anything off-contract is an error, never a pass', () {
    for (final json in <Object?>[
      null,
      'match',
      {'verdict': 'match'},
      {'metrics': pixelMetrics, 'policy_version': 2, 'verdict': 'match'},
      {
        'metrics': {'kind': 'fuzzy'},
        'policy_version': 2,
        'timings_us': timings,
        'verdict': 'match',
      },
      {'verdict': 'error'},
    ]) {
      expect(
        NativeReport.parse(json, null),
        isA<NativeError>(),
        reason: jsonEncode(json),
      );
    }
    const mismatchWithoutDiff = {
      'baseline': {'height': 60, 'width': 100},
      'metrics': pixelMetrics,
      'policy_version': 2,
      'timings_us': timings,
      'verdict': 'mismatch',
    };

    expect(NativeReport.parse(mismatchWithoutDiff, null), isA<NativeError>());
  });

  test('timings are values', () {
    const value = NativeTimings(
      decodeMicros: 1,
      compareMicros: 2,
      encodeMicros: 3,
    );
    expectValueSemantics(
      value,
      equal:
          NativeTimings.fromJson(const {
            'compare': 2,
            'decode': 1,
            'encode': 3,
          }) ??
          value,
      different: const NativeTimings(
        decodeMicros: 1,
        compareMicros: 2,
        encodeMicros: 4,
      ),
    );
  });

  test('verdicts without their required fields are errors', () {
    for (final json in [
      {
        'metrics': pixelMetrics,
        'policy_version': 2,
        'timings_us': timings,
        'verdict': 'mismatch',
      },
      {
        'baseline': {'height': 60, 'width': 100},
        'policy_version': 2,
        'timings_us': timings,
        'verdict': 'dimension_mismatch',
      },
    ]) {
      expect(
        NativeReport.parse(json, diff),
        isA<NativeError>().having(
          (error) => error.message,
          'message',
          startsWith('unexpected native report'),
        ),
      );
    }
  });
}
