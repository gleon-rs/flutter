import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gleon/gleon.dart';
import 'package:path/path.dart' as path;

const _swatchKey = ValueKey('swatch');
const _golden = 'goldens/swatch.png';
const _dot = Offset(10, 10);

/// Deterministic, text-free widget: solid rectangles on integer coordinates
/// render identically regardless of font rasterization.
Widget _swatch({
  Size size = const Size(100, 60),
  Offset? dot,
  Color accent = const Color(0xFF2196F3),
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: _swatchKey,
      child: CustomPaint(
        size: size,
        painter: _SwatchPainter(dot: dot, accent: accent),
      ),
    ),
  ),
);

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.dot, required this.accent});

  final Offset? dot;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF))
      ..drawRect(
        Rect.fromLTWH(0, 0, size.width / 2, size.height),
        Paint()..color = accent,
      )
      ..drawRect(
        Rect.fromLTWH(size.width * 2 / 3, 0, size.width / 3, size.height),
        Paint()..color = const Color(0xFFFF5722),
      );
    if (dot case final dot?) {
      canvas.drawRect(
        Rect.fromLTWH(dot.dx, dot.dy, 1, 1),
        Paint()..color = const Color(0xFF000000),
      );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter oldDelegate) =>
      oldDelegate.dot != dot || oldDelegate.accent != accent;
}

const _blobKey = ValueKey('blob');
const _blobGolden = 'goldens/blob.png';

/// Anti-aliased content (circle and thin strokes) drawn at a sub-pixel
/// [offset], emulating rasterization noise between machines.
Widget _blob({double offset = 0}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: _blobKey,
      child: CustomPaint(
        size: const Size(120, 80),
        painter: _BlobPainter(offset),
      ),
    ),
  ),
);

class _BlobPainter extends CustomPainter {
  const _BlobPainter(this.offset);

  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF))
      ..drawCircle(
        Offset(30 + offset, 40 + offset),
        18.5,
        Paint()..color = const Color(0xFF9C27B0),
      );
    final stroke = Paint()
      ..color = const Color(0xFF212121)
      ..strokeWidth = 1.4;
    for (var i = 0; i < 8; i++) {
      final x = 62.3 + i * 6.1 + offset;
      canvas.drawLine(Offset(x, 28 + offset), Offset(x, 52 + offset), stroke);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) => oldDelegate.offset != offset;
}

/// Directory of this test file (the `LocalFileComparator` basedir).
String get _testDir =>
    path.fromUri((goldenFileComparator as LocalFileComparator).basedir);

String get _failuresDir => path.join(_testDir, 'failures');

