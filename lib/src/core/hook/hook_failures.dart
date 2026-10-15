import 'dart:io';

import 'package:hooks/hooks.dart';

import 'network_failure.dart';

/// The work of a build hook.
typedef HookBuild = Future<void> Function();

/// How the build hook reports its failures.
abstract final class HookFailures {
  /// Runs [build] and reports its failures the way `package:hooks` expects:
  /// as [HookError]s, so a consumer sees the actionable message rather than
  /// an unhandled exception, and the hooks runner learns the kind of
  /// failure. A download the network failed ([NetworkFailure]) is an
  /// [InfraError] (it may pass when tried again); every other failure is a
  /// [BuildError].
  static Future<void> reporting(HookBuild build) async {
    try {
      await build();
      // ignore: avoid_catching_errors, the hook fails with actionable errors.
    } on NetworkFailure catch (error, stackTrace) {
      Error.throwWithStackTrace(InfraError(message: error.message), stackTrace);
      // ignore: avoid_catching_errors, the hook fails with actionable errors.
    } on StateError catch (error, stackTrace) {
      Error.throwWithStackTrace(BuildError(message: error.message), stackTrace);
    } on FormatException catch (exception, stackTrace) {
      Error.throwWithStackTrace(
        BuildError(message: 'gleon: ${exception.message}'),
        stackTrace,
      );
    } on ProcessException catch (exception, stackTrace) {
      Error.throwWithStackTrace(
        BuildError(message: 'gleon: $exception'),
        stackTrace,
      );
    }
  }
}
