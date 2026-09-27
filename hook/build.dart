// Build hook that provides the `gleon-ffi` native library to Dart.
//
// Consumers need neither Rust nor a network connection: the package ships
// prebuilt libraries in `native/` (see `tool/build_native.sh`) and this hook
// only verifies the one for the requested target against the SHA-256 in
// `native/manifest.json` before bundling it.
//
// Overrides (user-defines in the consuming app's pubspec.yaml):
//
//   hooks:
//     user_defines:
//       gleon:
//         ffi_path: path/to/libgleon_ffi.dylib # use this library as is
//         gleon_repo: ../gleon                 # contributors: cargo build from a gleon checkout
//
// Source builds are never a silent fallback: an unsupported target fails with
// an actionable error instead.

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

/// Must match the asset id used by the `@Native` bindings in `lib/src/native.dart`.
const _assetName = 'src/native.dart';
const _crate = 'gleon-ffi';
const _libraryBaseName = 'gleon_ffi';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    final code = input.config.code;
    final os = code.targetOS;
    final arch = code.targetArchitecture;

    final Uri library;
    final override = input.userDefines.path('ffi_path');
    final gleonRepo = input.userDefines.path('gleon_repo');
    if (override != null) {
      output.dependencies.add(override);
      if (!File.fromUri(override).existsSync()) {
        throw StateError(
          'gleon: user-define `ffi_path` points to a missing file: '
          '${override.toFilePath()}',
        );
      }
      library = override;
    } else if (gleonRepo != null) {
      library = await _buildFromSource(
        repoRoot: gleonRepo,
        input: input,
        output: output,
        triple: _rustTriple(os, arch),
        libraryFileName: os.dylibFileName(_libraryBaseName),
      );
    } else {
      library = _verifiedPrebuilt(input, output, os, arch);
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: library,
      ),
    );
  });
}

/// Key of the requested target (not the host) in `native/manifest.json`.
String? _targetKey(OS os, Architecture arch) => switch ((os, arch)) {
  (OS.macOS, Architecture.arm64) => 'macos-arm64',
  (OS.macOS, Architecture.x64) => 'macos-x64',
  (OS.linux, Architecture.x64) => 'linux-x64',
  _ => null,
};

Uri _verifiedPrebuilt(
  BuildInput input,
  BuildOutputBuilder output,
  OS os,
  Architecture arch,
) {
  final manifestUri = input.packageRoot.resolve('native/manifest.json');
  output.dependencies.add(manifestUri);
  final manifest =
      jsonDecode(File.fromUri(manifestUri).readAsStringSync())
          as Map<String, Object?>;
  final targets = manifest['targets']! as Map<String, Object?>;
  final key = _targetKey(os, arch);
  final entry = key == null ? null : targets[key] as Map<String, Object?>?;
  if (entry == null) {
    throw UnsupportedError(
      'gleon: no prebuilt native library for $os/$arch (available: '
      '${targets.keys.join(', ')}). Web, Windows and on-device tests are not '
      'supported yet.',
    );
  }

  final library = input.packageRoot.resolve('native/${entry['file']}');
  output.dependencies.add(library);
  final file = File.fromUri(library);
  if (!file.existsSync()) {
    throw StateError('gleon: prebuilt library missing: ${file.path}');
  }
  final actual = sha256.convert(file.readAsBytesSync()).toString();
  if (actual != entry['sha256']) {
    throw StateError(
      'gleon: checksum mismatch for ${file.path} (expected ${entry['sha256']}, '
      'got $actual). The package files are corrupted or were modified; '
      're-fetch the package.',
    );
  }
  return library;
}

/// Maps the requested target to a Rust target triple (source builds only).
String _rustTriple(OS os, Architecture arch) => switch ((os, arch)) {
  (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
  (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
  (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
  _ => throw UnsupportedError(
    'gleon: source builds support macOS arm64/x64 and Linux x64, not $os/$arch.',
  ),
};

Future<Uri> _buildFromSource({
  required Uri repoRoot,
  required BuildInput input,
  required BuildOutputBuilder output,
  required String triple,
  required String libraryFileName,
}) async {
  // `path()` resolves without a trailing slash; directories need one for `resolve`.
  final root = repoRoot.path.endsWith('/')
      ? repoRoot
      : repoRoot.replace(path: '${repoRoot.path}/');
  if (!File.fromUri(root.resolve('$_crate/Cargo.toml')).existsSync()) {
    throw StateError(
      'gleon: user-define `gleon_repo` must point to a gleon checkout; '
      '$_crate not found in ${root.toFilePath()}.',
    );
  }

  final targetDir = input.outputDirectoryShared.resolve('cargo/');
  final cargo = _findCargo();
  final result = await Process.run(cargo, [
    'build',
    '--release',
    '--locked',
    '--package',
    _crate,
    '--target',
    triple,
    '--target-dir',
    targetDir.toFilePath(),
  ], workingDirectory: root.toFilePath());
  if (result.exitCode != 0) {
    throw ProcessException(
      cargo,
      ['build', '--package', _crate, '--target', triple],
      'gleon: failed to build the native library (exit ${result.exitCode}).\n'
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }

  // Rebuild whenever the Rust inputs change.
  for (final file in [
    'Cargo.toml',
    'Cargo.lock',
    'rust-toolchain.toml',
    'gleon-engine/Cargo.toml',
    '$_crate/Cargo.toml',
  ]) {
    output.dependencies.add(root.resolve(file));
  }
  for (final dir in ['gleon-engine/src/', '$_crate/src/']) {
    Directory.fromUri(root.resolve(dir))
        .listSync(recursive: true)
        .whereType<File>()
        .forEach((file) => output.dependencies.add(file.uri));
  }

  final library = targetDir.resolve('$triple/release/$libraryFileName');
  if (!File.fromUri(library).existsSync()) {
    throw StateError(
      'gleon: cargo succeeded but ${library.toFilePath()} is missing.',
    );
  }
  return library;
}

/// Resolves `cargo` from `PATH`, falling back to the default rustup location
/// (IDE-launched processes often lack `~/.cargo/bin` in `PATH`).
String _findCargo() {
  final executable = Platform.isWindows ? 'cargo.exe' : 'cargo';
  final pathEntries = (Platform.environment['PATH'] ?? '').split(
    Platform.isWindows ? ';' : ':',
  );
  final home =
      Platform.environment['CARGO_HOME'] ??
      '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']}/.cargo';
  for (final dir in [...pathEntries, '$home/bin']) {
    if (dir.isEmpty) continue;
    final candidate = File('$dir${Platform.pathSeparator}$executable');
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  throw StateError(
    'gleon: `cargo` was not found (PATH or $home/bin), but the '
    '`gleon_repo` user-define asks for a source build.',
  );
}
