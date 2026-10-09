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
/// `cargo zigbuild` (zig plus `cargo install --locked cargo-zigbuild` on any
/// host; `brew install zig cargo-zigbuild` on macOS), Windows targets from
/// other hosts via `cargo xwin` (`cargo install --locked cargo-xwin`); macOS
/// only on macOS. `--target all` builds every target this host can.
///
/// A library is replaced atomically, and its stamp (the gleon commit it was
/// built from) is written only after it, so an interrupted build leaves no
/// stamp, which the hook refuses while `native/gleon_ref` exists; the
/// `--dist` copy comes last (see `NativeBuild` in `src/native_build.dart`).
///
/// Only `dart:*`, `crypto`, this package and `src/` may be imported here:
/// pub's strict-dependencies check forbids dev_dependencies in `bin/`.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/source_build.dart';

import 'src/cli.dart';
import 'src/native_build.dart';

typedef _Options = ({
  String? dist,
  bool isDirtyAllowed,
  List<String> keys,
  String? repo,
});

final _cli = Cli('build_native', '''
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
''');

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
    _cli.fail(error.message);
  }
  final packageRoot = await _cli.packageRoot();
  final repo = _checkout(options.repo, packageRoot);
  final builtFrom = await _stamp(repo, isDirtyAllowed: options.isDirtyAllowed);
  _warnUnlessPinned(packageRoot, repo, builtFrom);
  for (final target in targets) {
    final subcommand =
        target.cargoSubcommand(hostOs: hostOs, host: host) ??
        _cli.fail('${target.key} cannot be built here.');
    final library = await _build(repo, target, subcommand);
    final installed = await NativeBuild.install(
      library,
      target,
      packageRoot: packageRoot,
      builtFrom: builtFrom,
      dist: options.dist,
    );
    final hash = sha256.convert(await library.readAsBytes());
    stdout.writeln(
      '${target.key}: $hash  ${installed.map((file) => file.path).join(', ')}',
    );
  }
}

/// The gleon checkout of [Cli.gleonCheckout]; fails unless it is one.
Directory _checkout(String? repo, Uri packageRoot) {
  final checkout = Cli.gleonCheckout(repo, packageRoot);
  final manifest = checkout.uri.resolve('${SourceBuild.crate}/Cargo.toml');
  if (!File.fromUri(manifest).existsSync()) {
    _cli.fail('${checkout.path} is not a gleon checkout; pass --gleon-repo.');
  }

  return checkout;
}

/// Warns when a build of [repo] stamped [builtFrom] is not one of the
/// commit `native/gleon_ref` pins: the hook refuses it.
void _warnUnlessPinned(Uri packageRoot, Directory repo, String builtFrom) {
  final pin = NativeTarget.readPin(packageRoot);
  if (pin != null && !NativeTarget.isBuildOfPin(builtFrom, pin)) {
    stderr.writeln(
      'warning: ${repo.path} is at $builtFrom, but native/'
      '${NativeTarget.pinFileName} pins $pin: the build hook refuses this '
      'library until the pin names that commit (CI and releases build the '
      'pinned commit). To test another checkout, use the `gleon_repo` '
      'user-define instead.',
    );
  }
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
        keys.add(_cli.value(rest));

      case '--gleon-repo':
        repo = _cli.value(rest);

      case '--dist':
        dist = _cli.value(rest);

      case '--allow-dirty':
        isDirtyAllowed = true;

      case '-h' || '--help':
        _cli.help();

      case final other:
        _cli.failUsage('unknown argument $other.');
    }
  }

  return (
    dist: dist,
    isDirtyAllowed: isDirtyAllowed,
    keys: keys.isEmpty ? const ['host'] : keys,
    repo: repo,
  );
}

/// Builds [target] in [repo] with the cargo [subcommand] this host needs.
Future<File> _build(
  Directory repo,
  NativeTarget target,
  List<String> subcommand,
) async {
  final rustup = ['target', 'add', target.rustTriple];
  await _run('rustup', rustup, repo, isOptional: true);
  // Explicit: a `CARGO_TARGET_DIR` or `build.target-dir` would build
  // elsewhere, and an old library left in `target/` would be copied instead.
  final targetDir = Directory.fromUri(repo.uri.resolve('target/'));
  await _run(
    'cargo',
    [...subcommand, ...SourceBuild.cargoArguments(target, targetDir.uri)],
    repo,
    environment: target.cargoEnvironment(Platform.environment),
  );
  final library = File.fromUri(target.builtLibrary(targetDir.uri));
  if (!library.existsSync()) {
    _cli.fail('cargo succeeded but ${library.path} is missing.');
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
    _cli.fail('`$executable` was not found on PATH.');
  }
  final exitCode = await process.exitCode;
  if (exitCode != 0 && !isOptional) {
    _cli.fail('`$command` failed with exit code $exitCode.');
  }
}

/// The stamp of a build of [repo]: its commit, with
/// [NativeTarget.dirtySuffix] for uncommitted changes (only when
/// [isDirtyAllowed]). Fails when git cannot tell the commit.
Future<String> _stamp(Directory repo, {required bool isDirtyAllowed}) async {
  final state = await NativeBuild.checkoutState(repo.uri);
  if (state == null) {
    _cli.fail(
      'cannot read the commit of ${repo.path} with git, and the build hook '
      'only accepts a library built from the commit native/'
      '${NativeTarget.pinFileName} pins. Build another source with the '
      '`gleon_repo` user-define instead.',
    );
  }
  final (:commit, :isDirty) = state;
  if (!isDirty) return commit;
  if (!isDirtyAllowed) {
    _cli.fail(
      '${repo.path} has uncommitted changes in the sources of the library. '
      'Commit or stash them, or pass '
      '--allow-dirty to build them (the hook then accepts the library for '
      '$commit until you rebuild).',
    );
  }

  return '$commit${NativeTarget.dirtySuffix}';
}
