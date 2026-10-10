import 'dart:ui' as ui;

import 'package:gleon/alchemist.dart';
import 'package:gleon/gleon.dart';
import 'package:gleon/src/flutter/alchemist_expectation.dart'
    show AlchemistExpectation;

import '../../helpers/caption.dart';
import '../../helpers/swatch.dart';
import '../../helpers/workspace_sandbox.dart';

/// The failure message of [expectation] for [actual] and [golden]; null for
/// a pass.
Future<String?> _failureOf(
  AlchemistGoldenExpectation expectation,
  Object actual,
  String golden,
) async {
  try {
    await expectation(actual, golden)();

    return null;
  } on TestFailure catch (error) {
    return error.message;
  }
}

/// The swatch as a capture the test owns, like alchemist's image of
/// obscured text ([dot]: with a changed pixel).
Future<ui.Image> _swatchImage(WidgetTester tester, {Offset? dot}) async {
  await tester.pumpWidget(Swatch(dot: dot));
  final element = Swatch.finder.evaluate().singleOrNull ?? fail('no swatch');
  final image =
      await tester.runAsync(() => captureImage(element)) ??
      fail('no image captured');
  addTearDown(image.dispose);

  return image;
}

/// Named like alchemist's comparator for a `diffThreshold` above 0, which
/// alchemist installs around each of those golden tests.
// ignore: avoid-top-level-members-in-tests, gleon matches alchemist's name.
class AlchemistFileComparator extends LocalFileComparator {
  AlchemistFileComparator(super.testFile);
}

void main() {
  setUpAll(loadAppFonts);
  setUp(WorkspaceSandbox.withoutWorkspace);

  // Alchemist passes the Finder of its root unless text is obscured: gleon
  // then compares with the boxes of the text, like its own matcher.
  testWidgets('a widget is compared with its text boxes', (tester) async {
    await tester.pumpWidget(const Caption(digits: '0123456780'));

    expect(
      await _failureOf(
        gleonAlchemistExpectation(),
        Caption.finder,
        Caption.golden,
      ),
      isNull,
      reason: 'text alone changed: ignored by default',
    );
    final compared = await _failureOf(
      gleonAlchemistExpectation(textTolerance: 0.1),
      Caption.finder,
      Caption.golden,
    );
    expect(compared, contains('": text up to'));
    expect(compared, isNot(contains('obscureText')));
  });

  testWidgets('the tolerance and ignore regions apply', (tester) async {
    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));

    expect(
      await _failureOf(
        gleonAlchemistExpectation(),
        Swatch.finder,
        Swatch.golden,
      ),
      contains('1 of 6000px'),
    );
    expect(
      await _failureOf(
        gleonAlchemistExpectation(tolerance: const .pixel(maxDiffRatio: 0.001)),
        Swatch.finder,
        Swatch.golden,
      ),
      isNull,
    );
    expect(
      await _failureOf(
        gleonAlchemistExpectation(
          ignoreRegions: [ui.Rect.fromLTWH(Swatch.dotOffset.dx, 10, 1, 1)],
        ),
        Swatch.finder,
        Swatch.golden,
      ),
      isNull,
    );
  });

  group('an image of obscured text', () {
    testWidgets('fails with the way to compare real text', (tester) async {
      final image = await _swatchImage(tester, dot: Swatch.dotOffset);
      final message = await _failureOf(
        gleonAlchemistExpectation(),
        Future.value(image),
        Swatch.golden,
      );

      expect(message, contains('1 of 6000px'));
      expect(message, contains('`obscureText: false`'));
      expect(message, contains('`PlatformGoldensConfig`'));
      expect(message, contains('record the goldens again'));
    });

    // Without a golden nothing was compared: the hint must not say so.
    testWidgets('missing its golden, claims no comparison', (tester) async {
      final image = await _swatchImage(tester);
      final message = await _failureOf(
        gleonAlchemistExpectation(),
        Future.value(image),
        'goldens/missing.png',
      );

      expect(message, contains('`obscureText: false`'));
      expect(message, isNot(contains('compared it')));
    });

    testWidgets('fails without it when silenced', (tester) async {
      final image = await _swatchImage(tester, dot: Swatch.dotOffset);
      final message = await _failureOf(
        gleonAlchemistExpectation(shouldHintObscuredText: false),
        Future.value(image),
        Swatch.golden,
      );

      expect(message, contains('1 of 6000px'));
      expect(message, isNot(contains('obscureText')));
    });

    testWidgets('passes silently', (tester) async {
      final image = await _swatchImage(tester);

      expect(
        await _failureOf(
          gleonAlchemistExpectation(),
          Future.value(image),
          Swatch.golden,
        ),
        isNull,
      );
    });
  });

  // Alchemist installs its comparator for a `diffThreshold` above 0; gleon
  // takes only its directory, so a failure says the threshold did not apply.
  testWidgets("a failure under alchemist's diffThreshold says it is ignored", (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.current();
    goldenFileComparator = AlchemistFileComparator(
      sandbox.dir.uri.resolve('alchemist_test.dart'),
    );
    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));

    final message = await _failureOf(
      gleonAlchemistExpectation(),
      Swatch.finder,
      Swatch.golden,
    );
    expect(message, contains('1 of 6000px'));
    expect(message, contains('`diffThreshold`'));

    await tester.pumpWidget(const Swatch());
    expect(
      await _failureOf(
        gleonAlchemistExpectation(),
        Swatch.finder,
        Swatch.golden,
      ),
      isNull,
    );
  });

  testWidgets('compares in the session it is given', (tester) async {
    final sandbox = WorkspaceSandbox.create('''
required_version: ">=0.1.0"
screenshots:
  - include: "test/goldens/*.png"
metrics:
  enabled: true
''');
    await tester.pumpWidget(const Swatch());

    final expectation = AlchemistExpectation.create(
      session: sandbox.session(runId: 'alchemist-1'),
    );
    expect(await _failureOf(expectation, Swatch.finder, Swatch.golden), isNull);
    expect(
      sandbox.readCase('test/goldens/swatch'),
      containsPair('run_id', 'alchemist-1'),
    );
  });

  test('refuses invalid values when created', () {
    expect(
      () => gleonAlchemistExpectation(textTolerance: 2),
      throwsArgumentError,
    );
    expect(
      () => gleonAlchemistExpectation(ignoreRegions: [ui.Rect.zero]),
      throwsArgumentError,
    );
  });
}
