import 'dart:io';

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
/// The first that applies wins: `release_url` only says where step 4
/// downloads from, so a library in `native/<target>/` (a local build, the
/// pub.dev archive) is used before it. Source builds are never a silent
/// fallback: failures are actionable errors, and a path user-define set to
/// anything but a path is one too.
///
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
  Future<SourceBuildOutput> resolve({
    ProcessRunner runProcess = Process.run,
  }) async {
    if (_path('ffi_path') case final override?) {
      if (!File.fromUri(override).existsSync()) {
        throw StateError(
          'gleon: user-define `ffi_path` points to a missing file: '
          '${override.toFilePath()}',
        );
      }

      return (dependencies: [override], library: override);
    }
    if (_path('gleon_repo') case final gleonRepo?) {
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

  /// The path the user-define [key] holds, or null when it is not set.
  ///
  /// Throws a [StateError] for a value that is set but not a path (a
  /// number, a list), which would otherwise fall through silently.
  Uri? _path(String key) {
    final path = userDefines.path(key);
    final value = userDefines[key];
    if (path == null && value != null) {
      throw StateError('gleon: user-define `$key` must be a path, got $value');
    }

    return path;
  }

  Future<SourceBuildOutput> _prebuilt() async {
    const pinFile = NativeTarget.pinFileName;
    final nativeDir = packageRoot.resolve('native/');
    final targetDir = nativeDir.resolve('${target.key}/');
    final bundled = File.fromUri(targetDir.resolve(target.libFileName));
    final stamp = File.fromUri(targetDir.resolve(pinFile));
    // Present or not: the hooks runner hashes a directory by its direct
    // children only and re-runs the hook when a missing file appears, so a
    // later local build (or a moved pin) is seen in either branch.
    final inputs = [
      nativeDir,
      bundled.uri,
      nativeDir.resolve(pinFile),
      stamp.uri,
    ];
    if (bundled.existsSync()) {
      _rejectStaleBuild(
        pinned: NativeTarget.readPin(packageRoot),
        stamp: stamp,
        targetDir: targetDir,
      );

      return (dependencies: inputs, library: bundled.uri);
    }
    final pubspec = packageRoot.resolve('pubspec.yaml');
    final version =
        ReleaseDownload.readPubspecVersion(
          File.fromUri(pubspec).readAsStringSync(),
        ) ??
        (throw StateError('gleon: no `version` in ${pubspec.toFilePath()}'));
    final releaseUrl = switch (userDefines['release_url']) {
      final String url => _releaseUrl(url),
      null => ReleaseDownload.defaultUrl(version),
      final other => throw StateError(
        'gleon: user-define `release_url` must be a string, got $other',
      ),
    };
    final library = await ReleaseDownload.fetchLibrary(
      releaseUrl: releaseUrl,
      packageVersion: version,
      target: target,
      cacheDir: Directory.fromUri(sharedOutputDir),
    );

    return (
      dependencies: [...inputs, pubspec, library.uri],
      library: library.uri,
    );
  }

  /// The `release_url` [url] as the directory its files are resolved in.
  ///
  /// Throws a [StateError] for a query or fragment: resolving the checksum
  /// list and the assets against the URL would drop them.
  static Uri _releaseUrl(String url) {
    final uri = Uri.parse(url);
    if (uri.hasQuery || uri.hasFragment) {
      throw StateError(
        'gleon: user-define `release_url` must not have a query or fragment '
        '(the files are resolved against it), got $url',
      );
    }

    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }

  /// A local build records the gleon commit it was made from in its
  /// [stamp] (see `bin/build_native.dart`); a build of another commit, or of
  /// an old pin after the pin moved to [pinned], would silently test another
  /// engine. The pub.dev archive ships no pin, so no check.
  static void _rejectStaleBuild({
    required String? pinned,
    required File stamp,
    required Uri targetDir,
  }) {
    if (pinned == null) return;
    final builtFrom = stamp.existsSync()
        ? stamp.readAsStringSync().trim()
        : null;
    if (!NativeTarget.isBuildOfPin(builtFrom, pinned)) {
      throw StateError(
        'gleon: ${Directory.fromUri(targetDir).path} was built from gleon '
        '${builtFrom ?? '(unknown)'}, but native/${NativeTarget.pinFileName} '
        'pins $pinned. Rebuild it from the pinned commit with '
        '`dart bin/build_native.dart`, build from any checkout with the '
        '`gleon_repo` user-define, or delete that directory to download the '
        'released library.',
      );
    }
  }
}
