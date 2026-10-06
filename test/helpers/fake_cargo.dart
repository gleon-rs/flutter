import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/source_build.dart';

/// A cargo stand-in for [ProcessRunner]s: exits with [exitCode] and, on
/// success, writes the library of the requested target unless
/// [isWritingLibrary] is false. Fails the test when called unless
/// [isAllowed].
final class FakeCargo {
  /// A cargo that builds.
  FakeCargo({
    this.exitCode = 0,
    this.isWritingLibrary = true,
    this.isAllowed = true,
  });

  /// A cargo that fails the test when called.
  FakeCargo.never() : this(isAllowed: false);

  /// Exit code of every build.
  final int exitCode;

  /// Whether a successful build writes the library.
  final bool isWritingLibrary;

  /// Whether cargo may run at all.
  final bool isAllowed;

  /// Arguments of every call.
  final calls = <List<String>>[];

  /// Environment of every call.
  final environments = <Map<String, String>?>[];

  /// A [ProcessRunner].
  Future<ProcessResult> run(
    String _,
    List<String> arguments, {
    Map<String, String>? environment,
    // ignore: avoid-unused-parameters, part of the ProcessRunner signature.
    String? workingDirectory,
  }) {
    if (!isAllowed) fail('cargo must not run: $arguments');
    calls.add(arguments);
    environments.add(environment);
    String after(String flag) =>
        arguments
            .skipWhile((argument) => argument != flag)
            .skip(1)
            .firstOrNull ??
        fail('cargo was called without $flag');
    if (exitCode == 0 && isWritingLibrary) {
      final triple = after('--target');
      final built = NativeTarget.values.firstWhere(
        (target) => target.rustTriple == triple,
      );
      final library = '$triple/release/${built.libFileName}';
      File('${after('--target-dir')}/$library').createSync(recursive: true);
    }

    return .value(ProcessResult(1, exitCode, 'out', 'err'));
  }
}
