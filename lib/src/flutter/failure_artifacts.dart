import 'dart:io';
import 'dart:typed_data';

import '../core/io/atomic_write.dart';

/// Flutter-style failure output of a golden comparison.
abstract final class FailureArtifacts {
  /// Writes `failures/<name>_masterImage.png`, `_testImage.png` and, when
  /// present, `_gleonDiff.png` under [basedir] (the directory of the test
  /// file, like Flutter's `LocalFileComparator`) and returns the message
  /// suffix pointing at them.
  static Future<String> write({
    required Uri basedir,
    required Uri golden,
    required Uint8List goldenBytes,
    required Uint8List testBytes,
    Uint8List? diffPng,
  }) async {
    final failuresDir = basedir.resolve('failures/');
    final fileName = golden.pathSegments.lastOrNull ?? 'golden';
    // Without the extension, e.g. `swatch` for `goldens/swatch.png`.
    final testName =
        RegExp(r'^(.+?)(?:\.[^.]*)?$').firstMatch(fileName)?.group(1) ??
        fileName;
    final files = {
      'gleonDiff': ?diffPng,
      'masterImage': goldenBytes,
      'testImage': testBytes,
    };
    for (final MapEntry(key: suffix, value: bytes) in files.entries) {
      await AtomicWrite.bytes(
        File.fromUri(failuresDir.resolve('${testName}_$suffix.png')),
        bytes,
      );
    }

    return '\nFailure feedback can be found at '
        '${Directory.fromUri(failuresDir).path}';
  }
}
