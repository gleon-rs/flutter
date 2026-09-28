import 'dart:io';

import 'package:gleon/gleon.dart';

import '../helpers/golden_sandbox.dart';
import '../helpers/swatch.dart';

void main() {
  GoldenSandbox.install();

  testWidgets('--update-goldens writes through Flutter paths incl. version', (
    tester,
  ) async {
    final written = File('${GoldenSandbox.dir.path}/goldens/tmp_update.2.png');
    addTearDown(() => autoUpdateGoldenFiles = false);
    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
    autoUpdateGoldenFiles = true;
    await expectLater(
      Swatch.finder,
      matchesGoldenFile(
        'goldens/tmp_update.png',
        version: 2,
        tolerance: const .ssim(),
      ),
    );
    autoUpdateGoldenFiles = false;

    expect(written.existsSync(), isTrue);
    expect(GoldenSandbox.failures.existsSync(), isFalse);
  });
}
