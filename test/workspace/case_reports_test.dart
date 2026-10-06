import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:gleon/gleon.dart';
import 'package:gleon/src/core/config/gleon_session.dart';
import 'package:gleon/src/flutter/gleon_golden_comparator.dart';

import '../helpers/blob.dart';
import '../helpers/golden_updates.dart';
import '../helpers/prints.dart';
import '../helpers/swatch.dart';
import '../helpers/workspace_sandbox.dart';

const _yaml = '''
required_version: ">=0.1.0"
exclude: "test/goldens/excluded_*.png"
screenshots:
  - include: "test/goldens/**/*.png"
    mode: ssim
    diff: { min_similarity: 0.8, color_tolerance: 8 }
metrics:
  enabled: true
''';

const _disabledYaml = '''
required_version: ">=0.1.0"
screenshots:
  - include: "test/goldens/*.png"
metrics: { enabled: false, console: false }
''';

/// An unset environment variable.
const _unset = '';

/// Matches a lowercase hex SHA-256.
Matcher _isSha256() => matches(RegExp(r'^[0-9a-f]{64}$'));

/// The `sha256` of a recorded image.
String _shaOf(Object? image) => switch (image) {
  {'sha256': final String sha256} => sha256,
  _ => fail('no sha256 in the report'),
};

