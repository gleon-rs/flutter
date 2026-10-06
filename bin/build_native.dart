/// Builds the gleon-ffi native library from a gleon checkout into `native/`
/// (where the build hook picks it up before downloading anything).
///
/// ```sh
/// dart bin/build_native.dart [--target host|all|<key>]... \
///   [--gleon-repo <dir>] [--dist <dir>]
/// ```
///
/// Run it with plain `dart`, not `dart run`: `dart run` first executes this
/// package's build hook, which needs the very library this script builds.
///
/// Maintainers and CI only; package consumers never need Rust. Requirements:
/// rustup (the toolchain comes from the gleon repo's `rust-toolchain.toml`).
/// Cross builds, used only for local convenience (CI builds every target
/// natively): Linux targets of another OS or architecture via
/// `cargo zigbuild` (`brew install zig cargo-zigbuild`), Windows targets from
/// other hosts via `cargo xwin` (`cargo install --locked cargo-xwin`); macOS
/// only on macOS. `--target all` builds every target this host can.
///
/// A library is replaced atomically, and its stamp (the gleon commit it was
/// built from) is written only after it, so an interrupted build leaves no
/// stamp, which the hook refuses while `native/gleon_ref` exists.
///
/// Only `dart:*`, `crypto` and this package may be imported here: pub's
/// strict-dependencies check forbids dev_dependencies in `bin/`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:gleon/src/core/hook/atomic_write.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/source_build.dart';

typedef _Options = ({
  String? dist,
  bool isDirtyAllowed,
  List<String> keys,
  String? repo,
});

String get _usage =>
    '''
Usage: dart bin/build_native.dart [options]

  --target <key>      host (default), all (every target this host can
                      build), or one of: ${NativeTarget.keys}. Repeatable.
  --gleon-repo <dir>  gleon checkout (default: \$GLEON_REPO, else ../gleon).
  --dist <dir>        also copy each library there under its release asset
                      name.
  --allow-dirty       build a checkout with uncommitted changes; the hook
                      accepts the library for the commit it is based on, so
                      rebuild after every engine change.
  -h, --help          show this help.
''';

Future<void> main(List<String> args) async {
  final options = _parse(args);
  final host = NativeTarget.host;
  final hostOs = Platform.operatingSystem;
  final List<NativeTarget> targets;
  try {
    targets = NativeTarget.resolveKeys(
      options.keys,
      hostOs: hostOs,
      host: host,
    );
  } on FormatException catch (error) {
    _fail(error.message);
  }
  final packageRoot = await _packageRoot();
  final repo = Directory(
    options.repo ??
        Platform.environment['GLEON_REPO'] ??
        packageRoot.resolve('../gleon').toFilePath(),
  ).absolute;
  final manifest = repo.uri.resolve('${SourceBuild.crate}/Cargo.toml');
  if (!File.fromUri(manifest).existsSync()) {
    _fail('${repo.path} is not a gleon checkout; pass --gleon-repo.');
  }
  final pin = await _readPin(packageRoot);
  final builtFrom = await _stamp(repo, isDirtyAllowed: options.isDirtyAllowed);
  if (pin != null && !NativeTarget.isBuildOfPin(builtFrom, pin)) {
    stderr.writeln(
      'warning: ${repo.path} is at $builtFrom, but native/'
      '${NativeTarget.pinFileName} pins $pin: the build hook refuses this '
      'library until the pin names that commit (CI and releases build the '
      'pinned commit). To test another checkout, use the `gleon_repo` '
      'user-define instead.',
    );
  }
  for (final target in targets) {
    final subcommand =
        target.cargoSubcommand(hostOs: hostOs, host: host) ??
        _fail('${target.key} cannot be built here.');
    final library = await _build(repo, target, subcommand);
    await _install(
      library,
      target,
      packageRoot: packageRoot,
      dist: options.dist,
      builtFrom: builtFrom,
    );
  }
}

/// Copies the built [library] of [target] into `native/<target>/` of
/// [packageRoot] (and [dist] under its release asset name) and stamps it
/// with the commit it was [builtFrom].
Future<void> _install(
  File library,
  NativeTarget target, {
  required Uri packageRoot,
  required String? dist,
  required String builtFrom,
}) async {
  final bytes = await library.readAsBytes();
  final targetDir = packageRoot.resolve('native/${target.key}/');
  // Records the commit this build was made from; the hook rejects the
  // library unless native/gleon_ref pins it. Removed first, so a library
  // replaced by an interrupted build is never accepted under an old stamp.
  final stamp = File.fromUri(targetDir.resolve(NativeTarget.pinFileName));
  if (stamp.existsSync()) await stamp.delete();
  final outputs = [
    File.fromUri(targetDir.resolve(target.libFileName)),
    if (dist != null)
      File.fromUri(Directory(dist).absolute.uri.resolve(target.assetName)),
  ];
  for (final output in outputs) {
    await AtomicWrite.bytes(output, bytes);
  }
  await AtomicWrite.bytes(stamp, utf8.encode('$builtFrom\n'));
  stdout.writeln(
    '${target.key}: ${sha256.convert(bytes)}  '
    '${outputs.map((file) => file.path).join(', ')}',
  );
}

