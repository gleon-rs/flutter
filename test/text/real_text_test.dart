import 'dart:typed_data';

// ignore: migrate_design_widgets, the text field to test is Material's.
import 'package:flutter/material.dart';
import 'package:gleon/gleon.dart';
import 'package:gleon/src/core/compare/pixel_region.dart';
import 'package:gleon/src/flutter/text_regions.dart';

import '../helpers/caption.dart';
import '../helpers/workspace_sandbox.dart';

// A golden with real fonts, recorded on macOS, passes on every OS of CI: by
// default text never fails (OSes rasterize glyphs differently), everything else
// is exact. That is a trade-off: changes of text alone pass, unless a
// `textTolerance` compares text (for goldens of one OS).
void main() {
  setUpAll(loadAppFonts);
  setUp(WorkspaceSandbox.withoutWorkspace);
  final field = TextEditingController(text: 'Field ǺÅÉ gq');
  tearDownAll(field.dispose);

  testWidgets('the golden recorded on macOS passes', (tester) async {
    await tester.pumpWidget(const Caption());
    await expectLater(Caption.finder, matchesGoldenFile(Caption.golden));
  });

  testWidgets('text regions hug the text and skip the shapes', (tester) async {
    await tester.pumpWidget(const Caption());
    final regions = TextRegions.captured(tester.element(Caption.finder));
    bool isCovered(Offset point) =>
        regions.any((region) => _rect(region).contains(point));

    // The heading, three lines of the paragraph, the digits.
    expect(regions, hasLength(5));
    for (final region in regions) {
      expect(_rect(region), _within(const .fromLTWH(0, 0, 240, 160)));
    }
    expect(isCovered(const Offset(100, 15)), isFalse, reason: 'the bar');
    expect(isCovered(const Offset(20, 120)), isFalse, reason: 'the square');
    expect(isCovered(const Offset(220, 120)), isFalse, reason: 'beside text');
    expect(isCovered(const Offset(14, 34)), isTrue, reason: 'the heading');
  });

  // Changes of layout fail on the pixels around the text, whatever the text
  // tolerance.
  for (final (name, mutation) in [
    ('a bolder weight', const Caption(weight: .w700)),
    ('a paragraph moved by 1px', const Caption(shift: 1)),
  ]) {
    testWidgets('fails for $name', (tester) async {
      await tester.pumpWidget(mutation);
      final message = await matchesGoldenFile(Caption.golden)
          .matchAsync(Caption.finder);

      expect(message, contains('(gleon exact, text ignored)'));
    });
  }

  // Changes of text alone keep the layout: by default they pass (the
  // trade-off), with a text tolerance they fail on the text alone.
  for (final (name, mutation) in [
    ('a digit of the same width', const Caption(digits: '0123456780')),
    ('one word in a paragraph', const Caption(paragraph: _cancel)),
    ('a lighter text color', const Caption(color: .new(0xFF444444))),
    ('a frame tight around text', const Caption(hasFrame: true)),
  ]) {
    testWidgets('passes by default, fails a text tolerance for $name', (
      tester,
    ) async {
      await tester.pumpWidget(mutation);
      final byDefault = await matchesGoldenFile(Caption.golden)
          .matchAsync(Caption.finder);
      final compared = await matchesGoldenFile(
        Caption.golden,
        textTolerance: 0.1,
      ).matchAsync(Caption.finder);

      expect(byDefault, isNull);
      // Only text failed: the reason names no other pixels.
      expect(compared, contains('": text up to'));
    });

    // SSIM judges text by the same tiles and leaves it out of both gates.
    testWidgets('ssim: passes by default, fails a text tolerance for $name', (
      tester,
    ) async {
      await tester.pumpWidget(mutation);
      final byDefault = await matchesGoldenFile(
        Caption.golden,
        tolerance: const .ssim(),
      ).matchAsync(Caption.finder);
      final compared = await matchesGoldenFile(
        Caption.golden,
        tolerance: const .ssim(),
        textTolerance: 0.1,
      ).matchAsync(Caption.finder);

      expect(byDefault, isNull);
      expect(compared, contains('": text up to'));
      expect(compared, contains('text ≤ 10.00% per tile'));
    });
  }

  // Glyph ink reaching beyond the boxes of its line must stay in the text
  // regions: outside them every pixel is compared exactly, and other OSes
  // rasterize that ink differently.
  for (final (name, text) in [
    ('diacritics', const Text(_inky, style: _roboto)),
    (
      'negative letter spacing',
      Text(_inky, style: _roboto.copyWith(letterSpacing: -3)),
    ),
    (
      'outlined text',
      Text(
        _inky,
        style: TextStyle(
          fontSize: 28,
          foreground: Paint()
            ..style = .stroke
            ..strokeWidth = 4,
          fontFamily: 'Roboto',
        ),
      ),
    ),
    // The ellipsis is drawn by the paragraph, not a character of the text.
    (
      'an ellipsis',
      const SizedBox(
        width: 90,
        child: Text(
          'Ellipsis everywhere',
          style: _roboto,
          overflow: .ellipsis,
          maxLines: 1,
        ),
      ),
    ),
    // A text field paints its text at an offset (padding, centering).
    (
      'a text field',
      Material(
        color: const Color(0xFFFFFFFF),
        child: SizedBox(
          width: 300,
          child: TextField(
            controller: field,
            decoration: const InputDecoration(
              contentPadding: .symmetric(vertical: 12),
              border: .none,
            ),
            style: _roboto,
            autofillHints: null,
          ),
        ),
      ),
    ),
  ]) {
    testWidgets('text regions cover the ink of $name', (tester) async {
      const key = ValueKey('ink');
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: .topLeft,
            child: RepaintBoundary(
              key: key,
              child: Container(
                alignment: .topLeft,
                padding: const .all(20),
                color: const Color(0xFFFFFFFF),
                width: 360,
                height: 100,
                child: text,
              ),
            ),
          ),
        ),
      );
      final element = tester.element(find.byKey(key));
      final regions = TextRegions.captured(element);
      final (:height, :pixels, :width) = await _rawPixels(tester, element);
      final inkOutside = [
        for (int y = 0; y < height; y += 1)
          for (int x = 0; x < width; x += 1)
            if (pixels.getUint32((y * width + x) * 4) != _white &&
                !regions.any(
                  (region) => _rect(region).contains(.new(x + 0.5, y + 0.5)),
                ))
              (x, y),
      ];

      expect(inkOutside, isEmpty);
    });
  }
}