void main() {
  // Only the PNG bytes of the golden itself are identical: a widget is
  // compared as raw pixels, and equal pixels are a match.
  test('identical: schema-valid case without metrics', () async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    final lines = await capturePrints(
      () => expectLater(
        sandbox.goldenBytes(Swatch.golden),
        sandbox.matcher(Swatch.golden),
      ),
    );
    final report = sandbox.readCase('test/goldens/swatch');

    expect(report, containsPair('outcome', 'identical'));
    expect(report, containsPair('name', 'test/goldens/swatch'));
    expect(
      report['golden'],
      allOf(
        containsPair('path', 'test/goldens/swatch.png'),
        containsPair('sha256', _isSha256()),
        containsPair('width', 100),
        containsPair('height', 60),
      ),
    );
    expect(report['golden'], isNot(contains('blob')), reason: 'PNG goldens');
    expect(
      report['candidate'],
      containsPair('sha256', _shaOf(report['golden'])),
      reason: 'identical PNGs hash the same',
    );
    expect(report.containsKey('metrics'), isFalse);
    expect(report.containsKey('artifacts'), isFalse, reason: 'a pass');
    expect(report.containsKey('run_id'), isFalse, reason: 'no GLEON_RUN_ID');
    expect(report, containsPair('schema_version', 2));
    expect(report, containsPair('regions', isEmpty));
    expect(report['comparison'], {
      'masks': isEmpty,
      'policy_version': 2,
      'tolerance': {
        'color_tolerance': 8.0,
        'kind': 'ssim',
        'min_similarity': 0.8,
      },
    });
    expect(report['source'], {
      'renderer': startsWith('flutter-'),
      'tool': 'gleon_flutter',
      'tool_version': isNotEmpty,
    });
    expect(report['platform'], {'arch': isNotEmpty, 'os': isNotEmpty});
    expect(report['test'], {
      'name': 'identical: schema-valid case without metrics',
    });
    expect(
      lines.singleOrNull,
      startsWith('gleon = test/goldens/swatch.png  identical  '),
    );
  });

  testWidgets('an image is compared as raw pixels: a match', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch());
    final image =
        await tester.runAsync(
          () => captureImage(
            Swatch.finder.evaluate().singleOrNull ?? fail('no swatch'),
          ),
        ) ??
        fail('no image captured');
    addTearDown(image.dispose);
    await capturePrints(
      () => expectLater(image, sandbox.matcher(Swatch.golden)),
    );

    expect(
      sandbox.readCase('test/goldens/swatch'),
      containsPair('outcome', 'match'),
    );
  });

  testWidgets('match: headroom metrics and a console line', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Blob(offset: 0.3));
    final lines = await capturePrints(
      () => expectLater(Blob.finder, sandbox.matcher(Blob.golden)),
    );
    final report = sandbox.readCase('test/goldens/blob');
    final metrics = report['metrics'];

    expect(report, containsPair('outcome', 'match'));
    expect(
      metrics,
      allOf(
        containsPair('kind', 'ssim'),
        containsPair('headroom', containsPair('similarity', greaterThan(0))),
      ),
    );
    expect(report['regions'], [
      {'kind': 'image', 'metrics': metrics},
    ]);
    expect(report['timings_ms'], containsPair('native', isA<num>()));
    expect(
      lines.singleOrNull,
      matches(
        RegExp(
          r'^gleon ✓ test/goldens/blob\.png  ssim \d\.\d{3,4} \(≥0\.800, '
          r'\+\d\.\d{3,4}\)  color \d+\.\d \(≤8, [+-]\d+\.\d\)  \d+ ms$',
        ),
      ),
    );
  });

  testWidgets('mismatch: recorded before failing', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch(accent: Color(0xFF4CAF50)));
    final failure = await sandbox
        .matcher(Swatch.golden)
        .matchAsync(Swatch.finder);
    final report = sandbox.readCase('test/goldens/swatch');

    expect(failure, contains('changed area'));
    expect(report, containsPair('outcome', 'mismatch'));
    expect(
      report,
      containsPair('message', contains('changed area at (0, 0) 50x60px')),
    );
    expect(
      report['metrics'],
      containsPair('headroom', containsPair('color', lessThan(0))),
    );
    expect(
      report['metrics'],
      containsPair('max_excess', greaterThan(0)),
      reason: 'the envelope gate failed',
    );
  });

  testWidgets('dimension mismatch is recorded without metrics', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch(size: Size(100, 61)));
    await sandbox.matcher(Swatch.golden).matchAsync(Swatch.finder);
    final report = sandbox.readCase('test/goldens/swatch');

    expect(report, containsPair('outcome', 'dimension_mismatch'));
    expect(report['candidate'], containsPair('height', 61));
    expect(report.containsKey('metrics'), isFalse);
  });

  testWidgets('--update-goldens records an updated case', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
    await withGoldenUpdates(
      () => expectLater(Swatch.finder, sandbox.matcher('goldens/new.png')),
    );
    final report = sandbox.readCase('test/goldens/new');

    expect(report, containsPair('outcome', 'updated'));
    expect(report.containsKey('metrics'), isFalse);
    expect(report['golden'], containsPair('path', 'test/goldens/new.png'));
  });

  testWidgets('missing: a new golden is recorded without a golden hash', (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch());
    final results = <String?>[];
    Future<void> match() async => results.add(
      await sandbox.matcher('goldens/new/swatch.png').matchAsync(Swatch.finder),
    );
    final lines = await capturePrints(match);
    final report = sandbox.readCase('test/goldens/new/swatch');

    // Word for word the failure of Flutter's own comparator.
    expect(
      results.singleOrNull,
      'Could not be compared against non-existent file: '
      '"goldens/new/swatch.png"',
    );
    expect(report, containsPair('outcome', 'missing'));
    expect(report['golden'], {'path': 'test/goldens/new/swatch.png'});
    expect(report['candidate'], containsPair('sha256', _isSha256()));
    expect(
      lines.singleOrNull,
      startsWith('gleon ? test/goldens/new/swatch.png  missing  '),
    );
  });

  test('error: a corrupt candidate is recorded as an image error', () async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    final failure = await sandbox
        .matcher(Swatch.golden)
        .matchAsync(Uint8List.fromList(List.filled(64, 7)));
    final report = sandbox.readCase('test/goldens/swatch');

    expect(failure, contains('gleon could not compare: candidate image'));
    expect(failure, isNot(contains(GleonGoldenComparator.bugHint)));
    expect(report, containsPair('outcome', 'error'));
    expect(report, containsPair('error_kind', 'image'));
    expect(report, containsPair('message', startsWith('candidate image')));
    expect(report.containsKey('artifacts'), isFalse);
  });

  testWidgets('masks beyond the image warn', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    // Masks apply only to differing images: the dot inside the mask differs.
    await tester.pumpWidget(const Swatch(dot: Offset(96, 5)));
    final lines = await capturePrints(
      () => expectLater(
        Swatch.finder,
        sandbox.matcher(
          Swatch.golden,
          ignoreRegions: const [Rect.fromLTWH(95, 0, 10, 10)],
        ),
      ),
    );

    expect(
      lines.firstOrNull,
      'gleon: 1 mask of golden "goldens/swatch.png" reaches beyond the image '
      'and was clipped to it.',
    );
  });

  testWidgets('several warnings print one line each', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch(dot: Offset(96, 5)));
    final lines = await capturePrints(
      () => expectLater(
        Swatch.finder,
        sandbox.matcher(
          Swatch.golden,
          ignoreRegions: const [Rect.fromLTWH(95, 0, 10, 10)],
          session: sessionWithoutWorkspace(metrics: '1'),
        ),
      ),
    );

    expect(lines, hasLength(2));
    expect(lines.firstOrNull, startsWith('gleon: 1 mask of golden'));
    expect(lines.lastOrNull, startsWith('gleon: GLEON_METRICS is set but'));
  });

  testWidgets('an unwritable case report only warns', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    // A file where the cases directory should be.
    File('${sandbox.root.path}/.gleon/runs/latest/cases')
      ..parent.createSync(recursive: true)
      ..createSync();
    await tester.pumpWidget(const Swatch());
    final lines = await capturePrints(
      () => expectLater(Swatch.finder, sandbox.matcher(Swatch.golden)),
    );

    expect(
      lines.singleOrNull,
      startsWith('gleon: cannot write the case report'),
    );
  });

  // Finder inputs run the comparator inside Flutter's `binding.runAsync`
  // (every widget test above records its name through it); byte inputs do
  // not, and must name the test too.
  test('the test name is known for byte inputs outside runAsync', () async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await expectLater(
      sandbox.goldenBytes(Swatch.golden),
      sandbox.matcher(Swatch.golden),
    );

    expect(sandbox.readCase('test/goldens/swatch')['test'], {
      'name': 'the test name is known for byte inputs outside runAsync',
    });
  });

  testWidgets('excluded and unmatched goldens record nothing', (tester) async {
    final sandbox = WorkspaceSandbox.create(
      _yaml,
      extraGoldens: const {
        'goldens/excluded_swatch.png': 'swatch.png',
        'other/swatch.png': 'swatch.png',
      },
    );
    await tester.pumpWidget(const Swatch());
    await expectLater(
      Swatch.finder,
      sandbox.matcher('goldens/excluded_swatch.png'),
    );
    await expectLater(Swatch.finder, sandbox.matcher('other/swatch.png'));

    expect(sandbox.recordedFiles, isEmpty);
  });

  testWidgets('.gleon/.gitignore is created like gleon init, or kept', (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    final gitignore = File('${sandbox.root.path}/.gleon/.gitignore');
    await tester.pumpWidget(const Swatch());
    await expectLater(Swatch.finder, sandbox.matcher(Swatch.golden));

    expect(
      gitignore.readAsLinesSync(),
      containsAllInOrder(['blobs/', 'runs/', '.env', '.env.local']),
    );
    gitignore.writeAsStringSync('runs/\n# mine\n');
    await expectLater(
      Swatch.finder,
      sandbox.matcher(Swatch.golden, tolerance: const .exact()),
    );

    expect(gitignore.readAsStringSync(), 'runs/\n# mine\n');
  });

  group('GLEON_METRICS', () {
    testWidgets('enables metrics a disabled yaml does not', (tester) async {
      final sandbox = WorkspaceSandbox.create(_disabledYaml);
      await tester.pumpWidget(const Swatch());
      final lines = await capturePrints(
        () => expectLater(
          Swatch.finder,
          sandbox.matcher(
            Swatch.golden,
            session: sandbox.session(metrics: '1'),
          ),
        ),
      );

      expect(
        sandbox.readCase('test/goldens/swatch'),
        containsPair('outcome', 'match'),
      );
      expect(lines, isEmpty, reason: 'console: false still applies');
    });

    testWidgets('disables metrics the yaml enables', (tester) async {
      final sandbox = WorkspaceSandbox.create(_yaml);
      await tester.pumpWidget(const Swatch());
      await expectLater(
        Swatch.finder,
        sandbox.matcher(Swatch.golden, session: sandbox.session(metrics: '0')),
      );

      expect(sandbox.recordedFiles, isEmpty);
    });

    testWidgets('an invalid value fails, with or without a workspace', (
      tester,
    ) async {
      final sandbox = WorkspaceSandbox.create(_yaml);
      await tester.pumpWidget(const Swatch());
      for (final session in [
        sandbox.session(metrics: 'yes'),
        sessionWithoutWorkspace(metrics: 'yes'),
      ]) {
        final message = await sandbox
            .matcher(Swatch.golden, session: session)
            .matchAsync(Swatch.finder);

        expect(message, contains('GLEON_METRICS must be 1, 0, true or false'));
      }
    });

    testWidgets('without a workspace warns once, only when requested', (
      tester,
    ) async {
      final sandbox = WorkspaceSandbox.create(_yaml);
      await tester.pumpWidget(const Swatch());
      Future<List<String>> run(GleonSession session) => capturePrints(
        () => expectLater(
          Swatch.finder,
          sandbox.matcher(Swatch.golden, session: session),
        ),
      );
      final session = sessionWithoutWorkspace(metrics: '1');

      final lines = await run(session);

      expect(lines, hasLength(1));
      expect(lines.singleOrNull, contains('gleon init'));
      expect(await run(session), isEmpty, reason: 'once per session');
      for (final value in ['0', 'false', ' ', _unset]) {
        expect(
          await run(sessionWithoutWorkspace(metrics: value)),
          isEmpty,
          reason: 'GLEON_METRICS="$value"',
        );
      }
    });
  });

  // ignore: missing-test-assertion, the assertions live in the helper below.
  test(
    'the committed schema rejects an off-contract case',
    _expectSchemaRejectsOffContractCases,
    skip: caseSchema == null ? 'needs a gleon checkout at ../gleon' : null,
  );
}

