import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/golden_tolerance.dart';
import 'package:gleon/src/core/config/golden_resolution.dart';
import 'package:gleon/src/core/config/golden_rule.dart';

void main() {
  const resolved = {
    'abi': 4,
    'kind': 'resolved',
    'metrics': {'console': true, 'enabled': true},
    'platform': {'arch': 'aarch64', 'os': 'macos'},
    'policy_version': 2,
    'rule': {
      'index': 0,
      'kind': 'matched',
      'masks': [
        {'height': 10, 'width': '25%', 'x': 0, 'y': 0},
      ],
      'name': 'test/goldens/a',
      'tolerance': {'kind': 'pixel', 'max_diff_ratio': 0.02},
    },
  };

  test('parses a matched rule', () {
    final resolution = GoldenResolution.fromNativeJson(resolved);

    expect(
      resolution,
      isA<ResolvedGolden>()
          .having((golden) => golden.matched?.name, 'name', 'test/goldens/a')
          .having((golden) => golden.shouldRecordCase, 'records', isTrue)
          .having(
            (golden) => golden.rule,
            'rule',
            isA<MatchedRule>()
                .having(
                  (rule) => rule.tolerance,
                  'tolerance',
                  const GoldenTolerance.pixel(maxDiffRatio: 0.02),
                )
                .having((rule) => rule.masks, 'masks', hasLength(1)),
          ),
    );
  });

  test('excluded and unmatched goldens record no case', () {
    for (final kind in ['excluded', 'unmatched']) {
      final resolution = GoldenResolution.fromNativeJson({
        ...resolved,
        'rule': {'kind': kind},
      });

      expect(
        resolution,
        isA<ResolvedGolden>().having(
          (golden) => golden.shouldRecordCase,
          'records',
          isFalse,
        ),
        reason: kind,
      );
    }
  });

  test('errors and off-contract responses become errors', () {
    expect(
      GoldenResolution.fromNativeJson(const {
        'abi': 4,
        'error': 'bad yaml',
        'kind': 'error',
      }),
      isA<GoldenResolutionError>().having(
        (error) => error.message,
        'message',
        'bad yaml',
      ),
    );
    for (final json in <Object?>[
      null,
      {
        ...resolved,
        'rule': {'kind': 'matched'},
      },
      {...resolved, 'metrics': <String, Object>{}},
    ]) {
      expect(
        GoldenResolution.fromNativeJson(json),
        isA<GoldenResolutionError>(),
        reason: jsonEncode(json),
      );
    }
  });
}
