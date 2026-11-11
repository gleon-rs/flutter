import 'dart:io';
import 'dart:typed_data';

import 'package:gleon/gleon.dart';

import '../helpers/golden_updates.dart';
import '../helpers/workspace_sandbox.dart';

/// A 4097x4096 PNG (2 KB): one column over the largest image `ssim` compares,
/// 4096x4096 (16,777,216 pixels).
// ignore: avoid-explicit-type-declaration, not obvious from the initializer.
final Uint8List _overBudget = File('test/fixtures/ssim_budget_4097x4096.png')
    .readAsBytesSync();

const _golden = 'goldens/over_budget.png';

void main() {
  setUp(WorkspaceSandbox.withoutWorkspace);

  File golden() => .new('${WorkspaceSandbox.current().dir.path}/$_golden');

  test('--update-goldens records no ssim golden over the budget', () async {
    final message = await withGoldenUpdates(
      () => matchesGoldenFile(
        _golden,
        tolerance: const .ssim(),
      ).matchAsync(_overBudget),
    );

    expect(message, contains('gleon cannot record it'));
    expect(message, contains('4097x4096 exceeds the SSIM analysis budget'));
    expect(golden().existsSync(), isFalse);
  });

  test('a refused ssim update keeps the golden that is there', () async {
    final before = File('$goldenSource/swatch.png').readAsBytesSync();
    golden()
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(before);

    final message = await withGoldenUpdates(
      () => matchesGoldenFile(
        _golden,
        tolerance: const .ssim(),
      ).matchAsync(_overBudget),
    );

    expect(message, contains('gleon cannot record it'));
    expect(golden().readAsBytesSync(), before);
  });

  test(
    'an ssim golden over the budget is not comparable, even identical',
    () async {
      golden().writeAsBytesSync(_overBudget);

      final ssim = await matchesGoldenFile(
        _golden,
        tolerance: const .ssim(),
      ).matchAsync(_overBudget);
      expect(ssim, contains('gleon could not compare'));
      expect(ssim, contains('4097x4096 exceeds the SSIM analysis budget'));
      // Other tolerances have no budget.
      for (final tolerance in const [
        GoldenTolerance.exact(),
        GoldenTolerance.pixel(maxDiffRatio: 0),
      ]) {
        expect(
          await matchesGoldenFile(
            _golden,
            tolerance: tolerance,
          ).matchAsync(_overBudget),
          isNull,
          reason: '$tolerance',
        );
      }
    },
  );
}