void _expectSchemaRejectsOffContractCases() {
  final valid = {
    'candidate': {'sha256': '0' * 64},
    'comparison': {
      'masks': <Object>[],
      'policy_version': 2,
      'tolerance': {'kind': 'exact'},
    },
    'golden': {'path': 'a.png', 'sha256': '0' * 64},
    'name': 'a',
    'outcome': 'identical',
    'platform': {'arch': 'aarch64', 'os': 'macos'},
    'recorded_at': '2026-09-27T12:00:00.000Z',
    'regions': <Object>[],
    'schema_version': 2,
    'source': {'tool': 'gleon_flutter', 'tool_version': '0.1.0'},
    'timings_ms': {'total': 1.5},
  };
  final failed = {
    ...valid,
    'artifacts': {'candidate': '.gleon/runs/latest/artifacts/a/candidate.png'},
    'error_kind': 'image',
    'golden': {'blob': 'sha256:${'0' * 64}', 'path': 'a.png'},
    'outcome': 'error',
    'run_id': '12345',
  };
  final schema = caseSchema;

  expect(schema?.validate(valid).isValid, isTrue);
  expect(schema?.validate(failed).isValid, isTrue);
  for (final broken in [
    {...valid, 'schema_version': 1},
    {...valid, 'outcome': 'passed'},
    {...valid, 'name': 'Upper/Case'},
    {...valid, 'extra': 1},
    {...failed, 'error_kind': 'disk'},
    {...failed, 'run_id': 'run 1'},
    {
      ...failed,
      'artifacts': {'image': 'a.png'},
    },
    {
      ...valid,
      'comparison': {
        'masks': <Object>[],
        'policy_version': 2,
        'tolerance': {'kind': 'exact', 'max_diff_ratio': 0.1},
      },
    },
  ]) {
    expect(schema?.validate(broken).isValid, isFalse, reason: '$broken');
  }
}
