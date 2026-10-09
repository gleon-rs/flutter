import 'dart:io';

import 'package:gleon/gleon.dart';

import '../helpers/golden_updates.dart';
import '../helpers/swatch.dart';
import '../helpers/workspace_sandbox.dart';

void main() {
  setUp(WorkspaceSandbox.withoutWorkspace);

  testWidgets('--update-goldens writes through Flutter paths incl. version', (
    tester,
  ) async {
    final written = File(
      '${WorkspaceSandbox.current.dir.path}/goldens/tmp_update.2.png',
    );
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
    expect(WorkspaceSandbox.current.failures.existsSync(), isFalse);
  });
}
