/// The pub.dev archive of this package: the libraries of a release put into
/// `native/<target>/` of a copy of its tag (`.pubignore` keeps them in the
/// archive), and the check of what `pub publish --dry-run` lists.
///
/// Only `dart:*`, `crypto` and this package may be imported here (see
/// `build_native.dart`).

// The tree of `pub publish --dry-run` is drawn with box characters.
// ignore_for_file: avoid-non-ascii-symbols
library;

import 'dart:convert';
import 'dart:io';

import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/release_download.dart';

import 'check_failure.dart';
import 'consumer_app.dart';

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
        isPinRequired: true,
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

/// The files `pub publish --dry-run` lists in its [output], relative to the
/// package root and `/`-separated.
///
/// Its tree draws each entry after `├── ` or `└── `, four characters deeper
/// per level. pub lists files only, so an entry followed by deeper ones is a
/// directory and every other one a file, whatever pub prints after a name (a
/// size in parentheses, stripped when it looks like one).
List<String> archiveFiles(String output) {
  final entries = [
    for (final line in const LineSplitter().convert(output))
      if (_entry.firstMatch(line.trimRight()) case final match?)
        (
          depth: (match.group(1) ?? _none).length ~/ _indent,
          name: match.group(2) ?? _none,
        ),
  ];
  final dirs = <String>[];
  final files = <String>[];
  for (final (index, (:depth, :name)) in entries.indexed) {
    while (dirs.length > depth) {
      dirs.removeLast();
    }
    final next = entries.elementAtOrNull(index + 1);
    if (next != null && next.depth > depth) {
      dirs.add(name);
    } else {
      files.add([...dirs, name].join('/'));
    }
  }

  return files;
}

/// What is wrong with an archive of [files] (see [archiveFiles]): a file every
/// archive has missing (so the list was not read right), the library of a
/// target missing, anything else in `native/` (a pin, a build stamp), or
/// anything only maintainers need ([maintainerOnly]). Empty when the archive
/// is right.
List<String> archiveProblems(List<String> files) {
  final libraries = {
    for (final target in NativeTarget.values) _bundled(target),
  };

  return [
    for (final file in alwaysShipped)
      if (!files.contains(file))
        'the archive lacks $file (or the file list of pub was not read right)',
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

/// Files the archive always holds: without them in the list of pub, the list
/// was not read right ([archiveFiles]), or the archive lacks a notice it must
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

/// The paths (relative to the package root) only maintainers need: the top
/// level a consumer never gets ([notShipped], which a test keeps in sync with
/// `.pubignore`) but `example/` and `native/`, which ship, the hidden
/// `.github/` and `.antigravity/`, and what builds, tests and runs leave in
/// the package and its example (`.pubignore` and the example's
/// `.gleon/.gitignore` leave them out; this checks it).
final maintainerOnly = <String>{
  ...notShipped.difference(const {'example', 'native'}),
  '.antigravity',
  '.github',
  'doc/api',
  'example/.gleon/runs',
  'example/benchmark',
  'example/build',
  'example/test/failures',
};

/// An entry of the tree of `pub publish --dry-run`: its indentation (group
/// 1) and its name (group 2), without the size of a file.
final _entry = RegExp(
  r'^((?:│   |    )*)[├└]── (.+?)(?: \(<?[\d.]+ [KMGT]?B\))?$',
);

/// The characters of one level of the tree.
const _indent = 4;

const _none = '';
