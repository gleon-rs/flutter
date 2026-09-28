import 'dart:async';
import 'dart:io';

import 'package:gleon/gleon.dart';

import '../helpers/golden_sandbox.dart';
import '../helpers/swatch.dart';

void main() {
  GoldenSandbox.install();

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
