import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:gleon/gleon.dart';
import 'package:gleon/src/core/config/gleon_session.dart';

import '../helpers/blob.dart';
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

/// Matches a lowercase hex SHA-256.
Matcher _isSha256() => matches(RegExp(r'^[0-9a-f]{64}$'));

/// Runs [body] with `debugPrint` captured (reset to the test binding's
/// override before the test ends, as the binding requires) and returns the
/// printed lines.
Future<List<String>> _capturePrints(AsyncCallback body) async {
  final lines = <String>[];
  debugPrint = (message, {wrapWidth}) => lines.add(message ?? '(null)');
  try {
    await body();
  } finally {
    debugPrint = TestWidgetsFlutterBinding.instance.debugPrintOverride;
  }

  return lines;
}

void main() {
  testWidgets('identical: schema-valid case without metrics', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch());
    final lines = await _capturePrints(
      () => expectLater(Swatch.finder, sandbox.matcher(Swatch.golden)),
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
    expect(report['candidate'], containsPair('sha256', _isSha256()));
    expect(report.containsKey('metrics'), isFalse);
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

  testWidgets('identical PNGs hash the same', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch());
    await expectLater(Swatch.finder, sandbox.matcher(Swatch.golden));
    final report = sandbox.readCase('test/goldens/swatch');
    final golden = report['golden'];
    final candidate = report['candidate'];

    expect(
      golden is Map &&
          candidate is Map &&
          golden['sha256'] == candidate['sha256'],
      isTrue,
    );
  });

  testWidgets('match: headroom metrics and a console line', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Blob(offset: 0.3));
    final lines = await _capturePrints(
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
          r'^gleon ✓ test/goldens/blob\.png  ssim \d\.\d{3} \(≥0\.800, '
          r'\+\d\.\d{3}\)  color \d+\.\d \(≤8, [+-]\d+\.\d\)  \d+ ms$',
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
    addTearDown(() => autoUpdateGoldenFiles = false);
    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
    autoUpdateGoldenFiles = true;
    await expectLater(Swatch.finder, sandbox.matcher('goldens/new.png'));
    autoUpdateGoldenFiles = false;
    final report = sandbox.readCase('test/goldens/new');

    expect(report, containsPair('outcome', 'updated'));
    expect(report.containsKey('metrics'), isFalse);
    expect(report['golden'], containsPair('path', 'test/goldens/new.png'));
  });

  // Finder inputs run the comparator inside Flutter's `binding.runAsync`
  // (every widget test above records its name through it); byte inputs do
  // not, and must name the test too.
  test('the test name is known for byte inputs outside runAsync', () async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    final bytes = File('${sandbox.root.path}/test/${Swatch.golden}')
        .readAsBytesSync();
    await expectLater(bytes, sandbox.matcher(Swatch.golden));

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
      final lines = await _capturePrints(
        () => expectLater(
          Swatch.finder,
          sandbox.matcher(
            Swatch.golden,
            session: sandbox.session(metricsEnv: '1'),
          ),
        ),
      );

      expect(
        sandbox.readCase('test/goldens/swatch'),
        containsPair('outcome', 'identical'),
      );
      expect(lines, isEmpty, reason: 'console: false still applies');
    });

    testWidgets('disables metrics the yaml enables', (tester) async {
      final sandbox = WorkspaceSandbox.create(_yaml);
      await tester.pumpWidget(const Swatch());
      await expectLater(
        Swatch.finder,
        sandbox.matcher(
          Swatch.golden,
          session: sandbox.session(metricsEnv: '0'),
        ),
      );

      expect(sandbox.recordedFiles, isEmpty);
    });

    testWidgets('an invalid value fails like a bad config', (tester) async {
      final sandbox = WorkspaceSandbox.create(_yaml);
      await tester.pumpWidget(const Swatch());
      final message = await sandbox
          .matcher(Swatch.golden, session: sandbox.session(metricsEnv: 'yes'))
          .matchAsync(Swatch.finder);

      expect(message, contains('GLEON_METRICS must be 1, 0, true or false'));
    });

    test('without a workspace warns once, only when requested', () {
      final session = GleonSession(workspace: null, metricsEnv: '1');

      expect(session.takeMissingWorkspaceWarning(), contains('gleon init'));
      expect(session.takeMissingWorkspaceWarning(), isNull);
      for (final value in ['0', 'false', ' ', null]) {
        expect(
          GleonSession(
            workspace: null,
            metricsEnv: value,
          ).takeMissingWorkspaceWarning(),
          isNull,
          reason: 'GLEON_METRICS=${value ?? '(unset)'}',
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
    'schema_version': 1,
    'source': {'tool': 'gleon_flutter', 'tool_version': '0.1.0'},
    'timings_ms': {'total': 1.5},
  };
  final schema = caseSchema;

  expect(schema?.validate(valid).isValid, isTrue);
  for (final broken in [
    {...valid, 'outcome': 'passed'},
    {...valid, 'name': 'Upper/Case'},
    {...valid, 'extra': 1},
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
