// Builds the gleon-ffi native library from a gleon checkout into `native/`
// (where the build hook picks it up before downloading anything).
//
//   dart bin/build_native.dart [--target host|all|<key>]... [--gleon-repo <dir>] [--dist <dir>]
//
// Run it with plain `dart`, not `dart run`: `dart run` first executes this
// package's build hook, which needs the very library this script builds.
//
// Maintainers and CI only; package consumers never need Rust. Requirements:
// rustup (the toolchain comes from the gleon repo's rust-toolchain.toml). Cross
// builds, used only for local convenience (CI builds every target natively):
// Linux targets from other hosts via `cargo zigbuild` (`brew install zig
// cargo-zigbuild`), Windows targets from other hosts via `cargo xwin`
// (`cargo install --locked cargo-xwin`).
//
// Only `dart:*`, `crypto` and this package may be imported here: pub's
// strict-dependencies check forbids dev_dependencies in `bin/`.

import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:gleon/src/hook/targets.dart';

const _crate = 'gleon-ffi';
String get _usage =>
    '''
Usage: dart bin/build_native.dart [options]

  --target <key>      host (default), all, or one of: $_keys. Repeatable.
  --gleon-repo <dir>  gleon checkout (default: \$GLEON_REPO, else ../gleon).
  --dist <dir>        also copy each library there under its release asset name.
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
  if (!File.fromUri(repo.uri.resolve('$_crate/Cargo.toml')).existsSync()) {
    _fail('${repo.path} is not a gleon checkout; pass --gleon-repo.');
  }
  final pin = await _readPin(packageRoot);
  await _warnIfNotPinned(pin, repo);

  // `Abi` names are `<os>_<arch>`, like target keys with an underscore.
  final host = NativeTarget.byKey(
    Abi.current().toString().replaceAll('_', '-'),
  );
  for (final target in options.targets(host)) {
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
    await File.fromUri(targetDir.resolve(pinFileName))
        .writeAsString('${pin ?? ''}\n');
    stdout.writeln(
      '${target.key}: ${sha256.convert(bytes)}  '
      '${outputs.map((f) => f.path).join(', ')}',
    );
  }
}

typedef _Options = ({
  String? repo,
  String? dist,
  List<NativeTarget> Function(NativeTarget? host) targets,
});

_Options _parse(List<String> args) {
  final keys = <String>[];
  String? repo;
  String? dist;
  for (var i = 0; i < args.length; i++) {
    String value() => i + 1 < args.length
        ? args[++i]
        : _fail('${args[i]} needs a value.\n\n$_usage');
    switch (args[i]) {
      case '--target':
        keys.add(value());
      case '--gleon-repo':
        repo = value();
      case '--dist':
        dist = value();
      case '-h' || '--help':
        stdout.write(_usage);
        exit(0);
      default:
        _fail('unknown argument ${args[i]}.\n\n$_usage');
    }
  }
  if (keys.isEmpty) keys.add('host');
  return (
    repo: repo,
    dist: dist,
    targets: (host) => <NativeTarget>{
      for (final key in keys)
        ...switch (key) {
          'all' => NativeTarget.values,
          'host' => [
            host ?? _fail('this host is not a supported target ($_keys).'),
          ],
          _ => [
            NativeTarget.byKey(key) ??
                _fail('unknown target $key (expected host, all, $_keys).'),
          ],
        },
    }.toList(),
  );
}

String get _keys => NativeTarget.values.map((t) => t.key).join(', ');

Future<Uri> _packageRoot() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:gleon/'));
  if (lib == null) _fail('run this from the gleon package directory.');
  return lib.resolve('../');
}

Future<File> _build(
  Directory repo,
  NativeTarget target, {
  required NativeTarget? host,
}) async {
  final triple = target.rustTriple;
  // Plain cargo within one OS; the cross-linking wrapper for Linux or Windows
  // targets built elsewhere. The macOS SDK only exists on macOS.
  final subcommand = switch (target.os) {
    _ when target.os == host?.os => ['build'],
    'linux' => ['zigbuild'],
    'windows' => ['xwin', 'build'],
    _ => _fail('${target.key} can only be built on macOS.'),
  };

  await _run('rustup', ['target', 'add', triple], repo, optional: true);
  await _run(
    'cargo',
    [...subcommand, '--release', '--locked', '-p', _crate, '--target', triple],
    repo,
    environment: target.cargoEnvironment(Platform.environment),
  );
  final library = File.fromUri(
    repo.uri.resolve('target/$triple/release/${target.libFileName}'),
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
  bool optional = false,
}) async {
  stdout.writeln('\$ $executable ${args.join(' ')}');
  final Process process;
  try {
    process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory.path,
      environment: environment,
      mode: ProcessStartMode.inheritStdio,
    );
  } on ProcessException {
    if (optional) return;
    _fail('`$executable` was not found on PATH.');
  }
  final exitCode = await process.exitCode;
  if (exitCode != 0 && !optional) {
    _fail('`$executable ${args.join(' ')}` failed with exit code $exitCode.');
  }
}

Future<String?> _readPin(Uri packageRoot) async {
  final pin = File.fromUri(packageRoot.resolve('native/$pinFileName'));
  return pin.existsSync() ? (await pin.readAsString()).trim() : null;
}

Future<void> _warnIfNotPinned(String? pin, Directory repo) async {
  if (pin == null) return;
  final ProcessResult head;
  try {
    head = await Process.run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: repo.path);
  } on ProcessException {
    return; // No git: nothing to compare.
  }
  final actual = (head.stdout as String).trim();
  if (head.exitCode == 0 && actual != pin) {
    stderr.writeln(
      'warning: ${repo.path} is at $actual, but native/$pinFileName pins '
      '$pin (CI and releases build the pinned commit).',
    );
  }
}

Never _fail(String message) {
  stderr.writeln('build_native: $message');
  exit(64);
}
