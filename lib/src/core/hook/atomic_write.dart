import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// File writes that other processes never observe half-done.
///
/// Plain Dart (no Flutter imports): the build hook's library cache. The
/// matcher writes nothing itself; the native engine writes failure artifacts,
/// case reports and goldens.
abstract final class AtomicWrite {
  static final _random = Random.secure();

  /// Writes [bytes] to [file] via a unique temp file and a rename, so
  /// concurrent writers and readers never observe a partial file.
  ///
  /// Windows cannot replace a file another process has loaded. When the
  /// rename fails and [file] already exists, it is kept if its content has
  /// [expectedSha256] (by default the hash of [bytes]): a concurrent build
  /// stored the same verified bytes. Otherwise the error is rethrown, so a
  /// broken copy is never kept.
  static Future<void> bytes(
    File file,
    List<int> bytes, {
    String? expectedSha256,
  }) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.${pid}_${_random.nextInt(1 << 32)}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      // A leftover `.tmp` file is harmless; the rename failure matters.
      await temp.delete().catchError((_) => temp, test: _isFileSystemError);
      final expected = expectedSha256 ?? sha256.convert(bytes).toString();
      if (!await isKept(file, expectedSha256: expected)) rethrow;
    }
  }

  /// Whether an existing [file] that could not be replaced may stay: it has
  /// exactly the content of [expectedSha256]. An unreadable file is not
  /// kept, so the rename error is the one reported.
  @visibleForTesting
  static Future<bool> isKept(
    File file, {
    required String expectedSha256,
  }) async {
    if (!file.existsSync()) return false;
    try {
      return await sha256Of(file) == expectedSha256;
    } on FileSystemException {
      return false;
    }
  }

  static bool _isFileSystemError(Object error) => error is FileSystemException;

  /// Lowercase hex SHA-256 of the content of [file].
  static Future<String> sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;

    return digest.toString();
  }
}
