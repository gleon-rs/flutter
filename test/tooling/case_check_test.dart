import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../bin/src/case_check.dart';

void main() {
  const shared = 'test/goldens/a.png';
  const linuxOwn = 'test/goldens/linux-x86_64/a.png';

  /// A case report as JSON text.
  String report({
    String path = shared,
    String? fallback,
    String os = 'macos',
    String arch = 'aarch64',
    double text = 0.05,
    bool hasText = true,
    String outcome = 'match',
    String? runId,
    int version = 2,
  }) => json.encode({
    'comparison': {'text_tolerance': ?(hasText ? text : null)},
    'golden': {'fallback': ?fallback, 'path': path},
    'outcome': outcome,
    'platform': {'arch': arch, 'os': os},
    'run_id': ?runId,
    'schema_version': version,
  });

  group('with a fallback platform', () {
    const check = CaseCheck(fallbackPlatform: 'macos-aarch64');

    test('its own platform compares the shared golden with text', () {
      expect(check.problemsOfReport(report()), isEmpty);
      expect(check.problemsOfReport(report(fallback: shared)), [
        'compared $shared, expected $shared itself',
      ]);
      expect(check.problemsOfReport(report(text: 1)), [
        'text tolerance 1.0, expected 0.05',
      ]);
      expect(check.problemsOfReport(report(hasText: false)), [
        'text tolerance none, expected 0.05',
      ]);
    });

    test('another platform falls back to it with text ignored', () {
      String linux({String path = linuxOwn, String? fallback, double? text}) =>
          report(
            path: path,
            fallback: fallback,
            os: 'linux',
            arch: 'x86_64',
            text: text ?? 0,
            hasText: text != null,
          );

      expect(check.problemsOfReport(linux(fallback: shared, text: 1)), isEmpty);
      expect(check.problemsOfReport(linux(text: 1)), [
        'compared its own golden, expected $shared',
      ]);
      expect(check.problemsOfReport(linux(fallback: shared)), [
        'text tolerance none, expected 1.0',
      ]);
      expect(
        check.problemsOfReport(linux(path: shared, fallback: shared, text: 1)),
        [
          'golden.path $shared is not in a linux-x86_64/ directory',
          'compared $shared, expected test/a.png',
        ],
      );
    });
  });

  group('with own goldens', () {
    const check = CaseCheck(fallbackPlatform: null);

    test('every platform compares its own golden with text', () {
      expect(
        check.problemsOfReport(
          report(path: linuxOwn, os: 'linux', arch: 'x86_64'),
        ),
        isEmpty,
      );
      expect(
        check.problemsOfReport(
          report(path: linuxOwn, fallback: shared, os: 'linux', arch: 'x86_64'),
        ),
        ['compared $shared, expected $linuxOwn'],
      );
    });

    test('a dashed OS has a key=value directory, like gleon', () {
      expect(
        CaseCheck.platformKey(os: 'macos', arch: 'aarch64'),
        'macos-aarch64',
      );
      expect(
        CaseCheck.platformKey(os: 'ios-sim', arch: 'arm64'),
        'os=ios-sim+arch=arm64',
      );
      expect(
        check.problemsOfReport(
          report(
            path: 'goldens/os=ios-sim+arch=arm64/a.png',
            os: 'ios-sim',
            arch: 'arm64',
          ),
        ),
        isEmpty,
      );
      const misplaced =
          'golden.path goldens/ios-sim-aarch64/a.png is not in a '
          'os=ios-sim+arch=aarch64/ directory';
      expect(
        check.problemsOfReport(
          report(path: 'goldens/ios-sim-aarch64/a.png', os: 'ios-sim'),
        ),
        [misplaced],
      );
    });
  });

  test('a file that is no case report is a problem, not a crash', () {
    const check = CaseCheck(fallbackPlatform: 'macos-aarch64');

    expect(
      check.problemsOfReport('{"golden": '),
      allOf(hasLength(1), everyElement(startsWith('invalid JSON ('))),
    );
    for (final other in ['[1, 2]', '{}', '"report"', '{"golden": {}}']) {
      final problems = check.problemsOfReport(other);
      expect(problems, ['not a case report'], reason: other);
    }
  });

  test('the run id, outcome and schema version must match', () {
    const check = CaseCheck(
      fallbackPlatform: 'macos-aarch64',
      outcomes: {'identical'},
      runId: 'run-1',
    );

    expect(
      check.problemsOfReport(report(outcome: 'identical', runId: 'run-1')),
      isEmpty,
    );
    expect(check.problemsOfReport(report(runId: 'run-2', version: 3)), [
      'schema_version 3, expected 2',
      'outcome match, expected one of identical',
      'run_id run-2, expected run-1',
    ]);
    expect(check.problemsOfReport(report(outcome: 'identical')), [
      'run_id none, expected run-1',
    ]);
  });

  test('a run needs at least --min-cases reports', () {
    const check = CaseCheck(fallbackPlatform: null, minCases: 2);

    expect(check.tooFew(1), '1 case reports, expected at least 2.');
    expect(check.tooFew(2), isNull);
    expect(const CaseCheck(fallbackPlatform: null).tooFew(0), isNotNull);
  });
}
