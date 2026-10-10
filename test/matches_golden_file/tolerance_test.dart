import 'dart:ui';

import 'package:gleon/gleon.dart';

import '../helpers/blob.dart';
import '../helpers/swatch.dart';
import '../helpers/workspace_sandbox.dart';

void main() {
  setUp(WorkspaceSandbox.withoutWorkspace);

  group('pixel', () {
    testWidgets('tolerates a small change', (tester) async {
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
      await expectLater(
        Swatch.finder,
        matchesGoldenFile(
          Swatch.golden,
          tolerance: const .pixel(maxDiffRatio: 0.001),
        ),
      );
    });

    testWidgets('still fails a large change', (tester) async {
      await tester.pumpWidget(const Swatch(accent: Color(0xFF4CAF50)));
      final message = await matchesGoldenFile(
        Swatch.golden,
        tolerance: const .pixel(),
      ).matchAsync(Swatch.finder);

      expect(message, contains('50.00%'));
      expect(message, contains('gleon pixel ≤ 1.00%'));
    });

    testWidgets('antiAlias takes most sub-pixel noise', (tester) async {
      await tester.pumpWidget(const Blob(offset: 0.3));
      // Bounds, not counts: rasterizers of other Flutter versions draw the
      // anti-aliasing a little differently (macOS today: 611 of 9600).
      final exact = await matchesGoldenFile(
        Blob.golden,
        tolerance: const .pixel(maxDiffRatio: 0),
      ).matchAsync(Blob.finder);
      final withAntiAlias = await matchesGoldenFile(
        Blob.golden,
        tolerance: const .pixel(maxDiffRatio: 0, antiAlias: true),
      ).matchAsync(Blob.finder);

      expect(_differing(exact), greaterThan(9600 * 0.04));
      expect(_differing(withAntiAlias), lessThan(_differing(exact) ~/ 4));
      await expectLater(
        Blob.finder,
        matchesGoldenFile(
          Blob.golden,
          tolerance: const .pixel(antiAlias: true),
        ),
      );
    });

    testWidgets('edgeThreshold hides edge differences only', (tester) async {
      await tester.pumpWidget(const Blob(offset: 0.3));
      final message = await matchesGoldenFile(
        Blob.golden,
        tolerance: const .pixel(maxDiffRatio: 0, edgeThreshold: 64),
      ).matchAsync(Blob.finder);

      // On macOS today 22 of 9600 are left, less than 1% of the frame.
      expect(_differing(message), lessThan(9600 * 0.01));
      expect(message, contains('(gleon pixel ≤ 0.00%, edges >64 ignored)'));
    });

    testWidgets('options never hide a dot on a flat area', (tester) async {
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
      final message = await matchesGoldenFile(
        Swatch.golden,
        tolerance: const .pixel(
          maxDiffRatio: 0,
          channelTolerance: 8,
          antiAlias: true,
          edgeThreshold: 64,
        ),
      ).matchAsync(Swatch.finder);

      expect(message, contains('(1 of 6000px)'));
    });

    testWidgets('channelTolerance takes a one-level drift', (tester) async {
      await tester.pumpWidget(const Swatch(accent: Color(0xFF2197F4)));
      expect(
        await matchesGoldenFile(
          Swatch.golden,
          tolerance: const .pixel(maxDiffRatio: 0),
        ).matchAsync(Swatch.finder),
        contains('differ'),
      );
      await expectLater(
        Swatch.finder,
        matchesGoldenFile(
          Swatch.golden,
          tolerance: const .pixel(maxDiffRatio: 0, channelTolerance: 1),
        ),
      );
    });
  });

  group('ssim', () {
    testWidgets('anti-aliased golden baseline', (tester) async {
      await tester.pumpWidget(const Blob());
      await expectLater(Blob.finder, matchesGoldenFile(Blob.golden));
    });

    testWidgets('exact fails on sub-pixel rendering noise', (tester) async {
      await tester.pumpWidget(const Blob(offset: 0.3));
      final message = await matchesGoldenFile(Blob.golden)
          .matchAsync(Blob.finder);

      expect(message, contains('differ'));
    });

    testWidgets('tolerates sub-pixel rendering noise', (tester) async {
      await tester.pumpWidget(const Blob(offset: 0.3));
      await expectLater(
        Blob.finder,
        matchesGoldenFile(Blob.golden, tolerance: const .ssim()),
      );
    });

    testWidgets('tolerates imperceptible color drift', (tester) async {
      await tester.pumpWidget(const Swatch(accent: Color(0xFF2197F4)));
      await expectLater(
        Swatch.finder,
        matchesGoldenFile(Swatch.golden, tolerance: const .ssim()),
      );
    });

    testWidgets('fails one saturated pixel on a flat area', (tester) async {
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
      final message = await matchesGoldenFile(
        Swatch.golden,
        tolerance: const .ssim(),
      ).matchAsync(Swatch.finder);

      expect(message, contains('changed area at (10, 10) 1x1px'));
      expect(message, contains('gleon ssim ≥ 0.800, color ±8'));
    });

    testWidgets('catches a flat color shift with similar luminance', (
      tester,
    ) async {
      await tester.pumpWidget(const Swatch(accent: Color(0xFF4CAF50)));
      final message = await matchesGoldenFile(
        Swatch.golden,
        tolerance: const .ssim(),
      ).matchAsync(Swatch.finder);

      expect(message, contains('changed area at (0, 0) 50x60px'));
    });

    testWidgets('reports the configured thresholds', (tester) async {
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
      final message = await matchesGoldenFile(
        Swatch.golden,
        tolerance: const .ssim(minSimilarity: 0.95, colorTolerance: 4),
      ).matchAsync(Swatch.finder);

      expect(message, contains('gleon ssim ≥ 0.950, color ±4'));
    });
  });

  group('ignoreRegions', () {
    testWidgets('hide a changed area', (tester) async {
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
      await expectLater(
        Swatch.finder,
        matchesGoldenFile(
          Swatch.golden,
          ignoreRegions: [
            Rect.fromLTWH(Swatch.dotOffset.dx, Swatch.dotOffset.dy, 1, 1),
          ],
        ),
      );
    });

    testWidgets('expand fractional rectangles to whole pixels', (tester) async {
      await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
      await expectLater(
        Swatch.finder,
        matchesGoldenFile(
          Swatch.golden,
          ignoreRegions: [const Rect.fromLTRB(10.5, 10.5, 10.6, 10.6)],
        ),
      );
    });
  });
}

/// The differing pixels a failure [message] names (`(611 of 9600px)`).
int _differing(String? message) {
  final failure = message ?? fail('the golden passed');
  final count = RegExp(r'\((\d+) of \d+px\)').firstMatch(failure)?.group(1);

  return int.parse(count ?? fail('no pixel count in $failure'));
}