/// Text with ink beyond the boxes of its line.
const _inky = 'ǺÅÉ ÿ fjord Wylf gq';

const _roboto = TextStyle(
  color: Color(0xFF000000),
  fontSize: 28,
  fontFamily: 'Roboto',
);

/// Opaque white as the big-endian RGBA word of a pixel.
const _white = 0xFFFFFFFF;

/// The raw straight RGBA pixels of the image `captureImage` takes of
/// [element].
Future<_Pixels> _rawPixels(WidgetTester tester, Element element) async =>
    await tester.runAsync(() => _capture(element)) ?? fail('no capture');

Future<_Pixels> _capture(Element element) async {
  final image = await captureImage(element);
  try {
    final pixels = await image.toByteData(format: .rawStraightRgba);

    return (
      height: image.height,
      pixels: pixels ?? fail('no pixels'),
      width: image.width,
    );
  } finally {
    image.dispose();
  }
}

typedef _Pixels = ({int height, ByteData pixels, int width});

const _cancel =
    'Press Cancel to send the form, the quick brown fox jumps over the '
    'lazy dog; Cancel keeps your draft.';

Rect _rect(PixelRegion region) {
  final PixelRegion(:height, :width, :x, :y) = region;

  return .fromLTWH(
    x.toDouble(),
    y.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );
}

Matcher _within(Rect bounds) =>
    predicate<Rect>((rect) => bounds.intersect(rect) == rect, 'within $bounds');
