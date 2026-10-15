import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/hook_failures.dart';
import 'package:gleon/src/core/hook/network_failure.dart';
import 'package:hooks/hooks.dart';

void main() {
  Matcher throwsHook<T extends HookError>(String message) =>
      throwsA(isA<T>().having((error) => error.message, 'message', message));

  test('a build that passes passes', () async {
    await expectLater(HookFailures.reporting(Future<void>.value), completes);
  });

  test('a network failure is an infrastructure error', () async {
    await expectLater(
      HookFailures.reporting(() => throw NetworkFailure('gleon: offline')),
      throwsHook<InfraError>('gleon: offline'),
    );
  });

  // Message → the build that fails with it.
  final failures = <String, HookBuild>{
    'gleon: ProcessException: not found\n  Command: cargo build': () =>
        throw const ProcessException('cargo', ['build'], 'not found'),
    'gleon: bad pin': () => throw const FormatException('bad pin'),
    'gleon: no version': () => throw StateError('gleon: no version'),
  };
  for (final MapEntry(key: message, value: build) in failures.entries) {
    test('every other failure is a build error: $message', () async {
      await expectLater(
        HookFailures.reporting(build),
        throwsHook<BuildError>(message),
      );
    });
  }
}