_Options _parse(List<String> args) {
  final keys = <String>[];
  String? repo;
  String? dist;
  bool isDirtyAllowed = false;
  final rest = args.iterator;
  while (rest.moveNext()) {
    switch (rest.current) {
      case '--target':
        keys.add(_value(rest));

      case '--gleon-repo':
        repo = _value(rest);

      case '--dist':
        dist = _value(rest);

      case '--allow-dirty':
        isDirtyAllowed = true;

      case '-h' || '--help':
        stdout.write(_usage);
        exit(0);

      case final other:
        _fail('unknown argument $other.\n\n$_usage');
    }
  }

  return (
    dist: dist,
    isDirtyAllowed: isDirtyAllowed,
    keys: keys.isEmpty ? const ['host'] : keys,
    repo: repo,
  );
}

/// The value following the flag that [rest] is at.
String _value(Iterator<String> rest) {
  final flag = rest.current;

  return rest.moveNext()
      // ignore: use-existing-variable, `moveNext` advanced to the value.
      ? rest.current
      : _fail('$flag needs a value.\n\n$_usage');
}

Future<Uri> _packageRoot() async {
  final lib = await Isolate.resolvePackageUri(.parse('package:gleon/'));
  if (lib == null) _fail('run this from the gleon package directory.');

  return lib.resolve('../');
}

/// Builds [target] in [repo] with the cargo [subcommand] this host needs.
Future<File> _build(
  Directory repo,
  NativeTarget target,
  List<String> subcommand,
) async {
  final NativeTarget(:libFileName, :rustTriple) = target;

  await _run('rustup', ['target', 'add', rustTriple], repo, isOptional: true);
  // Explicit: a `CARGO_TARGET_DIR` or `build.target-dir` would build
  // elsewhere, and an old library left in `target/` would be copied instead.
  final targetDir = Directory.fromUri(repo.uri.resolve('target/'));
  await _run(
    'cargo',
    [
      ...subcommand,
      '--release',
      '--locked',
      '-p',
      SourceBuild.crate,
      '--target',
      rustTriple,
      '--target-dir',
      targetDir.path,
    ],
    repo,
    environment: target.cargoEnvironment(Platform.environment),
  );
  final library = File.fromUri(
    targetDir.uri.resolve('$rustTriple/release/$libFileName'),
  );
  if (!library.existsSync()) {
    _fail('cargo succeeded but ${library.path} is missing.');
  }

  return library;
}

Future<void> _run(
  String executable,
  List<String> args,
  Directory workingDirectory, {
  Map<String, String> environment = const {},
  bool isOptional = false,
}) async {
  final command = '$executable ${args.join(' ')}';
  stdout.writeln('\$ $command');
  final Process process;
  try {
    process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory.path,
      environment: environment,
      mode: .inheritStdio,
    );
  } on ProcessException {
    if (isOptional) return;
    _fail('`$executable` was not found on PATH.');
  }
  final exitCode = await process.exitCode;
  if (exitCode != 0 && !isOptional) {
    _fail('`$command` failed with exit code $exitCode.');
  }
}

Future<String?> _readPin(Uri packageRoot) async {
  final pin = File.fromUri(
    packageRoot.resolve('native/${NativeTarget.pinFileName}'),
  );
  if (!pin.existsSync()) return null;
  final content = await pin.readAsString();

  return content.trim();
}

/// The stamp of a build of [repo]: its commit, with
/// [NativeTarget.dirtySuffix] for uncommitted changes (only when
/// [isDirtyAllowed]). Fails when git cannot tell the commit.
Future<String> _stamp(Directory repo, {required bool isDirtyAllowed}) async {
  final state = await _checkoutState(repo);
  if (state == null) {
    _fail(
      'cannot read the commit of ${repo.path} with git, and the build hook '
      'only accepts a library built from the commit native/'
      '${NativeTarget.pinFileName} pins. Build another source with the '
      '`gleon_repo` user-define instead.',
    );
  }
  final (:commit, :isDirty) = state;
  if (!isDirty) return commit;
  if (!isDirtyAllowed) {
    _fail(
      '${repo.path} has uncommitted changes in the sources of the library. '
      'Commit or stash them, or pass '
      '--allow-dirty to build them (the hook then accepts the library for '
      '$commit until you rebuild).',
    );
  }

  return '$commit${NativeTarget.dirtySuffix}';
}

/// The commit [repo] is at and whether the inputs of the library have
/// uncommitted or untracked changes (anything else in the checkout does not
/// matter), or null when git cannot tell (no git, not a checkout, a checkout
/// git refuses to read).
Future<({String commit, bool isDirty})?> _checkoutState(Directory repo) async {
  final ProcessResult head;
  final ProcessResult status;
  try {
    head = await Process.run('git', _gitHead, workingDirectory: repo.path);
    final arguments = [
      ..._gitStatus,
      '--',
      ...SourceBuild.inputPaths(repo.uri),
    ];
    status = await Process.run('git', arguments, workingDirectory: repo.path);
  } on ProcessException {
    return null;
  }
  if (head.exitCode != 0 || status.exitCode != 0) return null;

  return (
    commit: head.stdout.toString().trim(),
    isDirty: status.stdout.toString().trim().isNotEmpty,
  );
}

const _gitHead = ['rev-parse', 'HEAD'];

// Untracked inputs count even where `status.showUntrackedFiles` hides them.
const _gitStatus = ['status', '--porcelain', '--untracked-files=all'];

Never _fail(String message) {
  stderr.writeln('build_native: $message');
  exit(64);
}
