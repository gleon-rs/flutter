// Build hook that provides the `gleon-ffi` native library to Dart.
//
// Consumers never need Rust. The library is resolved in this order:
//
// 1. user-define `ffi_path`: this exact file.
// 2. user-define `gleon_repo`: cargo build from a gleon checkout (contributors).
// 3. `native/<target>/` inside this package: a maintainer's local build
//    (`dart bin/build_native.dart`) or, later, the pub.dev archive. A local
//    build made for another `native/gleon_ref` pin is rejected as stale.
// 4. The GitHub Release `v<package version>` of this repository: downloaded
//    once, verified against the release's SHA256SUMS.txt and cached in the
//    hooks runner's shared output directory (`.dart_tool/hooks_runner/shared`).
//
//   hooks:
//     user_defines:
//       gleon:
//         ffi_path: path/to/libgleon_ffi.dylib # use this library as is
//         gleon_repo: ../gleon                 # build from a gleon checkout
//         release_url: https://mirror/v1.2.3/  # download from a mirror instead
//
// Source builds are never a silent fallback: failures are actionable errors.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:gleon/src/hook/download.dart';
import 'package:gleon/src/hook/targets.dart';
import 'package:hooks/hooks.dart';

/// Must match the asset id used by the `@Native` bindings in `lib/src/native.dart`.
const _assetName = 'src/native.dart';
const _crate = 'gleon-ffi';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    final code = input.config.code;
    final target = _target(code.targetOS, code.targetArchitecture);

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
        target: target,
      );
    } else {
      library = await _prebuilt(input, output, target);
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

/// The requested target (not the host).
NativeTarget _target(OS os, Architecture arch) =>
    NativeTarget.byKey('${os.name}-${arch.name}') ??
    (throw UnsupportedError(
      'gleon: no native library for $os/$arch. Supported hosts for '
      '`flutter test`: ${NativeTarget.values.map((t) => t.key).join(', ')}. '
      'Web and on-device tests are not supported.',
    ));

Future<Uri> _prebuilt(
  BuildInput input,
  BuildOutputBuilder output,
  NativeTarget target,
) async {
  // A new local build must re-run the hook, so depend on the directory.
  final nativeDir = input.packageRoot.resolve('native/');
  output.dependencies.add(nativeDir);
  final bundled = File.fromUri(
    nativeDir.resolve('${target.key}/${target.libFileName}'),
  );
  if (bundled.existsSync()) {
    output.dependencies.add(bundled.uri);
    _rejectStaleBuild(nativeDir, target, output);
    return bundled.uri;
  }

  final pubspec = input.packageRoot.resolve('pubspec.yaml');
  output.dependencies.add(pubspec);
  final releaseUrl = switch (input.userDefines['release_url']) {
    final String url => Uri.parse(url.endsWith('/') ? url : '$url/'),
    null => defaultReleaseUrl(
      readPubspecVersion(File.fromUri(pubspec).readAsStringSync()) ??
          (throw StateError('gleon: no `version` in ${pubspec.toFilePath()}')),
    ),
    final other => throw StateError(
      'gleon: user-define `release_url` must be a string, got $other',
    ),
  };
  try {
    final library = await fetchReleaseLibrary(
      releaseUrl: releaseUrl,
      target: target,
      cacheDir: Directory.fromUri(input.outputDirectoryShared),
    );
    output.dependencies.add(library.uri);
    return library.uri;
  } on NativeDownloadException catch (error) {
    // Hook errors are printed verbatim; keep the actionable message on top.
    throw StateError(error.toString());
  }
}

/// A local build records the `native/gleon_ref` pin it was made for (see
/// `bin/build_native.dart`); after the pin moves, that library would silently
/// test an outdated engine. The pub.dev archive ships no pin, so no check.
void _rejectStaleBuild(
  Uri nativeDir,
  NativeTarget target,
  BuildOutputBuilder output,
) {
  final pin = File.fromUri(nativeDir.resolve(pinFileName));
  if (!pin.existsSync()) return;
  final stamp = File.fromUri(nativeDir.resolve('${target.key}/$pinFileName'));
  output.dependencies
    ..add(pin.uri)
    ..add(stamp.uri);
  final pinned = pin.readAsStringSync().trim();
  final builtFor = stamp.existsSync() ? stamp.readAsStringSync().trim() : null;
  if (builtFor != pinned) {
    throw StateError(
      'gleon: ${Directory.fromUri(nativeDir.resolve('${target.key}/')).path} '
      'was built for gleon ${builtFor ?? '(unknown)'}, but native/$pinFileName '
      'pins $pinned. Rebuild it with `dart bin/build_native.dart`, or delete '
      'that directory to download the released library.',
    );
  }
}

Future<Uri> _buildFromSource({
  required Uri repoRoot,
  required BuildInput input,
  required BuildOutputBuilder output,
  required NativeTarget target,
}) async {
  final triple = target.rustTriple;
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
  final result = await Process.run(
    cargo,
    [
      'build',
      '--release',
      '--locked',
      '--package',
      _crate,
      '--target',
      triple,
      '--target-dir',
      targetDir.toFilePath(),
    ],
    workingDirectory: root.toFilePath(),
    environment: target.cargoEnvironment(Platform.environment),
  );
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

  final library = targetDir.resolve('$triple/release/${target.libFileName}');
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
