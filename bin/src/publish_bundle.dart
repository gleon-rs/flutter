/// The pub.dev archive of this package: the libraries of a release put into
/// `native/<target>/` of a copy of its tag (`.pubignore` keeps them in the
/// archive), and the check of the files of the archive pub packs.
///
/// Only `dart:*`, `crypto` and this package may be imported here (see
/// `build_native.dart`).
library;

import 'dart:io';

import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/release_download.dart';

import 'check_failure.dart';

/// Puts the library of every target of the release at [releaseUrl] (of
/// package [version]) into `native/<target>/` of [package]: each file of the
/// release is downloaded once.
///
/// Each library is verified against the checksum list of the release, and
/// the release must name the gleon commit of its libraries
/// (`gleon_ref.txt`, every release since 0.5.0 does), equal to the pin of
/// [package] (`native/gleon_ref`). Downloads are cached in [cacheDir]. Every
/// failure is a [CheckFailure] with the hook's message.
Future<void> bundleLibraries({
  required Directory package,
  required Uri releaseUrl,
  required String version,
  required Directory cacheDir,
}) async {
  final pin =
      NativeTarget.readPin(package.uri) ??
      (throw CheckFailure(
        '${package.path} has no native/${NativeTarget.pinFileName}.',
      ));
  final bundle = PublishBundle(
    package: package,
    releaseUrl: releaseUrl,
    version: version,
    cacheDir: cacheDir,
    pin: pin,
  );
  // The first target caches the checksum list and the pin of the release in
  // [cacheDir]; the others then download their library only, at once.
  final [first, ...others] = NativeTarget.values;
  await bundle.add(first);
  await Future.wait(others.map(bundle.add));
}

/// The libraries of one release going into one copy of the package (see
/// [bundleLibraries]).
final class PublishBundle {
  /// The libraries of the release at [releaseUrl] (of package [version]) for
  /// [package], which pins [pin]; downloads are cached in [cacheDir].
  const new({
    required this.package,
    required this.releaseUrl,
    required this.version,
    required this.cacheDir,
    required this.pin,
  });

  final Directory package;
  final Uri releaseUrl;
  final String version;
  final Directory cacheDir;
  final String pin;

  /// Puts the verified library of [target] into `native/<target>/`.
  Future<void> add(NativeTarget target) async {
    final File library;
    try {
      library = await ReleaseDownload.fetchLibrary(
        releaseUrl: releaseUrl,
        packageVersion: version,
        target: target,
        cacheDir: cacheDir,
        pin: pin,
      );
      // ignore: avoid_catching_errors, the hook's download and verification failures are StateErrors with an actionable message.
    } on StateError catch (error, stackTrace) {
      Error.throwWithStackTrace(CheckFailure(error.message), stackTrace);
    }
    final bundled = File.fromUri(target.bundledLibrary(package.uri))
      ..parent.createSync(recursive: true);
    library.copySync(bundled.path);
  }
}

/// What is wrong with an archive of [files] (`PubArchive.files`): a file every
/// archive has missing, the library of a
/// target missing, anything else in `native/` (a pin, a build stamp), or
/// anything only maintainers need ([maintainerOnly]). Empty when the archive
/// is right.
List<String> archiveProblems(List<String> files) {
  final libraries = {
    for (final target in NativeTarget.values) _bundled(target),
  };

  return [
    for (final file in alwaysShipped)
      if (!files.contains(file)) 'the archive lacks $file',
    for (final library in libraries)
      if (!files.contains(library)) 'the archive lacks $library',
    for (final file in files)
      if ((file.startsWith('native/') && !libraries.contains(file)) ||
          maintainerOnly.any(
            (path) => file == path || file.startsWith('$path/'),
          ))
        'the archive holds $file, which consumers must not get',
  ];
}

/// Files the archive always holds: the package itself, and the notice it must
/// carry (`NATIVE_LICENSES.md`: the licenses of the crates in the libraries).
const alwaysShipped = [
  'CHANGELOG.md',
  'LICENSE',
  'NATIVE_LICENSES.md',
  'README.md',
  'hook/build.dart',
  'lib/gleon.dart',
  'pubspec.yaml',
];

/// Where the archive keeps the library of [target], relative to its root.
String _bundled(NativeTarget target) =>
    'native/${target.key}/${target.libFileName}';

/// The paths (relative to the package root) only maintainers need: what
/// `.pubignore` leaves out at the top level (but `native/gleon_ref`), the
/// hidden `.github/` and `.antigravity/`, and what builds, tests and runs leave
/// in the package and its example (`.pubignore` and the example's
/// `.gleon/.gitignore` leave them out; this checks it).
const maintainerOnly = {
  '.antigravity',
  '.github',
  'CLAUDE.local.md',
  'benchmark',
  'bin',
  'build',
  'coverage',
  'dist',
  'doc/api',
  'example/.gleon/runs',
  'example/benchmark',
  'example/build',
  'example/test/failures',
  'pubspec.lock',
  'test',
};
