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
/// natively): Linux targets from other hosts via `cargo zigbuild`
/// (`brew install zig cargo-zigbuild`), Windows targets from other hosts via
/// `cargo xwin` (`cargo install --locked cargo-xwin`).
///
/// Only `dart:*`, `crypto` and this package may be imported here: pub's
/// strict-dependencies check forbids dev_dependencies in `bin/`.
library;

import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/source_build.dart';

typedef _Options = ({String? dist, List<String> keys, String? repo});

String get _usage =>
    '''
Usage: dart bin/build_native.dart [options]

  --target <key>      host (default), all, or one of: ${NativeTarget.keys}.
                      Repeatable.
  --gleon-repo <dir>  gleon checkout (default: \$GLEON_REPO, else ../gleon).
  --dist <dir>        also copy each library there under its release asset
                      name.
  -h, --help          show this help.
''';

Future<void> main(List<String> args) async {
  final options = _parse(args);
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
  await _warnIfNotPinned(pin, repo);

  // `Abi` names are `<os>_<arch>`, like target keys with an underscore.
  final host = NativeTarget.byKey(
    Abi.current().toString().replaceAll('_', '-'),
  );
  for (final target in _targets(options.keys, host)) {
    final library = await _build(repo, target, host: host);
    final bytes = await library.readAsBytes();
    final targetDir = packageRoot.resolve('native/${target.key}/');
    final outputs = [
      File.fromUri(targetDir.resolve(target.libFileName)),
      if (options.dist case final dist?)
        File.fromUri(Directory(dist).absolute.uri.resolve(target.assetName)),
    ];
    for (final output in outputs) {
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes, flush: true);
    }
    // Records the pin this build was made for; the hook rejects the library
    // once native/gleon_ref moves on.
    await File.fromUri(targetDir.resolve(NativeTarget.pinFileName))
        .writeAsString('${pin ?? '(unpinned)'}\n');
    stdout.writeln(
      '${target.key}: ${sha256.convert(bytes)}  '
      '${outputs.map((file) => file.path).join(', ')}',
    );
  }
}

_Options _parse(List<String> args) {
  final keys = <String>[];
  String? repo;
  String? dist;
  final rest = args.iterator;
  while (rest.moveNext()) {
    switch (rest.current) {
      case '--target':
        keys.add(_value(rest));

      case '--gleon-repo':
        repo = _value(rest);

      case '--dist':
        dist = _value(rest);

      case '-h' || '--help':
        stdout.write(_usage);
        exit(0);

      case final other:
        _fail('unknown argument $other.\n\n$_usage');
    }
  }

  return (dist: dist, keys: keys.isEmpty ? const ['host'] : keys, repo: repo);
}

/// The value following the flag that [rest] is at.
String _value(Iterator<String> rest) {
  final flag = rest.current;

  return rest.moveNext()
      // ignore: use-existing-variable, `moveNext` advanced to the value.
      ? rest.current
      : _fail('$flag needs a value.\n\n$_usage');
}

List<NativeTarget> _targets(List<String> keys, NativeTarget? host) =>
    <NativeTarget>{
      for (final key in keys)
        ...switch (key) {
          'all' => NativeTarget.values,
          'host' => [
            host ??
                _fail(
                  'this host is not a supported target (${NativeTarget.keys}).',
                ),
          ],
          _ => [
            NativeTarget.byKey(key) ??
                _fail(
                  'unknown target $key (expected host, all, '
                  '${NativeTarget.keys}).',
                ),
          ],
        },
    }.toList();

Future<Uri> _packageRoot() async {
  final lib = await Isolate.resolvePackageUri(.parse('package:gleon/'));
  if (lib == null) _fail('run this from the gleon package directory.');

  return lib.resolve('../');
}

Future<File> _build(
  Directory repo,
  NativeTarget target, {
  required NativeTarget? host,
}) async {
  final NativeTarget(:key, :libFileName, :os, :rustTriple) = target;
  // Plain cargo within one OS; the cross-linking wrapper for Linux or Windows
  // targets built elsewhere. The macOS SDK only exists on macOS.
  final subcommand = switch (target) {
    _ when os == host?.os => ['build'],
    .linuxArm64 || .linuxX64 => ['zigbuild'],
    .windowsX64 => ['xwin', 'build'],
    .macosArm64 => _fail('$key can only be built on macOS.'),
  };

  await _run('rustup', ['target', 'add', rustTriple], repo, isOptional: true);
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
    ],
    repo,
    environment: target.cargoEnvironment(Platform.environment),
  );
  final library = File.fromUri(
    repo.uri.resolve('target/$rustTriple/release/$libFileName'),
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

const _gitHead = ['rev-parse', 'HEAD'];

Future<void> _warnIfNotPinned(String? pin, Directory repo) async {
  if (pin == null) return;
  final ProcessResult head;
  try {
    head = await Process.run('git', _gitHead, workingDirectory: repo.path);
  } on ProcessException {
    return; // No git: nothing to compare.
  }
  final actual = head.stdout.toString().trim();
  if (head.exitCode == 0 && actual != pin) {
    stderr.writeln(
      'warning: ${repo.path} is at $actual, but native/${NativeTarget.pinFileName} pins $pin '
      '(CI and releases build the pinned commit).',
    );
  }
}

Never _fail(String message) {
  stderr.writeln('build_native: $message');
  exit(64);
}
