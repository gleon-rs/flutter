import 'dart:io';
import 'dart:ui' as ui;

import 'package:gleon/gleon.dart';

import '../helpers/golden_sandbox.dart';
import '../helpers/golden_updates.dart';
import '../helpers/prints.dart';
import '../helpers/swatch.dart';

void main() {
  GoldenSandbox.install();

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
  });

  testWidgets('a changed pixel fails with the failure images', (tester) async {
    final image = await swatch(tester, dot: Swatch.dotOffset);

    expect(
      await matchesGoldenFile(Swatch.golden).matchAsync(image),
      contains('1 of 6000px'),
    );
    expect(
      File('${GoldenSandbox.failures.path}/swatch_testImage.png').existsSync(),
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
