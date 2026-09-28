import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// File writes that other processes never observe half-done.
///
/// Plain Dart (no Flutter imports): shared by the build hook (library cache)
/// and the matcher (failure artifacts, later metrics).
abstract final class AtomicWrite {
  static final _random = Random.secure();

  /// Writes [bytes] to [file] via a unique temp file and a rename, so
  /// concurrent writers and readers never observe a partial file.
  ///
  /// Windows cannot replace a file another process has loaded. When the
  /// rename fails and [file] already exists, it is kept if [expectedSha256]
  /// is null or matches its content (a concurrent build stored the same
  /// verified bytes); otherwise the error is rethrown.
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
      if (!await isKept(file, expectedSha256: expectedSha256)) rethrow;
    }
  }

  /// Whether an existing [file] that could not be replaced may stay: it
  /// exists and, when [expectedSha256] is given, has exactly that content.
  @visibleForTesting
  static Future<bool> isKept(File file, {String? expectedSha256}) async =>
      file.existsSync() &&
      (expectedSha256 == null || await sha256Of(file) == expectedSha256);

  static bool _isFileSystemError(Object error) => error is FileSystemException;

  /// Lowercase hex SHA-256 of the content of [file].
  static Future<String> sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;

    return digest.toString();
  }
}
