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

  test('a failing concurrent match leaves the others intact', () async {
    final bytes = File('${GoldenSandbox.dir.path}/${Swatch.golden}')
        .readAsBytesSync();
    final before = goldenFileComparator;
    final [intact, failed, alsoIntact] = await Future.wait([
      matchesGoldenFile(Swatch.golden).matchAsync(bytes),
      matchesGoldenFile(Swatch.golden)
          .matchAsync(Uint8List.fromList(List.filled(64, 7))),
      matchesGoldenFile(
        Swatch.golden,
        tolerance: const .pixel(),
      ).matchAsync(bytes),
    ]);

    expect(intact, isNull);
    expect(failed, contains('gleon could not compare'));
    expect(alsoIntact, isNull);
    expect(goldenFileComparator, same(before));
  });

  test('an abandoned match gives the comparator back when its test ends', () {
    final before = goldenFileComparator;
    // Tear-downs run last in, first out: this one runs after the match's.
    addTearDown(() => expect(goldenFileComparator, same(before)));
    // Like a match of a timed-out test: it never reaches its `finally`.
    unawaited(
      matchesGoldenFile(Swatch.golden)
          .matchAsync(Completer<List<int>>().future),
    );

    expect(goldenFileComparator, isNot(same(before)));
  });

  // Would hang until the test times out if the abandoned turn were kept.
  test('a match after an abandoned one does not wait for it', () async {
    final bytes = File('${GoldenSandbox.dir.path}/${Swatch.golden}')
        .readAsBytesSync();

    await expectLater(bytes, matchesGoldenFile(Swatch.golden));
  });

  test('keys with spaces and nested folders resolve like Flutter', () async {
    final golden = File(
      '${GoldenSandbox.dir.path}/goldens/nested dir/swatch copy.png',
    )..parent.createSync(recursive: true);
    File('${GoldenSandbox.dir.path}/${Swatch.golden}').copySync(golden.path);
    final bytes = golden.readAsBytesSync();

    await expectLater(
      bytes,
      matchesGoldenFile('goldens/nested dir/swatch copy.png'),
    );
    await expectLater(
      bytes,
      matchesGoldenFile('goldens/nested%20dir/swatch%20copy.png'),
    );
  });

  test('a match outside any test zone still works', () async {
    final bytes = File('${GoldenSandbox.dir.path}/${Swatch.golden}')
        .readAsBytesSync();
    final matcher = matchesGoldenFile(Swatch.golden);

    expect(await Zone.root.run(() => matcher.matchAsync(bytes)), isNull);
  });
}
