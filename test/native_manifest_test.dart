import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/native.dart' show expectedAbiVersion;
import 'package:path/path.dart' as path;

/// Guards against shipping stale prebuilt libraries: rerun
/// `tool/build_native.sh` after changing `gleon-engine` or `gleon-ffi`.
void main() {
  // `flutter test` runs with the package root as the working directory.
  final packageRoot = Directory.current.path;
  final manifest =
      jsonDecode(
            File(
              path.join(packageRoot, 'native', 'manifest.json'),
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  test('prebuilt libraries implement the ABI this package expects', () {
    expect(manifest['abi_version'], expectedAbiVersion);
  });

  test('prebuilt libraries match their pinned checksums', () {
    final targets = manifest['targets']! as Map<String, Object?>;
    expect(
      targets.keys,
      containsAll(['macos-arm64', 'macos-x64', 'linux-x64']),
    );
    for (final MapEntry(:key, :value) in targets.entries) {
      final entry = value! as Map<String, Object?>;
      final file = File(
        path.join(packageRoot, 'native', entry['file']! as String),
      );
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        entry['sha256'],
        reason: key,
      );
    }
  });
}
