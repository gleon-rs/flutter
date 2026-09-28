import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:gleon/gleon.dart';

import '../helpers/golden_sandbox.dart';
import '../helpers/swatch.dart';

void main() {
  GoldenSandbox.install();

  testWidgets('matches List<int> of the golden itself', (tester) async {
    final bytes = File('${GoldenSandbox.dir.path}/${Swatch.golden}')
        .readAsBytesSync();
    await tester.runAsync(
      () => expectLater(bytes, matchesGoldenFile(Swatch.golden)),
    );
  });

  testWidgets('reports corrupt bytes as an error, not a pass', (tester) async {
    final message = await tester.runAsync(
      () =>
          matchesGoldenFile(Swatch.golden)
              .matchAsync(Uint8List.fromList(List.filled(64, 7))),
    );

    expect(message, contains('gleon could not compare'));
  });

  // Finder inputs cannot overlap (Flutter forbids concurrent `runAsync`), but
  // byte inputs can: each match must still use its own tolerance.
  test('concurrent byte matches do not interfere', () async {
    final bytes = File('${GoldenSandbox.dir.path}/${Swatch.golden}')
        .readAsBytesSync();

    await Future.wait([
      expectLater(bytes, matchesGoldenFile(Swatch.golden)),
      expectLater(
        bytes,
        matchesGoldenFile(Swatch.golden, tolerance: const .ssim()),
      ),
      expectLater(
        bytes,
        matchesGoldenFile(Swatch.golden, tolerance: const .pixel()),
      ),
    ]);
  });

  test('a match outside any test zone still works', () async {
    final bytes = File('${GoldenSandbox.dir.path}/${Swatch.golden}')
        .readAsBytesSync();
    final matcher = matchesGoldenFile(Swatch.golden);

    expect(await Zone.root.run(() => matcher.matchAsync(bytes)), isNull);
  });
}
