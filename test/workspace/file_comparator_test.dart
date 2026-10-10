import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:gleon/gleon.dart';

import '../helpers/golden_updates.dart';
import '../helpers/swatch.dart';
import '../helpers/workspace_sandbox.dart';

/// A sandbox (a workspace with [yaml]) with [GleonFileComparator] installed
/// like `test/flutter_test_config.dart` would, on top of the sandbox's
/// comparator (restored by the sandbox's tear-down).
WorkspaceSandbox _installed({String? yaml}) {
  final sandbox = yaml == null
      ? WorkspaceSandbox.withoutWorkspace()
      : WorkspaceSandbox.create(yaml);
  goldenFileComparator = GleonFileComparator.fromExisting(goldenFileComparator);

  return sandbox;
}

void main() {
  group("flutter_test's matchesGoldenFile with GleonFileComparator", () {
    testWidgets('passes an identical render', (tester) async {
      _installed();
      await tester.pumpWidget(const Swatch());

      await expectLater(Swatch.finder, ft.matchesGoldenFile(Swatch.golden));
    });

    testWidgets('fails with the engine message and its failure files', (
      tester,
    ) async {
      final sandbox = _installed();
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
      final message = await ft
          .matchesGoldenFile(Swatch.golden)
          .matchAsync(Swatch.finder);

      expect(message, contains('1 of 6000px'));
      expect(message, contains('gleon exact'));
      expect(
        File('${sandbox.failures.path}/swatch_gleonDiff.png').existsSync(),
        isTrue,
      );
    });

    testWidgets('compares byte inputs', (tester) async {
      final sandbox = _installed();

      await expectLater(
        sandbox.goldenBytes(Swatch.golden),
        ft.matchesGoldenFile(Swatch.golden),
      );
    });

    testWidgets("applies the golden's yaml rule", (tester) async {
      _installed(
        yaml: '''
required_version: ">=0.1.0"
screenshots:
  - include: "test/goldens/*.png"
    diff: { threshold: 0.001 }
''',
      );
      // 1 of 6000 pixels: within 0.1%.
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));

      await expectLater(Swatch.finder, ft.matchesGoldenFile(Swatch.golden));
    });

    testWidgets('writes goldens with --update-goldens', (tester) async {
      final sandbox = _installed();
      await tester.pumpWidget(const Swatch());
      await withGoldenUpdates(
        () => expectLater(
          Swatch.finder,
          ft.matchesGoldenFile('goldens/new.png', version: 2),
        ),
      );

      expect(
        File('${sandbox.dir.path}/goldens/new.2.png').existsSync(),
        isTrue,
      );
      await expectLater(
        Swatch.finder,
        ft.matchesGoldenFile('goldens/new.png', version: 2),
      );
    });
  });

  group('GleonFileComparator.fromExisting', () {
    testWidgets('keeps the golden directory', (tester) async {
      final sandbox = WorkspaceSandbox.withoutWorkspace();
      final comparator = GleonFileComparator.fromExisting(goldenFileComparator);

      expect(comparator.basedir, sandbox.dir.uri);
    });

    test('refuses a comparator without a golden directory', () {
      expect(
        () => GleonFileComparator.fromExisting(_RemoteComparator()),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('_RemoteComparator'),
          ),
        ),
      );
    });
  });

  testWidgets("gleon's matcher works with it installed", (tester) async {
    _installed();
    await tester.pumpWidget(const Swatch());
    await expectLater(Swatch.finder, matchesGoldenFile(Swatch.golden));

    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
    final message = await matchesGoldenFile(Swatch.golden)
        .matchAsync(Swatch.finder);

    expect(message, contains('1 of 6000px'));
  });
}

class _RemoteComparator extends GoldenFileComparator {
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) =>
      fail('never compares');

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      fail('never updates');
}
