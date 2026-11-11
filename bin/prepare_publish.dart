/// Prepares the pub.dev archive of a release: a clone of the tag `v<version>`
/// with the four libraries of its GitHub Release in `native/<target>/`,
/// checked by `flutter pub publish --dry-run`. It never publishes: it prints
/// the command that does.
///
/// ```sh
/// fvm dart bin/prepare_publish.dart [--version <x.y.z>] [--release-url <url>]
///   [--work-dir <dir>]
/// ```
///
/// Publish only from the copy it prepares: the working tree has no libraries
/// of the release (and may have a local build of one target). The release
/// workflow must have published the release of the tag first.
///
/// Only `dart:*`, `crypto`, this package and `src/` may be imported here (see
/// `build_native.dart`).
library;

import 'dart:io';

import 'package:gleon/src/core/hook/release_download.dart';

import 'src/check_failure.dart';
import 'src/cli.dart';
import 'src/publish_bundle.dart';

const _cli = Cli('prepare_publish', '''
Usage: dart bin/prepare_publish.dart [--version <x.y.z>] [--release-url <url>]
  [--work-dir <dir>]

  --version <x.y.z>    the version to publish (default: pubspec.yaml); the tag
                       v<x.y.z> must exist here and its GitHub Release online
  --release-url <url>  where the libraries of the release are (default: the
                       GitHub Release of the tag)
  --work-dir <dir>     where the copy goes (default: a new temporary directory)
''');

Future<void> main(List<String> args) async {
  final options = _parse(args);
  final root = await _cli.packageRoot();
  final version =
      options.version ??
      ReleaseDownload.readPubspecVersion(
        File.fromUri(root.resolve('pubspec.yaml')).readAsStringSync(),
      ) ??
      _cli.fail('pubspec.yaml has no version.');
  final work =
      options.workDir ?? Directory.systemTemp.createTempSync('gleon_publish_');
  final copy = Directory('${work.path}/gleon');
  final cache = Directory('${work.path}/cache');
  // Never what was there before: a work directory of its own goes whole,
  // else only what this run made in it.
  if (copy.existsSync() || cache.existsSync()) {
    _cli.fail('${work.path} holds gleon/ or cache/: pass another --work-dir.');
  }
  final made = options.workDir == null ? [work] : [copy, cache];
  final interrupts = [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ].map((signal) => signal.watch().listen((_) => _interrupted(made))).toList();
  try {
    await _clone(root, version: version, copy: copy);
    final releaseUrl =
        options.releaseUrl ?? ReleaseDownload.defaultUrl(version);
    stdout.writeln('Adding the libraries of $releaseUrl ...');
    await bundleLibraries(
      package: copy,
      releaseUrl: releaseUrl,
      version: version,
      cacheDir: cache,
    );
    await _checkArchive(copy);
    stdout.writeln('''
The archive of gleon $version is ready in ${copy.path}:
the libraries of the four hosts, nothing only maintainers need. Publish it:

  cd ${copy.path} && fvm flutter pub publish
''');
  } on CheckFailure catch (error) {
    _remove(made);
    _cli.report(error.message);
  } finally {
    // The downloads are in the copy now.
    _remove([cache]);
    for (final interrupt in interrupts) {
      await interrupt.cancel();
    }
  }
}

/// Removes what [made] holds after an interrupt (Ctrl+C skips `finally`) and
/// exits as an interrupted process does.
void _interrupted(List<Directory> made) {
  stderr.writeln('prepare_publish: interrupted, cleaning up.');
  _remove(made);
  exit(130);
}

/// Deletes each of [dirs] that exists.
void _remove(List<Directory> dirs) {
  for (final dir in dirs) {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// Clones the tag of [version] of the package at [root] into [copy]: exactly
/// the files the tag tracks.
///
/// Throws a [CheckFailure] when the tag is not here or names another version.
Future<void> _clone(
  Uri root, {
  required String version,
  required Directory copy,
}) async {
  final tag = 'v$version';
  stdout.writeln('Cloning $tag into ${copy.path} ...');
  final clone = await Process.run('git', [
    'clone',
    '--quiet',
    '--branch',
    tag,
    root.toFilePath(),
    copy.path,
  ]);
  if (clone.exitCode != 0) {
    throw CheckFailure(
      'cannot clone the tag $tag (fetch it with `git fetch --tags`):\n'
      '${clone.stderr}',
    );
  }
  final tagged = ReleaseDownload.readPubspecVersion(
    File('${copy.path}/pubspec.yaml').readAsStringSync(),
  );
  if (tagged != version) {
    throw CheckFailure(
      'the pubspec.yaml of $tag names version ${tagged ?? '(none)'}, not '
      '$version.',
    );
  }
}

/// Runs `flutter pub publish --dry-run` in [copy].
///
/// Throws a [CheckFailure] unless pub accepts the archive without a warning
/// and [archiveProblems] finds none.
Future<void> _checkArchive(Directory copy) async {
  stdout.writeln('Checking the archive with flutter pub publish --dry-run ...');
  final dryRun = await Process.run(
    'flutter',
    const ['pub', 'publish', '--dry-run'],
    workingDirectory: copy.path,
    runInShell: Platform.isWindows,
  );
  final output = '${dryRun.stdout}\n${dryRun.stderr}';
  if (dryRun.exitCode != 0) {
    throw CheckFailure(
      'flutter pub publish --dry-run failed with exit code '
      '${dryRun.exitCode}:\n$output',
    );
  }
  final problems = archiveProblems(archiveFiles(output));
  if (problems.isNotEmpty) throw CheckFailure(problems.join('\n'));
}

({Uri? releaseUrl, String? version, Directory? workDir}) _parse(
  List<String> args,
) {
  Uri? releaseUrl;
  String? version;
  Directory? workDir;
  final rest = args.iterator;
  while (rest.moveNext()) {
    switch (rest.current) {
      case '--release-url':
        final url = _cli.value(rest);
        releaseUrl = Uri.parse(url.endsWith('/') ? url : '$url/');

      case '--version':
        version = _cli.value(rest);

      case '--work-dir':
        workDir = Directory(_cli.value(rest)).absolute;

      case '-h' || '--help':
        _cli.help();

      case final other:
        _cli.failUsage('unknown argument $other.');
    }
  }

  return (releaseUrl: releaseUrl, version: version, workDir: workDir);
}
