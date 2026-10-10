import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:gleon/gleon.dart';

import '../helpers/blob.dart';
import '../helpers/golden_updates.dart';
import '../helpers/swatch.dart';
import '../helpers/workspace_sandbox.dart';

/// A sandbox (a workspace with [yaml]) with [GleonFileComparator] installed
/// like `test/flutter_test_config.dart` would (with the sandbox's session).
WorkspaceSandbox _installed({String? yaml}) =>
    .create(yaml, installsGleonComparator: true);

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

  group('GleonFileComparator in a workspace', () {
    testWidgets("--update-goldens writes this platform's own golden", (
      tester,
    ) async {
      final sandbox = _installed(
        yaml:
            '''
required_version: ">=0.1.0"
fallback_platform: $foreignPlatform
screenshots:
  - include: "test/goldens/*.png"
''',
      );
      final shared = sandbox.goldenBytes(Swatch.golden);
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
      await withGoldenUpdates(
        () => expectLater(Swatch.finder, ft.matchesGoldenFile(Swatch.golden)),
      );

      expect(
        sandbox.goldenBytes('goldens/$hostPlatform/swatch.png'),
        isNotEmpty,
      );
      expect(
        // ignore: use-existing-variable, read again after the update.
        sandbox.goldenBytes(Swatch.golden),
        shared,
        reason: 'the shared golden is left alone',
      );
    });

    testWidgets("applies the golden rule's pixel options", (tester) async {
      String yaml(String diff) =>
          '''
required_version: ">=0.1.0"
screenshots:
  - include: "test/goldens/*.png"
    diff: $diff
''';
      final sandbox = _installed(yaml: yaml('{ threshold: 0.01 }'));
      // 611 of 9600 pixels differ, most of them anti-aliasing.
      await tester.pumpWidget(const Blob(offset: 0.3));
      expect(
        await ft.matchesGoldenFile(Blob.golden).matchAsync(Blob.finder),
        contains('(gleon pixel ≤ 1.00%)'),
      );

      sandbox.writeConfig(yaml('{ threshold: 0.01, anti_alias: true }'));
      await expectLater(Blob.finder, ft.matchesGoldenFile(Blob.golden));
    });
  });

  testWidgets('compares a ui.Image', (tester) async {
    _installed();
    Future<ui.Image> capture({Offset? dot}) async {
      await tester.pumpWidget(Swatch(dot: dot));
      final element =
          Swatch.finder.evaluate().singleOrNull ?? fail('no swatch');
      final image =
          await tester.runAsync(() => captureImage(element)) ??
          fail('no image captured');
      addTearDown(image.dispose);

      return image;
    }

    expect(
      await ft.matchesGoldenFile(Swatch.golden).matchAsync(await capture()),
      isNull,
    );
    expect(
      await ft
          .matchesGoldenFile(Swatch.golden)
          .matchAsync(await capture(dot: Swatch.dotOffset)),
      contains('gleon exact'),
    );
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