void main() {
  tearDown(() {
    gleonGoldenDefaults = const GleonGoldenConfig();
    final failures = Directory(_failuresDir);
    if (failures.existsSync()) {
      failures.deleteSync(recursive: true);
    }
  });

  group('default (exact, same as Flutter)', () {
    testWidgets('passes for an identical render', (tester) async {
      await tester.pumpWidget(_swatch());
      await expectLater(find.byKey(_swatchKey), matchesGoldenFile(_golden));
    });

    testWidgets('accepts a Uri key', (tester) async {
      await tester.pumpWidget(_swatch());
      await expectLater(
        find.byKey(_swatchKey),
        matchesGoldenFile(Uri.parse(_golden)),
      );
    });

    testWidgets('fails on a single changed pixel and writes failure files', (
      tester,
    ) async {
      await tester.pumpWidget(_swatch(dot: _dot));
      final message = await matchesGoldenFile(_golden)
          .matchAsync(find.byKey(_swatchKey));

      expect(message, contains('1 of 6000px'));
      expect(message, contains('gleon exact'));
      expect(message, contains('Failure feedback can be found at'));
      for (final suffix in ['masterImage', 'testImage', 'gleonDiff']) {
        expect(
          File(path.join(_failuresDir, 'swatch_$suffix.png')).existsSync(),
          isTrue,
          reason: suffix,
        );
      }
    });

    testWidgets('reports a dimension mismatch', (tester) async {
      await tester.pumpWidget(_swatch(size: const Size(100, 61)));
      final message = await matchesGoldenFile(_golden)
          .matchAsync(find.byKey(_swatchKey));
      expect(message, contains('100x60px'));
      expect(message, contains('100x61px'));
    });

    testWidgets('fails for a missing golden like Flutter does', (tester) async {
      await tester.pumpWidget(_swatch());
      final message = await matchesGoldenFile('goldens/does_not_exist.png')
          .matchAsync(find.byKey(_swatchKey));
      expect(message, contains('non-existent file'));
    });

    testWidgets('keeps Flutter matcher errors for bad finders', (tester) async {
      await tester.pumpWidget(_swatch());
      final message = await matchesGoldenFile(_golden)
          .matchAsync(find.byKey(const ValueKey('nope')));
      expect(message, contains('no widget was found'));
    });
  });

  group('tolerance', () {
    testWidgets('pixel threshold tolerates a small change', (tester) async {
      await tester.pumpWidget(_swatch(dot: _dot));
      await expectLater(
        find.byKey(_swatchKey),
        matchesGoldenFile(_golden, mode: GoldenMode.pixel, threshold: 0.001),
      );
    });

    testWidgets('pixel threshold still fails a large change', (tester) async {
      await tester.pumpWidget(_swatch(accent: const Color(0xFF4CAF50)));
      final message = await matchesGoldenFile(
        _golden,
        mode: GoldenMode.pixel,
        threshold: 0.01,
      ).matchAsync(find.byKey(_swatchKey));
      expect(message, contains('50.00%'));
      expect(message, contains('gleon pixel ≤ 1.00%'));
    });

    testWidgets('anti-aliased golden baseline', (tester) async {
      await tester.pumpWidget(_blob());
      await expectLater(find.byKey(_blobKey), matchesGoldenFile(_blobGolden));
    });

    testWidgets('exact fails on sub-pixel rendering noise', (tester) async {
      await tester.pumpWidget(_blob(offset: 0.3));
      final message = await matchesGoldenFile(_blobGolden)
          .matchAsync(find.byKey(_blobKey));
      expect(message, contains('differ'));
    });

    testWidgets('ssim tolerates sub-pixel rendering noise', (tester) async {
      await tester.pumpWidget(_blob(offset: 0.3));
      await expectLater(
        find.byKey(_blobKey),
        matchesGoldenFile(_blobGolden, mode: GoldenMode.ssim),
      );
    });

    testWidgets('ssim tolerates imperceptible color drift', (tester) async {
      await tester.pumpWidget(_swatch(accent: const Color(0xFF2197F4)));
      await expectLater(
        find.byKey(_swatchKey),
        matchesGoldenFile(_golden, mode: GoldenMode.ssim),
      );
    });

    testWidgets('ssim fails a single saturated pixel on a flat area', (
      tester,
    ) async {
      await tester.pumpWidget(_swatch(dot: _dot));
      final message = await matchesGoldenFile(
        _golden,
        mode: GoldenMode.ssim,
      ).matchAsync(find.byKey(_swatchKey));
      expect(message, contains('changed area at (10, 10) 1x1px'));
      expect(message, contains('gleon ssim ≥ 0.800, color ±8'));
    });

    testWidgets('ssim catches a flat color shift with similar luminance', (
      tester,
    ) async {
      await tester.pumpWidget(_swatch(accent: const Color(0xFF4CAF50)));
      final message = await matchesGoldenFile(
        _golden,
        mode: GoldenMode.ssim,
      ).matchAsync(find.byKey(_swatchKey));
      expect(message, contains('changed area at (0, 0) 50x60px'));
    });

    testWidgets('ignoreRegions hides a changed area', (tester) async {
      await tester.pumpWidget(_swatch(dot: _dot));
      await expectLater(
        find.byKey(_swatchKey),
        matchesGoldenFile(
          _golden,
          ignoreRegions: [Rect.fromLTWH(_dot.dx, _dot.dy, 1, 1)],
        ),
      );
    });

    testWidgets('suite-wide defaults apply when no argument is passed', (
      tester,
    ) async {
      gleonGoldenDefaults = const GleonGoldenConfig(
        mode: GoldenMode.pixel,
        threshold: 0.001,
      );
      await tester.pumpWidget(_swatch(dot: _dot));
      await expectLater(find.byKey(_swatchKey), matchesGoldenFile(_golden));
    });
  });

  group('byte inputs', () {
    testWidgets('matches List<int> of the golden itself', (tester) async {
      final bytes = File(path.join(_testDir, _golden)).readAsBytesSync();
      await tester.runAsync(() async {
        await expectLater(bytes, matchesGoldenFile(_golden));
      });
    });

    testWidgets('reports corrupt bytes as an error, not a pass', (
      tester,
    ) async {
      final message = await tester.runAsync(
        () =>
            matchesGoldenFile(_golden)
                .matchAsync(Uint8List.fromList(List.filled(64, 7))),
      );
      expect(message, contains('gleon could not compare'));
    });
  });

  group('update', () {
    testWidgets('--update-goldens writes through Flutter paths incl. version', (
      tester,
    ) async {
      final written = File(path.join(_testDir, 'goldens', 'tmp_update.2.png'));
      addTearDown(() {
        autoUpdateGoldenFiles = false;
        if (written.existsSync()) written.deleteSync();
      });
      await tester.pumpWidget(_swatch(dot: _dot));
      autoUpdateGoldenFiles = true;
      await expectLater(
        find.byKey(_swatchKey),
        matchesGoldenFile('goldens/tmp_update.png', version: 2),
      );
      autoUpdateGoldenFiles = false;
      expect(written.existsSync(), isTrue);
    });
  });

  group('argument validation', () {
    test('rejects a parameter that does not apply to the mode', () {
      expect(
        () => matchesGoldenFile(_golden, mode: GoldenMode.ssim, threshold: 0.1),
        throwsArgumentError,
      );
      expect(
        () => matchesGoldenFile(_golden, minSimilarity: 0.9),
        throwsArgumentError,
      );
      expect(
        () => matchesGoldenFile(_golden, colorTolerance: 4),
        throwsArgumentError,
      );
    });

    test('rejects out-of-range values and bad regions', () {
      expect(
        () =>
            matchesGoldenFile(_golden, mode: GoldenMode.pixel, threshold: 1.5),
        throwsArgumentError,
      );
      expect(
        () => matchesGoldenFile(
          _golden,
          ignoreRegions: [const Rect.fromLTWH(-1, 0, 5, 5)],
        ),
        throwsArgumentError,
      );
    });

    test('validates only the settings the resolved mode uses', () {
      final original = gleonGoldenDefaults;
      addTearDown(() => gleonGoldenDefaults = original);
      gleonGoldenDefaults = const GleonGoldenConfig(
        threshold: 1.5,
        minSimilarity: 2,
        colorTolerance: -1,
      );
      expect(() => matchesGoldenFile(_golden), returnsNormally);
      expect(
        () => matchesGoldenFile(_golden, mode: GoldenMode.pixel),
        throwsArgumentError,
      );
      expect(
        () => matchesGoldenFile(_golden, mode: GoldenMode.ssim),
        throwsArgumentError,
      );
      expect(
        () => matchesGoldenFile(
          _golden,
          mode: GoldenMode.ssim,
          minSimilarity: 0.9,
          colorTolerance: 8,
        ),
        returnsNormally,
      );
    });

    test('rejects unsupported key types like Flutter', () {
      expect(() => matchesGoldenFile(42), throwsArgumentError);
    });
  });

  testWidgets('custom comparators get an actionable error', (tester) async {
    final original = goldenFileComparator;
    addTearDown(() => goldenFileComparator = original);
    goldenFileComparator = _FakeComparator();
    await tester.pumpWidget(_swatch());
    final message = await matchesGoldenFile(_golden)
        .matchAsync(find.byKey(_swatchKey));
    expect(message, contains('needs the default LocalFileComparator'));
  });
}

class _FakeComparator extends GoldenFileComparator {
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {}
}
