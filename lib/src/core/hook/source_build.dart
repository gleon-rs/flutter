import 'dart:io';

import 'native_target.dart';

/// A library the build hook provides and every input file whose change must
/// re-run the hook (`NativeLibrary.resolve`, [SourceBuild.run]).
typedef LibraryFiles = ({List<Uri> dependencies, Uri library});

/// Runs a process like [Process.run] (injectable so builds are testable
/// without Rust).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  String? workingDirectory,
});

/// Builds `gleon-ffi` with cargo from a gleon checkout (the `gleon_repo`
/// user-define, for contributors). Package consumers never get here: this is
/// never a silent fallback, and every failure is an actionable error.
///
/// Plain Dart (no Flutter imports): used by `hook/build.dart` and tested
/// directly.
abstract final class SourceBuild {
  /// The Rust crate that produces the library.
  static const crate = 'gleon-ffi';

  /// Workspace files whose change must re-run the build (when present).
  static const _workspaceFiles = [
    'Cargo.toml',
    'Cargo.lock',
    'rust-toolchain.toml',
  ];

  /// `path = "<dir>"` dependencies of a `Cargo.toml`, in either quotes.
  static final _pathDependency = RegExp(r'''path\s*=\s*["']([^"']+)["']''');

  /// The arguments of a cargo build subcommand (`build`, `zigbuild`, ...)
  /// that builds [target] into [targetDir]: release, locked, only [crate].
  /// The library lands at [NativeTarget.builtLibrary].
  static List<String> cargoArguments(NativeTarget target, Uri targetDir) => [
    '--release',
    '--locked',
    '--package',
    crate,
    '--target',
    target.rustTriple,
    '--target-dir',
    targetDir.toFilePath(),
  ];

  /// Builds [target] from the checkout at [repoRoot] into [targetDir]
  /// (cargo's `--target-dir`), using [environment] (the hook's process
  /// environment) to find cargo and to pass its settings on; [runProcess]
  /// runs it.
  static Future<LibraryFiles> run({
    required Uri repoRoot,
    required Uri targetDir,
    required NativeTarget target,
    required Map<String, String> environment,
    ProcessRunner runProcess = Process.run,
  }) async {
    final root = checkoutRoot(repoRoot);
    final cargo = findCargo(environment);
    final arguments = ['build', ...cargoArguments(target, targetDir)];
    final result = await runProcess(
      cargo,
      arguments,
      environment: target.cargoEnvironment(environment),
      workingDirectory: root.toFilePath(),
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        cargo,
        arguments,
        'gleon: failed to build the native library (exit ${result.exitCode}).'
        '\n${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }

    final library = target.builtLibrary(targetDir);
    if (!File.fromUri(library).existsSync()) {
      throw StateError(
        'gleon: cargo succeeded but ${library.toFilePath()} is missing.',
      );
    }

    return (dependencies: inputs(root), library: library);
  }

  /// The gleon checkout at [repoRoot] as a directory URI (with a trailing
  /// slash, so `resolve` stays inside it).
  ///
  /// Throws a [StateError] naming the `gleon_repo` user-define when
  /// [repoRoot] is not a gleon checkout.
  static Uri checkoutRoot(Uri repoRoot) {
    // User-define paths resolve without a trailing slash.
    final root = repoRoot.path.endsWith('/')
        ? repoRoot
        : repoRoot.replace(path: '${repoRoot.path}/');
    if (!File.fromUri(root.resolve('$crate/Cargo.toml')).existsSync()) {
      throw StateError(
        'gleon: user-define `gleon_repo` must point to a gleon checkout; '
        '$crate not found in ${root.toFilePath()}.',
      );
    }

    return root;
  }

  /// Resolves `cargo` from `PATH` in [environment], falling back to the
  /// default rustup location (IDE-launched processes often lack
  /// `~/.cargo/bin` in `PATH`).
  ///
  /// Throws a [StateError] that says where it looked when cargo is missing.
  static String findCargo(Map<String, String> environment) {
    final executable = Platform.isWindows ? 'cargo.exe' : 'cargo';
    final cargoHome =
        environment['CARGO_HOME'] ??
        switch (environment['HOME'] ?? environment['USERPROFILE']) {
          final userHome? => '$userHome/.cargo',
          null => null,
        };
    final cargoBin = [if (cargoHome != null) '$cargoHome/bin'];
    final searched = [
      ...?environment['PATH']?.split(Platform.isWindows ? ';' : ':'),
      ...cargoBin,
    ].where((dir) => dir.isNotEmpty);
    for (final dir in searched) {
      final candidate = File('$dir${Platform.pathSeparator}$executable');
      if (candidate.existsSync()) return candidate.path;
    }

    throw StateError(
      'gleon: `cargo` was not found (searched '
      '${['PATH', ...cargoBin].join(' and ')}), but the '
      '`gleon_repo` user-define asks for a source build. Install Rust via '
      'rustup, or remove `gleon_repo` to use the prebuilt library.',
    );
  }

  /// Every Rust input of the build inside the checkout [root]: the workspace
  /// files plus the manifest and sources of [crate] and of every crate it
  /// reaches through `path` dependencies, so a new crate is tracked without
  /// changing this list.
  static List<Uri> inputs(Uri root) => [
    for (final file in _workspaceFiles)
      if (File.fromUri(root.resolve(file)) case final workspaceFile
          when workspaceFile.existsSync())
        workspaceFile.uri,
    for (final member in _localCrates(root))
      if (File.fromUri(root.resolve('$member/Cargo.toml')) case final manifest
          when manifest.existsSync()) ...[
        manifest.uri,
        ..._sources(root.resolve('$member/src/')),
      ],
  ];

  /// The inputs of [inputs] as git pathspecs relative to the checkout
  /// [root]: a change anywhere else (another crate, docs, untracked notes)
  /// does not change the library.
  static List<String> inputPaths(Uri root) => [
    ..._workspaceFiles,
    for (final member in _localCrates(root)) ...[
      '$member/Cargo.toml',
      '$member/src',
    ],
  ];

  /// [crate] and its transitive `path` dependencies inside the checkout
  /// [root], as directories relative to it. The workspace's own `path`
  /// dependencies count too, since members inherit them with
  /// `workspace = true`: one crate too many only rebuilds more often.
  static Set<String> _localCrates(Uri root) {
    final crates = <String>{};
    final pending = [crate, ..._pathDependencies(root, inside: root)];
    while (pending.isNotEmpty) {
      final member = pending.removeLast();
      if (crates.add(member)) {
        pending.addAll(
          _pathDependencies(root.resolve('$member/'), inside: root),
        );
      }
    }

    return crates;
  }

  /// The `path` dependencies of the manifest in [dir] that lie [inside] the
  /// checkout, relative to it.
  static List<String> _pathDependencies(Uri dir, {required Uri inside}) {
    final manifest = File.fromUri(dir.resolve('Cargo.toml'));
    // `inside` is a directory: its last segment is empty.
    final depth = inside.pathSegments.length - 1;

    return manifest.existsSync()
        ? [
            for (final match in _pathDependency.allMatches(
              manifest.readAsStringSync(),
            ))
              if (match.group(1) case final path?)
                if (dir.resolve(path) case final crateDir
                    when crateDir.path.startsWith(inside.path))
                  crateDir.pathSegments.skip(depth).join('/'),
          ]
        : const [];
  }

  static Iterable<Uri> _sources(Uri dir) {
    final sources = Directory.fromUri(dir);

    return sources.existsSync()
        ? sources
              .listSync(recursive: true)
              .whereType<File>()
              .map((file) => file.uri)
        : const [];
  }
}
