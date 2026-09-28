import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/io/atomic_write.dart';

void main() {
  Directory? temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('gleon_atomic_'));
  tearDown(() => temp?.deleteSync(recursive: true));

  File fileIn(String name) => .new('${(temp ?? .systemTemp).path}/$name');

  test('creates missing parent directories', () async {
    final file = fileIn('a/b/c.bin');
    await AtomicWrite.bytes(file, const [1, 2, 3]);

    expect(file.readAsBytesSync(), [1, 2, 3]);
  });

  test('replaces existing content and leaves no temp files', () async {
    final file = fileIn('data.bin')..writeAsBytesSync(const [9, 8]);
    await AtomicWrite.bytes(file, const [4, 5]);

    expect(file.readAsBytesSync(), [4, 5]);
    // Only the file itself (compared by name: Windows lists `\` separators).
    expect(
      file.parent.listSync().map(
        (entity) => entity.uri.pathSegments.lastOrNull,
      ),
      ['data.bin'],
    );
  });

  test('concurrent writers never leave a partial file', () async {
    final file = fileIn('shared.bin');
    final payload = List<int>.generate(1 << 16, (i) => i % 256);
    await Future.wait([
      for (int i = 0; i < 8; i += 1) AtomicWrite.bytes(file, payload),
    ]);

    expect(file.readAsBytesSync(), payload);
    expect(file.parent.listSync(), hasLength(1));
  });

  test('hashes file content as lowercase hex SHA-256', () async {
    final file = fileIn('hash.bin')..writeAsBytesSync(const [1, 2, 3]);

    expect(
      await AtomicWrite.sha256Of(file),
      sha256.convert(const [1, 2, 3]).toString(),
    );
  });

  test('a failed rename is reported and leaves no temp file', () async {
    // A non-empty directory where the file should go: every OS refuses to
    // rename a file over it.
    final blocked = fileIn('blocked');
    Directory('${blocked.path}/child').createSync(recursive: true);

    await expectLater(
      AtomicWrite.bytes(blocked, const [1]),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      blocked.parent.listSync().map((entity) => entity.path),
      isNot(anyElement(endsWith('.tmp'))),
    );
  });

  test(
    'a file that cannot be replaced is kept only with the expected content',
    () async {
      final file = fileIn('loaded.dll')..writeAsBytesSync(const [7]);
      final hash = sha256.convert(const [7]).toString();

      expect(await AtomicWrite.isKept(file), isTrue);
      expect(await AtomicWrite.isKept(file, expectedSha256: hash), isTrue);
      expect(await AtomicWrite.isKept(file, expectedSha256: '0' * 64), isFalse);
      expect(await AtomicWrite.isKept(fileIn('missing.dll')), isFalse);
    },
  );
}
