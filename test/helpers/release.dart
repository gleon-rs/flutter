import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_target.dart';

/// A release of one [library] for [target]; [throwsDownload] matches the
/// failures of downloading it.
abstract final class Release {
  /// The target of [library].
  static const NativeTarget target = .linuxX64;

  /// The library of the release.
  static final library = List<int>.generate(4096, (i) => i % 251);

  /// The sha256 of [library].
  static final hash = sha256.convert(library).toString();

  /// The checksum list of the release.
  static List<int> get sums => '$hash  ${target.assetName}\n'.codeUnits;
}

/// Hook errors are printed verbatim: every one names gleon first.
Matcher throwsDownload(Object message) => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    allOf(startsWith('gleon: '), message),
  ),
);
