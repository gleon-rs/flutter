import 'dart:convert';
import 'dart:io';

import 'package:gleon/src/core/hook/atomic_write.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/source_build.dart';

/// Installs local builds of the `gleon-ffi` library and reads the gleon
/// checkout they come from (`bin/build_native.dart`).
///
/// Plain Dart (no Flutter imports): maintainer tooling, tested directly.
abstract final class NativeBuild {
  /// The commit of a checkout.
  static const _gitHead = ['rev-parse', 'HEAD'];

  /// `git status` of the library inputs; untracked inputs count even where
  /// `status.showUntrackedFiles` hides them.
  static const _gitStatus = ['status', '--porcelain', '--untracked-files=all'];

  /// Copies the built [library] of [target] into `native/<target>/` of
  /// [packageRoot], stamps it with the commit it was [builtFrom], then
  /// copies it into [dist] (if given) under its release asset name, which
  /// no hook reads. Returns the copies.
  ///
  /// Every file is replaced atomically. An old stamp is removed first and
  /// the new one written only after the library, so a library replaced by an
  /// interrupted build is never accepted under a stamp.
  static Future<List<File>> install(
    File library,
    NativeTarget target, {
    required Uri packageRoot,
    required String builtFrom,
    String? dist,
  }) async {
    final bytes = await library.readAsBytes();
    final targetDir = packageRoot.resolve('native/${target.key}/');
    final stamp = File.fromUri(targetDir.resolve(NativeTarget.pinFileName));
    if (stamp.existsSync()) await stamp.delete();
    final installed = File.fromUri(targetDir.resolve(target.libFileName));
    await AtomicWrite.bytes(installed, bytes);
    await AtomicWrite.bytes(stamp, utf8.encode('$builtFrom\n'));
    if (dist == null) return [installed];
    final asset = File.fromUri(
      Directory(dist).absolute.uri.resolve(target.assetName),
    );
    await AtomicWrite.bytes(asset, bytes);

    return [installed, asset];
  }

  /// The commit of the gleon checkout at [repo] and whether the inputs of
  /// the library ([SourceBuild.inputPaths]) have uncommitted or untracked
  /// changes (anything else in the checkout does not matter), or null when
  /// git cannot tell (no git, not a checkout, a checkout git refuses to
  /// read). [runProcess] runs git.
  static Future<({String commit, bool isDirty})?> checkoutState(
    Uri repo, {
    ProcessRunner runProcess = Process.run,
  }) async {
    final directory = repo.toFilePath();
    final statusArguments = [
      ..._gitStatus,
      '--',
      ...SourceBuild.inputPaths(repo),
    ];
    final ProcessResult head;
    final ProcessResult status;
    try {
      head = await runProcess('git', _gitHead, workingDirectory: directory);
      status = await runProcess(
        'git',
        statusArguments,
        workingDirectory: directory,
      );
    } on ProcessException {
      return null;
    }
    if (head.exitCode != 0 || status.exitCode != 0) return null;

    return (
      commit: head.stdout.toString().trim(),
      isDirty: status.stdout.toString().trim().isNotEmpty,
    );
  }
}
