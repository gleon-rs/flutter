/// Build hook that provides the `gleon-ffi` native library to Dart.
///
/// Consumers never need Rust. The library is resolved in this order:
///
/// 1. User-define `ffi_path`: this exact file.
/// 2. User-define `gleon_repo`: a cargo build from a gleon checkout
///    (contributors, see `lib/src/core/hook/source_build.dart`).
/// 3. `native/<target>/` inside this package: a maintainer's local build
///    (`dart bin/build_native.dart`) or, later, the pub.dev archive. A local
///    build made for another `native/gleon_ref` pin is rejected as stale.
/// 4. The GitHub Release `v<package version>` of this repository: downloaded
///    once, verified against the release's `SHA256SUMS.txt` and cached in the
///    hooks runner's shared output directory
///    (`.dart_tool/hooks_runner/shared`).
///
/// ```yaml
/// hooks:
///   user_defines:
///     gleon:
///       ffi_path: path/to/libgleon_ffi.dylib # use this library as is
///       gleon_repo: ../gleon                 # build from a gleon checkout
///       release_url: https://mirror/v1.2.3/  # download from a mirror
/// ```
///
/// Source builds are never a silent fallback: failures are actionable errors.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:gleon/src/core/hook/native_download_exception.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/release_download.dart';
import 'package:gleon/src/core/hook/source_build.dart';
import 'package:hooks/hooks.dart';

/// Must match the `@DefaultAsset` of `lib/src/core/native/gleon_ffi.dart`.
const _assetName = 'src/core/native/gleon_ffi.dart';

Future<void> main(List<String> args) => build(args, _build);

Future<void> _build(BuildInput input, BuildOutputBuilder output) async {
  if (!input.config.buildCodeAssets) return;
  final CodeConfig(:targetArchitecture, :targetOS) = input.config.code;
  final library = await _library(
    input,
    output,
    _target(targetOS, targetArchitecture),
  );
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: _assetName,
      linkMode: DynamicLoadingBundled(),
      file: library,
    ),
  );
}

/// The requested target (not the host).
NativeTarget _target(OS os, Architecture arch) =>
    NativeTarget.byKey('${os.name}-${arch.name}') ??
    (throw UnsupportedError(
      'gleon: no native library for $os/$arch. Supported hosts for '
      '`flutter test`: ${NativeTarget.keys}. '
      'Web and on-device tests are not supported.',
    ));

Future<Uri> _library(
  BuildInput input,
  BuildOutputBuilder output,
  NativeTarget target,
) async {
  final userDefines = input.userDefines;
  if (userDefines.path('ffi_path') case final override?) {
    output.dependencies.add(override);
    if (!File.fromUri(override).existsSync()) {
      throw StateError(
        'gleon: user-define `ffi_path` points to a missing file: '
        '${override.toFilePath()}',
      );
    }

    return override;
  }
  if (userDefines.path('gleon_repo') case final gleonRepo?) {
    final built = await SourceBuild.run(
      repoRoot: gleonRepo,
      targetDir: input.outputDirectoryShared.resolve('cargo/'),
      target: target,
      environment: Platform.environment,
    );
    output.dependencies.addAll(built.dependencies);

    return built.library;
  }

  return await _prebuilt(input, output, target);
}

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
    null => ReleaseDownload.defaultUrl(
      ReleaseDownload.readPubspecVersion(
            File.fromUri(pubspec).readAsStringSync(),
          ) ??
          (throw StateError('gleon: no `version` in ${pubspec.toFilePath()}')),
    ),
    final other => throw StateError(
      'gleon: user-define `release_url` must be a string, got $other',
    ),
  };
  try {
    final library = await ReleaseDownload.fetchLibrary(
      releaseUrl: releaseUrl,
      target: target,
      cacheDir: Directory.fromUri(input.outputDirectoryShared),
    );
    output.dependencies.add(library.uri);

    return library.uri;
  } on NativeDownloadException catch (error, stackTrace) {
    // Hook errors are printed verbatim; keep the actionable message on top.
    Error.throwWithStackTrace(StateError(error.toString()), stackTrace);
  }
}

/// A local build records the gleon commit it was made from (see
/// `bin/build_native.dart`); a build of another commit, or of an old pin after
/// the pin moved, would silently test another engine. The pub.dev archive
/// ships no pin, so no check.
void _rejectStaleBuild(
  Uri nativeDir,
  NativeTarget target,
  BuildOutputBuilder output,
) {
  const pinFile = NativeTarget.pinFileName;
  final pin = File.fromUri(nativeDir.resolve(pinFile));
  if (!pin.existsSync()) return;
  final targetDir = nativeDir.resolve('${target.key}/');
  final stamp = File.fromUri(targetDir.resolve(pinFile));
  output.dependencies
    ..add(pin.uri)
    ..add(stamp.uri);
  final pinned = pin.readAsStringSync().trim();
  final builtFrom = stamp.existsSync() ? stamp.readAsStringSync().trim() : null;
  if (!NativeTarget.isBuildOfPin(builtFrom, pinned)) {
    throw StateError(
      'gleon: ${Directory.fromUri(targetDir).path} was built from gleon '
      '${builtFrom ?? '(unknown)'}, but native/$pinFile pins $pinned. '
      'Rebuild it from the pinned commit with `dart bin/build_native.dart`, '
      'build from any checkout with the `gleon_repo` user-define, or delete '
      'that directory to download the released library.',
    );
  }
}
