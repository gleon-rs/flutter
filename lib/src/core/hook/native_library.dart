import 'dart:io';

import 'native_download_exception.dart';
import 'native_target.dart';
import 'release_download.dart';
import 'source_build.dart';
import 'user_defines.dart';

/// Finds the `gleon-ffi` library the build hook (`hook/build.dart`) provides.
/// Consumers never need Rust. The library is resolved in this order:
///
/// 1. User-define `ffi_path`: this exact file.
/// 2. User-define `gleon_repo`: a cargo build from a gleon checkout
///    (contributors, see [SourceBuild]).
/// 3. `native/<target>/` inside this package: a maintainer's local build
///    (`dart bin/build_native.dart`) or the pub.dev archive. A local build
///    made for another `native/gleon_ref` pin is rejected as stale.
/// 4. The GitHub Release `v<package version>` of this repository, or the
///    mirror named by the `release_url` user-define: downloaded once,
///    verified against the release's `SHA256SUMS.txt` and cached in the
///    hooks runner's shared output directory
///    (`.dart_tool/hooks_runner/shared`), see [ReleaseDownload].
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
/// Plain Dart (no Flutter imports): used by the build hook and tested
/// directly.
final class NativeLibrary {
  /// Resolves the library of [target] for the package at [packageRoot].
  const NativeLibrary({
    required this.packageRoot,
    required this.userDefines,
    required this.sharedOutputDir,
    required this.target,
    required this.environment,
  });

  /// The root of this package (with `pubspec.yaml` and `native/`).
  final Uri packageRoot;

  /// The user-defines of the app.
  final UserDefines userDefines;

  /// The hooks runner's output directory shared across builds (cargo's
  /// target directory, the download cache).
  final Uri sharedOutputDir;

  /// The requested target (not the host).
  final NativeTarget target;

  /// The hook's process environment (what the hooks runner forwards).
  final Map<String, String> environment;

  /// The library and the files it came from, in the order of the class
  /// documentation; [runProcess] runs cargo for `gleon_repo` builds.
  Future<({List<Uri> dependencies, Uri library})> resolve({
    ProcessRunner runProcess = Process.run,
  }) async {
    if (userDefines.path('ffi_path') case final override?) {
      if (!File.fromUri(override).existsSync()) {
        throw StateError(
          'gleon: user-define `ffi_path` points to a missing file: '
          '${override.toFilePath()}',
        );
      }

      return (dependencies: [override], library: override);
    }
    if (userDefines.path('gleon_repo') case final gleonRepo?) {
      return await SourceBuild.run(
        repoRoot: gleonRepo,
        targetDir: sharedOutputDir.resolve('cargo/'),
        target: target,
        environment: environment,
        runProcess: runProcess,
      );
    }

    return await _prebuilt();
  }

  Future<({List<Uri> dependencies, Uri library})> _prebuilt() async {
    // A new local build must re-run the hook, so depend on the directory.
    final nativeDir = packageRoot.resolve('native/');
    final bundled = File.fromUri(
      nativeDir.resolve('${target.key}/${target.libFileName}'),
    );
    if (bundled.existsSync()) {
      return (
        dependencies: [nativeDir, bundled.uri, ..._rejectStaleBuild(nativeDir)],
        library: bundled.uri,
      );
    }
    final pubspec = packageRoot.resolve('pubspec.yaml');
    final version =
        ReleaseDownload.readPubspecVersion(
          File.fromUri(pubspec).readAsStringSync(),
        ) ??
        (throw StateError('gleon: no `version` in ${pubspec.toFilePath()}'));
    final releaseUrl = switch (userDefines['release_url']) {
      final String url => Uri.parse(url.endsWith('/') ? url : '$url/'),
      null => ReleaseDownload.defaultUrl(version),
      final other => throw StateError(
        'gleon: user-define `release_url` must be a string, got $other',
      ),
    };
    try {
      final library = await ReleaseDownload.fetchLibrary(
        releaseUrl: releaseUrl,
        packageVersion: version,
        target: target,
        cacheDir: Directory.fromUri(sharedOutputDir),
      );

      return (
        dependencies: [nativeDir, pubspec, library.uri],
        library: library.uri,
      );
    } on NativeDownloadException catch (error, stackTrace) {
      // Hook errors are printed verbatim; keep the actionable message on top.
      Error.throwWithStackTrace(StateError(error.toString()), stackTrace);
    }
  }

  /// A local build records the gleon commit it was made from (see
  /// `bin/build_native.dart`); a build of another commit, or of an old pin
  /// after the pin moved, would silently test another engine. The pub.dev
  /// archive ships no pin, so no check. Returns the files checked.
  List<Uri> _rejectStaleBuild(Uri nativeDir) {
    const pinFile = NativeTarget.pinFileName;
    final pin = File.fromUri(nativeDir.resolve(pinFile));
    if (!pin.existsSync()) return const [];
    final targetDir = nativeDir.resolve('${target.key}/');
    final stamp = File.fromUri(targetDir.resolve(pinFile));
    final pinned = pin.readAsStringSync().trim();
    final builtFrom = stamp.existsSync()
        ? stamp.readAsStringSync().trim()
        : null;
    if (!NativeTarget.isBuildOfPin(builtFrom, pinned)) {
      throw StateError(
        'gleon: ${Directory.fromUri(targetDir).path} was built from gleon '
        '${builtFrom ?? '(unknown)'}, but native/$pinFile pins $pinned. '
        'Rebuild it from the pinned commit with `dart bin/build_native.dart`, '
        'build from any checkout with the `gleon_repo` user-define, or delete '
        'that directory to download the released library.',
      );
    }

    return [pin.uri, stamp.uri];
  }
}
