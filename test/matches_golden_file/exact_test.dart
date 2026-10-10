import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:gleon/gleon.dart';

import '../helpers/swatch.dart';
import '../helpers/workspace_sandbox.dart';

void main() {
  setUp(WorkspaceSandbox.withoutWorkspace);

  group('default (exact, same as Flutter)', () {
    testWidgets('passes for an identical render', (tester) async {
      await tester.pumpWidget(const Swatch());
      await expectLater(Swatch.finder, matchesGoldenFile(Swatch.golden));
    });

    testWidgets('accepts a Uri key', (tester) async {
      await tester.pumpWidget(const Swatch());
      await expectLater(
        Swatch.finder,
        matchesGoldenFile(Uri.parse(Swatch.golden)),
      );
    });

    testWidgets('fails on a single changed pixel and writes failure files', (
      tester,
    ) async {
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
      final message = await matchesGoldenFile(Swatch.golden)
          .matchAsync(Swatch.finder);

      expect(message, contains('1 of 6000px'));
      expect(message, contains('gleon exact'));
      expect(message, contains('Failure feedback can be found at'));
      for (final suffix in ['masterImage', 'testImage', 'gleonDiff']) {
        expect(
          File('${WorkspaceSandbox.current().failures.path}/swatch_$suffix.png')
              .existsSync(),
          isTrue,
          reason: suffix,
        );
      }
    });

    testWidgets('an omitted tolerance is exact', (tester) async {
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
      final message = await matchesGoldenFile(
        Swatch.golden,
        tolerance: const .exact(),
      ).matchAsync(Swatch.finder);

      expect(message, contains('gleon exact'));
    });

    testWidgets('reports a dimension mismatch', (tester) async {
      await tester.pumpWidget(const Swatch(size: Size(100, 61)));
      final message = await matchesGoldenFile(Swatch.golden)
          .matchAsync(Swatch.finder);

      expect(message, contains('golden is 100x60px'));
      expect(message, contains('test image is 100x61px'));
      expect(
        File('${WorkspaceSandbox.current().failures.path}/swatch_testImage.png')
            .existsSync(),
        isTrue,
      );
    });

    testWidgets('fails for a missing golden like Flutter does', (tester) async {
      await tester.pumpWidget(const Swatch());
      final message = await matchesGoldenFile('goldens/does_not_exist.png')
          .matchAsync(Swatch.finder);

      expect(message, contains('non-existent file'));
    });

    testWidgets('keeps Flutter matcher errors for bad finders', (tester) async {
      await tester.pumpWidget(const Swatch());
      final message = await matchesGoldenFile(Swatch.golden)
          .matchAsync(find.byKey(const ValueKey('nope')));

      expect(message, contains('no widget was found'));
    });

    testWidgets('passing tests write nothing', (tester) async {
      await tester.pumpWidget(const Swatch());
      await expectLater(Swatch.finder, matchesGoldenFile(Swatch.golden));

      expect(WorkspaceSandbox.current().failures.existsSync(), isFalse);
    });
  });

  testWidgets('custom comparators get an actionable error', (tester) async {
    // ignore: avoid-unnecessary-local-variable, captures the value to restore.
    final original = goldenFileComparator;
    addTearDown(() => goldenFileComparator = original);
    goldenFileComparator = _FakeComparator();
    await tester.pumpWidget(const Swatch());
    expect(
      await matchesGoldenFile(Swatch.golden).matchAsync(Swatch.finder),
      contains('needs a LocalFileComparator'),
    );
  });

  testWidgets("a LocalFileComparator subclass's own threshold never applies", (
    tester,
  ) async {
    // Like alchemist's or golden_screenshot's tolerant comparators: gleon
    // takes the golden directory and compares itself.
    goldenFileComparator = _TolerantComparator(
      WorkspaceSandbox.current().dir.uri.resolve('tolerant_test.dart'),
    );
    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));

    expect(
      await matchesGoldenFile(Swatch.golden).matchAsync(Swatch.finder),
      contains('gleon exact'),
    );
  });
}

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;
}

class _FakeComparator extends GoldenFileComparator {
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      fail('comparing fails before any update');
}
