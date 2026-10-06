import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:gleon/gleon.dart';

import '../helpers/golden_sandbox.dart';
import '../helpers/golden_updates.dart';
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

  test('a match never replaces goldenFileComparator', () async {
    final before = goldenFileComparator;
    final bytes = Completer<List<int>>();
    final pending = matchesGoldenFile(Swatch.golden).matchAsync(bytes.future);

    expect(goldenFileComparator, same(before));
    bytes.complete(
      File('${GoldenSandbox.dir.path}/${Swatch.golden}').readAsBytesSync(),
    );
    expect(await pending, isNull);
  });

  // Like a match abandoned by a timed-out test that goes on during the next
  // test, which installed another comparator and runs with --update-goldens.
  test('a late match keeps its own comparator and update flag', () async {
    final golden = File('${GoldenSandbox.dir.path}/${Swatch.golden}');
    final original = golden.readAsBytesSync();
    final bytes = Completer<List<int>>();
    final pending = matchesGoldenFile(Swatch.golden).matchAsync(bytes.future);
    final spy = _SpyComparator();
    goldenFileComparator = spy;
    // ignore: avoid-unnecessary-local-variable, restored after the test.
    final wasUpdating = autoUpdateGoldenFiles;
    addTearDown(() => autoUpdateGoldenFiles = wasUpdating);
    autoUpdateGoldenFiles = true;
    // Another image than the golden: compared, it fails; written, it would
    // replace the golden.
    bytes.complete(
      File('${GoldenSandbox.source}/caption.png').readAsBytesSync(),
    );

    expect(await pending, isNotNull);
    expect(spy.calls, isEmpty);
    final after = await golden.readAsBytes();
    expect(after, original);
  });

  test('a byte update that fails is the failure message', () async {
    final bytes = File('${GoldenSandbox.dir.path}/${Swatch.golden}')
        .readAsBytesSync();
    goldenFileComparator = _SpyComparator();

    final message = await withGoldenUpdates(
      () => matchesGoldenFile(Swatch.golden).matchAsync(bytes),
    );
    expect(message, contains('needs the default LocalFileComparator'));
  });

  test('other inputs fail like Flutter', () async {
    for (final input in <Object?>['goldens/swatch.png', null]) {
      await expectLater(
        matchesGoldenFile(Swatch.golden).matchAsync(input),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            contains('must provide a Finder, Image'),
          ),
        ),
      );
    }
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

/// Records every call; a match must never reach it.
final class _SpyComparator extends GoldenFileComparator {
  final calls = <String>[];

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    calls.add('compare $golden');

    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async =>
      calls.add('update $golden');
}
