import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:gleon/gleon.dart';

import '../helpers/png.dart';
import '../helpers/swatch.dart';
import '../helpers/workspace_sandbox.dart';

const _yaml = '''
required_version: ">=0.1.0"
screenshots:
  - include: "test/goldens/**/*.png"
    mode: ssim
metrics:
  enabled: true
  console: false
''';

const _withoutMetrics = '''
required_version: ">=0.1.0"
screenshots:
  - include: "test/goldens/*.png"
artifacts: .gleon/runs/kept
''';

/// Flutter's failure file of the swatch golden for each gleon image.
const _flutterFailures = {
  'candidate': 'swatch_testImage.png',
  'diff': 'swatch_gleonDiff.png',
  'golden': 'swatch_masterImage.png',
};

void main() {
  testWidgets('a mismatch keeps the failure images too', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch(accent: Color(0xFF4CAF50)));
    await sandbox.matcher(Swatch.golden).matchAsync(Swatch.finder);
    final report = sandbox.readCase('test/goldens/swatch');
    final artifacts = report['artifacts'];

    // A widget is compared as raw pixels; its PNG is encoded for a failure.
    expect(report['candidate'], containsPair('sha256', hasLength(64)));

    // The images of this platform: `<dir>/<platform>/<name>/`.
    const dir = '.gleon/runs/latest/artifacts';
    expect(artifacts, {
      'candidate': '$dir/$hostPlatform/test/goldens/swatch/candidate.png',
      'diff': '$dir/$hostPlatform/test/goldens/swatch/diff.png',
      'golden': '$dir/$hostPlatform/test/goldens/swatch/golden.png',
    });
    for (final MapEntry(key: kind, value: failure)
        in _flutterFailures.entries) {
      final path = artifacts is Map ? artifacts[kind] : null;
      expect(
        File('${sandbox.root.path}/$path').readAsBytesSync(),
        File('${sandbox.root.path}/test/failures/$failure').readAsBytesSync(),
        reason: kind,
      );
    }
  });

  testWidgets('a pass compares raw pixels, encodes nothing', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch());
    await expectLater(Swatch.finder, sandbox.matcher(Swatch.golden));
    final report = sandbox.readCase('test/goldens/swatch');

    expect(report, containsPair('outcome', 'match'));
    expect(report['candidate'], {'height': 60, 'width': 100});
    expect(report.containsKey('artifacts'), isFalse);
  });

  testWidgets('a pass removes earlier failure images', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch(accent: Color(0xFF4CAF50)));
    await sandbox.matcher(Swatch.golden).matchAsync(Swatch.finder);
    final kept = sandbox.artifactsOf('test/goldens/swatch');

    expect(kept.listSync(), hasLength(3));
    await tester.pumpWidget(const Swatch());
    await expectLater(Swatch.finder, sandbox.matcher(Swatch.golden));

    expect(kept.listSync(), isEmpty);
  });

  testWidgets('a dimension mismatch keeps a diff of both', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch(size: Size(100, 61)));
    await sandbox.matcher(Swatch.golden).matchAsync(Swatch.finder);

    expect(sandbox.readCase('test/goldens/swatch')['artifacts'], {
      'candidate': endsWith('/test/goldens/swatch/candidate.png'),
      'diff': endsWith('/test/goldens/swatch/diff.png'),
      'golden': endsWith('/test/goldens/swatch/golden.png'),
    });
    final diff = decodeRgbaPng(
      File('${sandbox.failures.path}/swatch_gleonDiff.png').readAsBytesSync(),
    );
    expect((diff.width, diff.height), (100, 61));
    final golden = decodeRgbaPng(sandbox.goldenBytes(Swatch.golden));
    // The area both cover: equal pixels are the darkened golden.
    expect(_pixel(diff, 0, 0), _darkened(_pixel(golden, 0, 0)));
    // Row 60, the candidate's alone: green stripes where (x + y) % 8 < 4.
    expect(_pixel(diff, 4, 60), [0, 200, 83, 255]);
  });

  testWidgets('a mismatch diff marks the changed pixel', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
    await sandbox
        .matcher(Swatch.golden, tolerance: const .exact())
        .matchAsync(Swatch.finder);

    final diff = decodeRgbaPng(
      File('${sandbox.failures.path}/swatch_gleonDiff.png').readAsBytesSync(),
    );
    final golden = decodeRgbaPng(sandbox.goldenBytes(Swatch.golden));
    expect(_pixel(diff, 10, 10), [255, 0, 255, 255]);
    expect(_pixel(diff, 90, 30), _darkened(_pixel(golden, 90, 30)));
  });

  testWidgets('a missing golden keeps its candidate for gleon approve', (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch());
    await sandbox.matcher('goldens/new/swatch.png').matchAsync(Swatch.finder);

    expect(sandbox.readCase('test/goldens/new/swatch')['artifacts'], {
      'candidate': endsWith('/test/goldens/new/swatch/candidate.png'),
    });
    expect(
      Directory('${sandbox.root.path}/test/failures').existsSync(),
      isFalse,
      reason: "Flutter's comparator writes nothing for a missing golden",
    );
  });

  // Without metrics a failure is still recorded, for `gleon report` and
  // `gleon approve`; passes are not, and a fix removes the failure's report.
  testWidgets('failures are kept without metrics, where artifacts: says', (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.create(_withoutMetrics);
    await tester.pumpWidget(const Swatch(accent: Color(0xFF4CAF50)));
    final failure = await sandbox
        .matcher(Swatch.golden)
        .matchAsync(Swatch.finder);
    final kept = Directory(
      '${sandbox.root.path}/.gleon/runs/kept/$hostPlatform/test/goldens/swatch',
    );

    expect(failure, contains('Failure feedback can be found at'));
    expect(kept.listSync(), hasLength(3));
    final report = sandbox.readCase('test/goldens/swatch');
    expect(report, containsPair('outcome', 'mismatch'));
    expect(
      report['artifacts'],
      containsPair(
        'candidate',
        '.gleon/runs/kept/$hostPlatform/test/goldens/swatch/candidate.png',
      ),
    );

    await tester.pumpWidget(const Swatch());
    final fixed = await sandbox
        .matcher(Swatch.golden)
        .matchAsync(Swatch.finder);

    expect(fixed, isNull);
    expect(sandbox.hasCase('test/goldens/swatch'), isFalse);
    expect(kept.listSync(), isEmpty);
  });

  group('GLEON_ARTIFACTS_DIR and GLEON_RUN_ID', () {
    testWidgets('move the images and name the run', (tester) async {
      final sandbox = WorkspaceSandbox.create(_yaml);
      await tester.pumpWidget(const Swatch(accent: Color(0xFF4CAF50)));
      await sandbox
          .matcher(
            Swatch.golden,
            session: sandbox.session(
              artifactsDir: '.gleon/runs/ram',
              runId: '12345-2',
            ),
          )
          .matchAsync(Swatch.finder);
      final report = sandbox.readCase('test/goldens/swatch');

      expect(report, containsPair('run_id', '12345-2'));
      expect(
        report['artifacts'],
        containsPair(
          'diff',
          '.gleon/runs/ram/$hostPlatform/test/goldens/swatch/diff.png',
        ),
      );
      expect(sandbox.artifactsOf('test/goldens/swatch').existsSync(), isFalse);
    });

    testWidgets('invalid values fail every golden as config errors', (
      tester,
    ) async {
      final sandbox = WorkspaceSandbox.create(_yaml);
      await tester.pumpWidget(const Swatch());
      for (final (session, text) in [
        (
          sandbox.session(artifactsDir: 'build/out'),
          "GLEON_ARTIFACTS_DIR: 'build/out' must be "
              '`.gleon/runs/latest/artifacts`',
        ),
        (sandbox.session(runId: 'run 1'), 'GLEON_RUN_ID: a run id must be'),
      ]) {
        final message = await sandbox
            .matcher(Swatch.golden, session: session)
            .matchAsync(Swatch.finder);

        expect(message, allOf(startsWith('gleon: '), contains(text)));
        expect(message, isNot(contains('bug')), reason: 'a config error');
      }
    });
  });
}

/// The RGBA bytes at ([x], [y]) of a decoded PNG.
List<int> _pixel(
  ({int height, Uint8List rgba, int width}) image,
  int x,
  int y,
) {
  final start = (y * image.width + x) * 4;

  return image.rgba.sublist(start, start + 4);
}

/// [pixel] as gleon's pixel diff draws the unchanged golden: color halved,
/// alpha kept.
List<int> _darkened(List<int> pixel) => [
  ...pixel.take(3).map((channel) => channel ~/ 2),
  ...pixel.skip(3),
];
