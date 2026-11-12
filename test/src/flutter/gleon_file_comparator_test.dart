import 'dart:io';

// Flutter's own matchesGoldenFile: the matcher a golden harness calls.
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/flutter/gleon_file_comparator.dart';

import '../../helpers/golden_updates.dart';
import '../../helpers/png_origin.dart';
import '../../helpers/swatch.dart';
import '../../helpers/workspace_sandbox.dart';

// Installed like `test/flutter_test_config.dart` does, the comparator works in
// the session of the process (whose environment this package's tests leave
// empty); test/workspace/file_comparator_test.dart covers the rest with a
// session of each test's own.
void main() {
  /// A sandbox without a workspace, with its comparator as a
  /// [GleonFileComparator].
  WorkspaceSandbox installed() {
    final sandbox = WorkspaceSandbox.withoutWorkspace();
    goldenFileComparator = GleonFileComparator.fromExisting(
      goldenFileComparator,
    );

    return sandbox;
  }

  testWidgets('compares through the engine', (tester) async {
    installed();
    await tester.pumpWidget(const Swatch());
    await expectLater(Swatch.finder, matchesGoldenFile(Swatch.golden));

    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));
    // A mismatch also in a run with `--update-goldens`, which would rewrite
    // the golden instead.
    final message = await withGoldenUpdates<Object?>(
      () async =>
          await matchesGoldenFile(Swatch.golden).matchAsync(Swatch.finder),
      isUpdating: false,
    );
    expect(message, allOf(contains('1 of 6000px'), contains('gleon exact')));
  });

  testWidgets('writes goldens stamped with this platform', (tester) async {
    final sandbox = installed();
    const key = 'goldens/new.png';
    await tester.pumpWidget(const Swatch());

    await withGoldenUpdates(
      () => expectLater(Swatch.finder, matchesGoldenFile(key)),
    );
    final golden = File('${sandbox.dir.path}/$key');
    expect(PngOrigin.read(golden.readAsBytesSync()), hostPlatform);
    await expectLater(Swatch.finder, matchesGoldenFile(key));
  });
}
