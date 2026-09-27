import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'config.dart';
import 'native.dart';

/// A [GoldenFileComparator] that compares with the gleon engine while
/// delegating golden path resolution and `--update-goldens` writes to the
/// comparator it wraps (normally Flutter's [LocalFileComparator]), so golden
/// files live exactly where they would without this package.
class GleonGoldenComparator extends GoldenFileComparator {
  /// Wraps [delegate] and compares using [options].
  GleonGoldenComparator(this.delegate, this.options);

  /// The comparator that was installed before (owns paths and updates).
  final GoldenFileComparator delegate;

  /// Comparison options for this golden.
  final ResolvedGoldenOptions options;

  @override
  Uri getTestUri(Uri key, int? version) => delegate.getTestUri(key, version);

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      delegate.update(golden, imageBytes);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final local = delegate;
    if (local is! LocalFileComparator) {
      throw TestFailure(
        'gleon: matchesGoldenFile needs the default LocalFileComparator, but '
        'goldenFileComparator is ${local.runtimeType}. Custom comparators are '
        'not supported yet.',
      );
    }
    final goldenFile = File(
      path.join(path.fromUri(local.basedir), path.fromUri(golden.path)),
    );
    if (!goldenFile.existsSync()) {
      throw TestFailure(
        'Could not be compared against non-existent file: "$golden"',
      );
    }
    final goldenBytes = await goldenFile.readAsBytes();

    // Identical encodings are identical pixels: skip decoding entirely.
    if (_bytesEqual(goldenBytes, imageBytes)) {
      return true;
    }

    final result = compareNative(
      baseline: goldenBytes,
      candidate: imageBytes,
      options: options.toNativeJson(),
    );
    switch (result) {
      case NativeMatch():
        return true;
      case NativeError(:final message):
        throw TestFailure(
          'Golden "$golden": gleon could not compare: $message',
        );
      case NativeDimensionMismatch():
        final feedback = await _writeFailure(
          local.basedir,
          golden,
          goldenBytes,
          imageBytes,
          null,
        );
        throw TestFailure(
          'Golden "$golden": image sizes differ: golden is '
          '${result.baselineWidth}x${result.baselineHeight}px, test image is '
          '${result.candidateWidth}x${result.candidateHeight}px.$feedback',
        );
      case NativeMismatch():
        final feedback = await _writeFailure(
          local.basedir,
          golden,
          goldenBytes,
          imageBytes,
          result.diffPng,
        );
        throw TestFailure(
          'Golden "$golden": ${_describeMismatch(result)} '
          '(gleon ${options.describe()}).$feedback',
        );
    }
  }

  String _describeMismatch(NativeMismatch result) {
    final minSsim = result.minSsim;
    if (minSsim != null) {
      final region = result.region;
      final where = region == null
          ? ''
          : 'changed area at (${region.x}, ${region.y}) '
                '${region.width}x${region.height}px: ';
      final excess = result.maxExcess ?? 0;
      final color = excess > 0
          ? ', colors exceed the tolerance by up to '
                '${excess.toStringAsFixed(1)} (8-bit units)'
          : '';
      return '${where}min local SSIM ${minSsim.toStringAsFixed(4)}$color';
    }
    final diff = result.diffPixels ?? 0;
    final percent = (diff / result.totalPixels * 100).toStringAsFixed(2);
    return '$percent% ($diff of ${result.totalPixels}px) differ';
  }

  /// Writes Flutter-style failure artifacts next to the test and returns the
  /// message suffix pointing at them.
  Future<String> _writeFailure(
    Uri basedir,
    Uri golden,
    List<int> goldenBytes,
    List<int> testBytes,
    Uint8List? diffPng,
  ) async {
    final failuresDir = path.join(path.fromUri(basedir), 'failures');
    final fileName = golden.pathSegments.last;
    final testName = path.basenameWithoutExtension(fileName);
    Future<void> write(String suffix, List<int> bytes) async {
      final file = File(path.join(failuresDir, '${testName}_$suffix.png'));
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }

    await write('masterImage', goldenBytes);
    await write('testImage', testBytes);
    if (diffPng != null) {
      await write('gleonDiff', diffPng);
    }
    return '\nFailure feedback can be found at $failuresDir';
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
