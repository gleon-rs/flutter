import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../bin/src/case_check.dart';

void main() {
  const golden = 'test/goldens/a.png';

  /// A case report of the golden `test/goldens/a` as JSON text.
  String report({
    String? recorded,
    String os = 'macos',
    String arch = 'aarch64',
    double text = 0.05,
    bool hasText = true,
    String outcome = 'match',
    String? runId,
    int version = 5,
  }) => json.encode({
    'comparison': {'text_tolerance': ?(hasText ? text : null)},
    'golden': {'path': golden, 'platform': ?recorded},
    'name': 'test/goldens/a',
    'outcome': outcome,
    'platform': {'arch': arch, 'os': os},
    'run_id': ?runId,
    'schema_version': version,
  });

  /// The problems of [content] filed at [location] (relative to `cases/`),
  /// by default where it belongs: `<platform key>/<name>.json`.
  List<String> problemsOf(CaseCheck check, String content, {String? location}) {
    final belongs = switch (json.decode(content)) {
      {
        'name': final String name,
        'platform': {'arch': final String arch, 'os': final String os},
      } =>
        '${CaseCheck.platformKey(os: os, arch: arch)}/$name.json',
      _ => 'a.json',
    };

    return check.problemsOfReport(content, location: location ?? belongs);
  }

  group('with a fallback platform', () {
    const check = CaseCheck(fallbackPlatform: 'macos-aarch64');

    test('it compares its goldens with text', () {
      expect(problemsOf(check, report()), isEmpty);
      expect(problemsOf(check, report(recorded: 'macos-aarch64')), isEmpty);
      expect(problemsOf(check, report(text: 1)), [
        'text tolerance 1.0, expected 0.05',
      ]);
      expect(problemsOf(check, report(hasText: false)), [
        'text tolerance none, expected 0.05',
      ]);
    });

    test('another platform compares them with text ignored', () {
      String linux({String? recorded, double? text}) => report(
        recorded: recorded,
        os: 'linux',
        arch: 'x86_64',
        text: text ?? 0,
        hasText: text != null,
      );

      expect(problemsOf(check, linux(text: 1)), isEmpty);
      expect(
        problemsOf(check, linux(recorded: 'macos-aarch64', text: 1)),
        isEmpty,
      );
      expect(problemsOf(check, linux()), ['text tolerance none, expected 1.0']);
    });

    test('a golden recorded on another platform is a problem', () {
      expect(problemsOf(check, report(recorded: 'linux-x86_64')), [
        'golden recorded on linux-x86_64, expected macos-aarch64',
      ]);
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
      final dashed = report(os: 'ios-sim', arch: 'arm64', text: 1);
      const misplaced =
          'lies at ios-sim-arm64/test/goldens/a.json, expected '
          'os=ios-sim+arch=arm64/test/goldens/a.json';
      expect(problemsOf(check, dashed), isEmpty);
      expect(
        problemsOf(
          check,
          dashed,
          location: 'ios-sim-arm64/test/goldens/a.json',
        ),
        [misplaced],
      );
    });
  });

  test('a file that is no case report is a problem, not a crash', () {
    const check = CaseCheck(fallbackPlatform: 'macos-aarch64');

    expect(
      check.problemsOfReport('{"golden": ', location: 'a.json'),
      allOf(hasLength(1), everyElement(startsWith('invalid JSON ('))),
    );
    for (final other in ['[1, 2]', '{}', '"report"', '{"golden": {}}']) {
      final problems = check.problemsOfReport(other, location: 'a.json');
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
      problemsOf(check, report(outcome: 'identical', runId: 'run-1')),
      isEmpty,
    );
    expect(problemsOf(check, report(runId: 'run-2', version: 2)), [
      'schema_version 2, expected 5',
      'outcome match, expected one of identical',
      'run_id run-2, expected run-1',
    ]);
    expect(problemsOf(check, report(outcome: 'identical')), [
      'run_id none, expected run-1',
    ]);
  });

  test('a report lies at cases/<platform key>/<name>.json', () {
    const check = CaseCheck(fallbackPlatform: 'macos-aarch64');

    for (final misplaced in [
      'test/goldens/a.json',
      'linux-x86_64/test/goldens/a.json',
      'macos-aarch64/test/goldens/b.json',
    ]) {
      expect(problemsOf(check, report(), location: misplaced), [
        'lies at $misplaced, expected macos-aarch64/test/goldens/a.json',
      ]);
    }
  });

  test('a run needs at least --min-cases reports', () {
    const check = CaseCheck(fallbackPlatform: 'macos-aarch64', minCases: 2);

    expect(check.tooFew(1), '1 case reports, expected at least 2.');
    expect(check.tooFew(2), isNull);
    expect(
      const CaseCheck(fallbackPlatform: 'macos-aarch64').tooFew(0),
      isNotNull,
    );
  });
}
