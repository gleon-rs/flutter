import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gleon/gleon.dart';

import '../helpers/golden_updates.dart';
import '../helpers/prints.dart';
import '../helpers/swatch.dart';
import '../helpers/workspace_sandbox.dart';

void main() {
  setUp(WorkspaceSandbox.withoutWorkspace);

  /// The swatch as an image the test owns ([dot]: with a changed pixel).
  Future<ui.Image> swatch(WidgetTester tester, {Offset? dot}) async {
    await tester.pumpWidget(Swatch(dot: dot));
    final element = Swatch.finder.evaluate().singleOrNull ?? fail('no swatch');
    final image =
        await tester.runAsync(() => captureImage(element)) ??
        fail('no image captured');
    addTearDown(image.dispose);

    return image;
  }

  testWidgets('a ui.Image is compared and left to its owner', (tester) async {
    final image = await swatch(tester);

    expect(await matchesGoldenFile(Swatch.golden).matchAsync(image), isNull);
    expect(image.debugDisposed, isFalse);
  });

  testWidgets('a Future<ui.Image> is compared', (tester) async {
    await tester.pumpWidget(const Swatch());
    final capture = captureImage(
      Swatch.finder.evaluate().singleOrNull ?? fail('no swatch'),
    );

    expect(await matchesGoldenFile(Swatch.golden).matchAsync(capture), isNull);
    // Like a ui.Image, the captured image stays its owner's to dispose.
    final owned = await capture;
    expect(owned.debugDisposed, isFalse);
    owned.dispose();
  });

  testWidgets('an image may differ within the tolerance', (tester) async {
    final image = await swatch(tester, dot: Swatch.dotOffset);
    final matcher = matchesGoldenFile(
      Swatch.golden,
      tolerance: const .pixel(maxDiffRatio: 0.001),
    );

    expect(await matcher.matchAsync(image), isNull);
  });

  testWidgets('an image may differ in its ignore regions', (tester) async {
    final image = await swatch(tester, dot: Swatch.dotOffset);
    final matcher = matchesGoldenFile(
      Swatch.golden,
      ignoreRegions: [Swatch.dotOffset & const ui.Size.square(1)],
    );

    expect(await matcher.matchAsync(image), isNull);
  });

  testWidgets('a version names the golden of an image', (tester) async {
    final image = await swatch(tester);
    final matcher = matchesGoldenFile('goldens/versioned.png', version: 2);

    expect(await withGoldenUpdates(() => matcher.matchAsync(image)), isNull);
    expect(await matcher.matchAsync(image), isNull);
    final sandbox = '${WorkspaceSandbox.current.dir.path}/goldens';
    expect(File('$sandbox/versioned.2.png').existsSync(), isTrue);
    expect(File('$sandbox/versioned.png').existsSync(), isFalse);
  });

  testWidgets('a custom comparator fails images, never throws', (tester) async {
    final image = await swatch(tester);
    // ignore: avoid-unnecessary-local-variable, captures the value to restore.
    final original = goldenFileComparator;
    addTearDown(() => goldenFileComparator = original);
    final custom = _CustomComparator();
    goldenFileComparator = custom;
    final matcher = matchesGoldenFile(Swatch.golden);

    for (final input in <Object>[image, Future.value(image)]) {
      expect(
        await matcher.matchAsync(input),
        contains('needs the default LocalFileComparator'),
      );
      expect(
        await withGoldenUpdates(() => matcher.matchAsync(input)),
        contains('needs the default LocalFileComparator'),
      );
    }
    expect(custom.calls, isEmpty);
  });

  testWidgets('a changed pixel fails with the failure images', (tester) async {
    final image = await swatch(tester, dot: Swatch.dotOffset);

    expect(
      await matchesGoldenFile(Swatch.golden).matchAsync(image),
      contains('1 of 6000px'),
    );
    expect(
      File('${WorkspaceSandbox.current.failures.path}/swatch_testImage.png')
          .existsSync(),
      isTrue,
    );
  });

  testWidgets('--update-goldens writes the image', (tester) async {
    final image = await swatch(tester, dot: Swatch.dotOffset);
    final matcher = matchesGoldenFile('goldens/tmp_update.png');

    expect(await withGoldenUpdates(() => matcher.matchAsync(image)), isNull);
    expect(await matcher.matchAsync(image), isNull);
  });

  testWidgets('a text tolerance has no text to apply to', (tester) async {
    final image = await swatch(tester);
    final matcher = matchesGoldenFile(Swatch.golden, textTolerance: 0.1);
    final messages = <String?>[];
    final lines = await capturePrints(
      () async => messages.add(await matcher.matchAsync(image)),
    );

    expect(messages, [null]);
    expect(
      lines,
      contains(contains('the text tolerance of golden "goldens/swatch.png"')),
    );
  });
}

/// A comparator other than Flutter's [LocalFileComparator] that records
/// every call; a match must never reach it.
final class _CustomComparator extends GoldenFileComparator {
  final calls = <String>[];

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    calls.add('compare $golden');

    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async =>
      calls.add('update $golden');
}
