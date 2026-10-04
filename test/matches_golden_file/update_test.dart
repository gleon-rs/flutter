import 'dart:io';

import 'package:gleon/gleon.dart';

import '../helpers/golden_sandbox.dart';
import '../helpers/golden_updates.dart';
import '../helpers/swatch.dart';

void main() {
  GoldenSandbox.install();

  testWidgets('--update-goldens writes through Flutter paths incl. version', (
    tester,
  ) async {
    final written = File('${GoldenSandbox.dir.path}/goldens/tmp_update.2.png');
    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
    await withGoldenUpdates(
      () => expectLater(
        Swatch.finder,
        matchesGoldenFile(
          'goldens/tmp_update.png',
          version: 2,
          tolerance: const .ssim(),
        ),
      ),
    );

    expect(written.existsSync(), isTrue);
    expect(GoldenSandbox.failures.existsSync(), isFalse);
  });
}
