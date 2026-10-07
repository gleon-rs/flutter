/// Writes `NATIVE_LICENSES.md`: the licenses of everything statically linked
/// into the `gleon-ffi` library this package ships, for every target, at the
/// gleon commit `native/gleon_ref` pins.
///
/// ```sh
/// dart bin/native_licenses.dart [--gleon-repo <dir>] [--commit <sha>] [--check]
/// ```
///
/// The crates come from `cargo tree` of `gleon-ffi` per target (normal
/// dependencies, no proc-macros or build scripts: only what ends up in the
/// library), their licenses from `cargo metadata` and the license files in
/// each crate (see `LicenseCrate` in `src/license_crate.dart`). A crate
/// without license files must offer a license that needs no notice (Zlib,
/// Unlicense, 0BSD, CC0-1.0, BSL-1.0 or MIT-0). The Rust standard library is
/// listed too. `--check` fails when the file is stale (CI); run without it
/// after moving `native/gleon_ref`.
///
/// The file names the pinned commit it was generated for, and the gleon repo
/// must be at that commit: its `git rev-parse HEAD`, or for a tree without
/// git (`git archive <pin> | tar -x -C <dir>`, which leaves the sibling
/// checkout alone) the `--commit` the tree was exported from. So `--check`
/// fails after a pin move until the file is regenerated.
///
/// Run it with plain `dart` (see `build_native.dart`); needs cargo and the
/// gleon repo's toolchain. Only `dart:*`, this package and `src/` may be
/// imported here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:gleon/src/core/hook/native_target.dart';

import 'src/cli.dart';
import 'src/license_crate.dart';
import 'src/native_build.dart';
import 'src/native_licenses.dart';

const _cli = Cli('native_licenses', r'''
Usage: dart bin/native_licenses.dart [options]

  --gleon-repo <dir>  gleon checkout (default: $GLEON_REPO, else ../gleon).
  --commit <sha>      the commit a gleon tree without git was exported from
                      (e.g. by `git archive`); a git checkout's own HEAD is
                      used otherwise.
  --check             fail if NATIVE_LICENSES.md is not up to date.
  -h, --help          show this help.
''');

const _outputName = 'NATIVE_LICENSES.md';

Future<void> main(List<String> args) async {
  final (:commit, :isCheck, :repo) = _parse(args);
  final packageRoot = await _cli.packageRoot();
  final gleon = Directory(
    repo ??
        Platform.environment['GLEON_REPO'] ??
        packageRoot.resolve('../gleon').toFilePath(),
  ).absolute;
  final pin = await File.fromUri(
    packageRoot.resolve('native/${NativeTarget.pinFileName}'),
  ).readAsString();
  final gleonCommit = await _commitOf(gleon, given: commit);
  if (gleonCommit != pin.trim()) {
    _cli.fail(
      '${gleon.path} is at $gleonCommit, but native/'
      '${NativeTarget.pinFileName} pins ${pin.trim()}: check out the pinned '
      'commit, or pass --gleon-repo with a tree of it.',
    );
  }
  final licenses = NativeLicenses(
    await _linked(gleon),
    gleonCommit: gleonCommit,
  );
  if (licenses.unlicensed case final missing when missing.isNotEmpty) {
    _cli.fail(
      'no license files, and no license that needs no notice, in: '
      '${missing.join(', ')}. Add their texts by hand to this script.',
    );
  }
  final content = licenses.markdown;
  final output = File.fromUri(packageRoot.resolve(_outputName));
  if (!isCheck) {
    await output.writeAsString(content);
    stdout.writeln('${output.path}: gleon $gleonCommit.');

    return;
  }
  final current = output.existsSync() ? await output.readAsString() : null;
  if (current != content) {
    _cli.fail(
      '$_outputName is not up to date with the crates of gleon-ffi at '
      '$gleonCommit: run `dart bin/native_licenses.dart` and commit the '
      'result.',
    );
  }
  stdout.writeln('$_outputName is up to date (gleon $gleonCommit).');
}

({String? commit, bool isCheck, String? repo}) _parse(List<String> args) {
  String? commit;
  String? repo;
  bool isCheck = false;
  final rest = args.iterator;
  while (rest.moveNext()) {
    switch (rest.current) {
      case '--gleon-repo':
        repo = _cli.value(rest);

      case '--commit':
        commit = _cli.value(rest);

      case '--check':
        isCheck = true;

      case '-h' || '--help':
        _cli.help();

      case final other:
        _cli.failUsage('unknown argument $other.');
    }
  }

  return (commit: commit, isCheck: isCheck, repo: repo);
}

/// The commit of the gleon tree [repo]: its git HEAD when [repo] is the top
/// of a git checkout, else the [given] `--commit`. A checkout with
/// uncommitted changes to the inputs of the library (`Cargo.lock`, the
/// manifests and sources of its crates) is refused: its crates are not the
/// commit's; so is one whose changes git cannot tell.
Future<String> _commitOf(Directory repo, {required String? given}) async {
  final head = await _gitHead(repo);
  if (head != null && given != null && head != given) {
    _cli.fail('${repo.path} is at $head, not --commit $given.');
  }
  if (head != null) {
    final state =
        await NativeBuild.checkoutState(repo.uri) ??
        _cli.fail(
          'cannot read the changes of ${repo.path} with git: its crates may '
          'not be those of $head.',
        );
    if (state.isDirty) {
      _cli.fail(
        '${repo.path} has uncommitted changes to the inputs of the library: '
        'its crates are not those of $head. Commit or stash them.',
      );
    }
  }

  return head ??
      given ??
      _cli.fail(
        'cannot read the commit of ${repo.path} with git; for a tree '
        'exported without git, pass the commit it came from as --commit.',
      );
}

/// HEAD of the git checkout whose top directory is [repo], or null (no git,
/// no checkout, or [repo] inside another repository).
Future<String?> _gitHead(Directory repo) async {
  final ProcessResult result;
  try {
    const revParse = ['rev-parse', '--show-toplevel', 'HEAD'];
    result = await Process.run('git', revParse, workingDirectory: repo.path);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) return null;
  final lines = const LineSplitter().convert(result.stdout.toString());
  if (lines case [final top, final head]
      when Directory(top).resolveSymbolicLinksSync() ==
          repo.resolveSymbolicLinksSync()) {
    return head;
  }

  return null;
}

/// The crates linked into `gleon-ffi` for any target, sorted.
Future<List<LicenseCrate>> _linked(Directory repo) async {
  final labels = <String>{
    for (final target in NativeTarget.values)
      ...LicenseCrate.treeLabels(
        await _cargo(repo, [
          'tree',
          '--locked',
          '-p',
          'gleon-ffi',
          '-e',
          'normal,no-proc-macro',
          '--target',
          target.rustTriple,
          '--prefix',
          'none',
          '--format',
          '{p}',
        ]),
      ),
  };
  final metadata = json.decode(
    await _cargo(repo, ['metadata', '--format-version', '1', '--locked']),
  );
  try {
    return LicenseCrate.linked(metadata, labels);
  } on FormatException catch (error) {
    _cli.fail(error.message);
  }
}

/// Runs cargo in [repo] (its pinned toolchain) and returns its output.
Future<String> _cargo(Directory repo, List<String> args) async {
  final ProcessResult result;
  try {
    result = await Process.run('cargo', args, workingDirectory: repo.path);
  } on ProcessException {
    _cli.fail('`cargo` was not found on PATH.');
  }
  if (result.exitCode != 0) {
    _cli.fail('`cargo ${args.join(' ')}` failed:\n${result.stderr}');
  }

  return result.stdout.toString();
}
