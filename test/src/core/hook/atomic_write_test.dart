import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/atomic_write.dart';

void main() {
  Directory? temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('gleon_atomic_'));
  tearDown(() => temp?.deleteSync(recursive: true));

  File fileIn(String name) => .new('${(temp ?? .systemTemp).path}/$name');

  /// The failure of a write to a [_FullDisk].
  final throwsWriteFailure = throwsA(
    isA<FileSystemException>().having(
      (error) => error.message,
      'message',
      _FullDisk.message,
    ),
  );

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

  // A disk that fills up: the temp file is written part way.
  test(
    'a failed write is reported and deletes its partial temp file',
    () async {
      final file = fileIn('data.bin')..writeAsBytesSync(const [9, 8]);

      await expectLater(
        IOOverrides.runWithIOOverrides(
          () => AtomicWrite.bytes(file, const [1, 2, 3, 4]),
          _FullDisk(),
        ),
        throwsWriteFailure,
      );
      expect(file.readAsBytesSync(), [9, 8]);
      expect(
        file.parent.listSync().map(
          (entity) => entity.uri.pathSegments.lastOrNull,
        ),
        ['data.bin'],
      );
    },
  );

  // Windows: a virus scanner may hold the partial temp file.
  test('a temp file that cannot be deleted leaves the write error', () async {
    final file = fileIn('data.bin');

    await expectLater(
      IOOverrides.runWithIOOverrides(
        () => AtomicWrite.bytes(file, const [1, 2, 3, 4]),
        _FullDisk(isLocked: true),
      ),
      throwsWriteFailure,
    );
    expect(file.existsSync(), isFalse);
  });

  test(
    'a file that cannot be replaced is kept only with the expected content',
    () async {
      final file = fileIn('loaded.dll')..writeAsBytesSync(const [7]);
      final hash = sha256.convert(const [7]).toString();

      expect(await AtomicWrite.isKept(file, expectedSha256: hash), isTrue);
      expect(await AtomicWrite.isKept(file, expectedSha256: '0' * 64), isFalse);
      expect(
        await AtomicWrite.isKept(fileIn('missing.dll'), expectedSha256: hash),
        isFalse,
      );
    },
  );

  test(
    'an unreadable file is not kept, so the rename error surfaces',
    () async {
      final file = fileIn('locked.dll')..writeAsBytesSync(const [7]);
      Process.runSync('chmod', ['000', file.path]);
      addTearDown(() => Process.runSync('chmod', ['644', file.path]));
      final hash = sha256.convert(const [7]).toString();
      bool isReadable;
      try {
        await AtomicWrite.sha256Of(file);
        isReadable = true;
      } on FileSystemException {
        isReadable = false;
      }

      expect(
        await AtomicWrite.isKept(file, expectedSha256: hash),
        isReadable, // Root reads it anyway.
      );
    },
    skip: Platform.isWindows ? 'no chmod on Windows' : null,
  );
}

/// A disk that fills up while a temp file (`*.tmp`) is written: half of its
/// bytes land, then the write fails. When [isLocked], deleting it fails too.
final class _FullDisk extends IOOverrides {
  new({this.isLocked = false});

  /// The message of a failed write.
  static const message = 'No space left on device';

  /// Whether the temp file cannot be deleted.
  final bool isLocked;

  @override
  File createFile(String path) {
    final file = super.createFile(path);

    return path.endsWith('.tmp')
        ? _PartialWrite(file, isLocked: isLocked)
        : file;
  }
}

/// A temp [_file] on a [_FullDisk].
final class _PartialWrite extends Fake implements File {
  new(this._file, {required this.isLocked});

  /// Whether [delete] fails.
  final bool isLocked;

  final File _file;

  @override
  String get path => _file.path;

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = .write,
    bool flush = false,
  }) async {
    await _file.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2), flush: flush);

    throw FileSystemException(_FullDisk.message, path);
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) => isLocked
      ? .error(FileSystemException('locked', path))
      : _file.delete(recursive: recursive);
}
